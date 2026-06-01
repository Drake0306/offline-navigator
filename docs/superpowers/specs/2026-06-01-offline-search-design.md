# Milestone 2b — Offline Search (Design Spec)

- **Date:** 2026-06-01
- **Status:** Approved (design); pending spec review → implementation plan
- **Project:** Offline-first Android + iOS navigation app ("Offline Navigator")
- **This milestone:** search named destinations (places, POIs, roads, water) fully offline, then center the map + drop a marker on the chosen result.

---

## 1. Context

Milestone 1 delivered the offline map foundation (MapLibre vector tiles from a bundled
`ghatshila.pmtiles` served on `127.0.0.1`, GPS arrow pointer, 2.5D tilt, follow camera).
Milestone 2a added auto dark mode + a 4-style switcher and fixed the location-permission prompt.
This milestone adds **offline destination search**. Full A→B routing with stops is a SEPARATE later
milestone (Milestone 3) — this milestone stops at "find a place and show it on the map."

The bundled Protomaps tile pack's `places`, `pois`, `roads`, and `water` layers carry `name`,
`name:en`, and localized name fields (incl. Devanagari) — confirmed by inspecting the pack's
vector-layer metadata. But rather than search the tiles (lossy at low zoom), we build a dedicated
search index from raw OpenStreetMap data (the user's chosen, most-accurate approach).

## 2. Goal

A search icon on the map opens a full-screen search page. Typing shows live (search-as-you-type)
results drawn from a prebuilt, on-device SQLite FTS5 index of named features, ranked by distance
from the user (text relevance as tiebreak). Selecting a result returns to the map, centers + zooms
to it, drops a destination marker, and shows an info card (name, kind, distance). Works fully
offline after first launch.

## 3. Decisions (locked)

| Area | Decision |
|---|---|
| Searchable features | **Places, POIs, roads, and water** (all four) |
| Index source | **Dedicated index from raw OSM** — build-time extract → bundled SQLite FTS5 DB |
| Storage / engine | SQLite **FTS5** via the `sqflite` package; DB copied to storage on first launch (version-stamped) |
| Result action | **Center map + drop a destination marker** + dismissible info card (name, kind, distance) |
| Search UI | **Search icon → full-screen search page** (bar + live results); returns to map on select |
| Ranking | **Distance from user, then text match**; falls back to map-center distance if no GPS fix |
| Routing | OUT OF SCOPE — Milestone 3 |

## 4. Scope

**In scope**
- Build-time pipeline: clip raw OSM to the Ghatshila bbox (`86.35,22.45,86.65,22.75`), extract named
  places/POIs/roads/water, write `assets/search/ghatshila.sqlite` (FTS5 over names + a row table).
- `SearchService`: copy the bundled DB to storage (version-stamped), open via `sqflite`, run
  prefix FTS queries, rank distance-then-text, return `SearchResult`s.
- `SearchScreen`: full-screen search with a debounced live results list; returns the chosen result.
- `MapScreen`: a search entry icon; on a returned result, animate camera + drop a `destination`
  GeoJSON marker (robust across style swaps via the same `…SourceReady` guard the pointer uses) +
  show an info card.

**Out of scope (later / not this milestone)**
- A→B routing, stops, turn-by-turn (Milestone 3).
- Search history / favorites, autocomplete suggestions beyond name matching, category browsing.
- Multi-region search (only the bundled Ghatshila DB; the download-manager milestone generalizes this).

## 5. Architecture

```
SearchScreen (new, full-screen)
  ├── TextField + debounced live results ListView
  └── on tap → Navigator.pop(SearchResult)
        │ queries
        ▼
SearchService (new)
  • ensureReady(): copy bundled search.sqlite → storage (version-stamped), open via sqflite
  • Future<List<SearchResult>> query(String text, {LatLng? origin, int limit})
  • dispose()
        │ reads
        ▼
search.sqlite (bundled asset: assets/search/ghatshila.sqlite)
  • features(id, name, name_en, kind, lat, lon)
  • features_fts FTS5(name, name_en) contentless-linked to features
        ▲ built by
tool/generate_search_index.* (build-time; NOT shipped in the app)

MapScreen (modified)
  ├── search icon (top-left) → push SearchScreen
  └── on returned SearchResult → animate camera + set `destination` source/layer + info card
```

**Units & responsibilities**
- **`SearchResult`** — immutable `{name, kind, lat, lng, distanceM?}`; haversine helper; testable.
- **`SearchService`** — owns the DB lifecycle and querying + ranking. Single responsibility.
- **`SearchScreen`** — the search UI; debounces input (~200ms), drops stale in-flight results.
- **`MapScreen`** (modified) — search entry + destination marker + info card; reuses the pointer's
  source/layer + ready-guard pattern so the marker survives style swaps (no iOS missing-source throw).

**New dependency:** `sqflite` (standard Flutter SQLite, FTS5-capable, Android + iOS).
**New build dependency:** an OSM extractor (`osmium`/`pyosmium`) to filter the pbf — not yet installed
(plan Task 0 installs it, as we did for the `pmtiles` CLI).

## 6. Data flow

**Build-time (scripted, once):**
1. Obtain a raw OSM extract covering the bbox (e.g. a Geofabrik Jharkhand `.osm.pbf`, clipped with
   `osmium extract --bbox`).
2. Filter to named features in places/POIs/roads/water; for each, capture display `name`, romanized
   `name_en` (from `name:en` or transliteration when available), a normalized `kind`, and a
   representative `lat/lon` (point for nodes; centroid for ways/areas).
3. Write `search.sqlite`: insert rows into `features`, build `features_fts`. Bundle under
   `assets/search/`. (Document the exact commands in `tool/generate_search_index`.)

**Runtime:**
1. On first launch (or version bump), `SearchService.ensureReady()` copies the DB to app storage and
   opens it. (Version-stamped like the tile assets.)
2. Each keystroke (debounced ~200ms): `query(text, origin, limit:30)` runs an FTS5 **prefix** match
   (`name MATCH '<term>*'`), joined to `features` for `kind`/`lat`/`lon`.
3. Rank in Dart: haversine distance from `origin` (GPS fix, else map center) ascending; tiebreak by
   text-match quality (exact/prefix above deeper matches). Fill `distanceM`. Return top N.
4. `SearchScreen` renders the list; selection pops the `SearchResult`.
5. `MapScreen` animates the camera to it, updates the `destination` GeoJSON source (pin layer), and
   shows the info card. Selecting another result moves the same marker.

## 7. Schema

```sql
CREATE TABLE features(
  id      INTEGER PRIMARY KEY,
  name    TEXT NOT NULL,   -- display name (local script when that's all OSM has)
  name_en TEXT,            -- romanized/English (name:en) when available
  kind    TEXT NOT NULL,   -- 'place' | 'poi' | 'road' | 'water' (+ optional subkind)
  lat     REAL NOT NULL,
  lon     REAL NOT NULL
);
CREATE VIRTUAL TABLE features_fts USING fts5(
  name, name_en, content='features', content_rowid='id',
  tokenize="unicode61 remove_diacritics 2"
);
```
Indexing both `name` and `name_en` lets a user type English or local script and match the same row.
`unicode61 remove_diacritics` normalizes accents/scripts for forgiving matching.

## 8. Error handling & edge cases

- **DB missing/corrupt/open-fails** → `ensureReady` surfaces an error; `SearchScreen` shows a
  "Search unavailable / Retry" state; the map keeps working. No crash.
- **No GPS fix** → rank by map-center distance; labels still shown relative to map center.
- **Empty/whitespace query** → empty results, no DB hit.
- **Huge match set** → `limit:30`, distance-sorted, nearest on top.
- **Rapid typing** → debounce ~200ms; ignore stale in-flight results (guard by a query sequence id).
- **Destination marker across style swaps** → reuse the pointer's `…SourceReady` guard so the marker
  is re-added on the new style and never updates a missing source (the iOS-crash class we fixed).
- **Unnamed features** → not indexed (expected rural coverage gap); documented, not an error.
- **Offline guarantee** → local DB + local `sqflite`; zero network in the query path.

## 9. Testing

- **Unit — `SearchResult`:** haversine distance (known coords → known metres); equality.
- **Unit — `SearchService` ranking:** seed a temp SQLite with a few rows; assert distance-then-text
  ordering, prefix matching, `name` vs `name_en` dual-match (type Latin → matches a
  Devanagari-named row), `limit` cap, empty-query → empty, and the no-origin (map-center) fallback.
- **Unit — build script sanity:** a small fixture input → DB has the expected schema + rows. If a real
  `.osm.pbf` fixture is too heavy, assert schema + a hand-seeded insert/query path instead.
- **Widget — `SearchScreen`:** typing shows results (mocked service); tap pops the chosen result;
  the "Search unavailable" error state renders.
- **Widget — `MapScreen`:** the search icon is present (keyed) and navigates; a returned result drops
  the destination marker and shows the info card.
- **Manual on-device:** search "Ghatshila"/"Galudih"/a known POI → nearest-first → tap → map centers
  + marker + card; confirm in airplane mode.
- **Gate:** `flutter analyze` clean + `flutter test` green, verified from real command output.

## 10. Success criteria

1. Tapping the search icon opens a full-screen search; typing shows live results from the offline DB.
2. Results are ordered nearest-first (GPS, or map center if no fix), with a distance label.
3. Selecting a result returns to the map, centers/zooms to it, drops a destination marker, and shows
   an info card; selecting another moves the marker.
4. All search works in airplane mode after first launch; a DB failure degrades gracefully (map still
   works, search shows a retry state).

## 11. References

- M1 spec: `docs/superpowers/specs/2026-05-31-offline-map-foundation-design.md`
- M2a spec: `docs/superpowers/specs/2026-06-01-map-polish-design.md`
- Research: `offline-map-app-research.html` (offline geocoding section)
