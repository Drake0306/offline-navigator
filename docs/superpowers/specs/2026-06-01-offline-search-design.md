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

**Matching engine note:** the index uses a normalized text column + `LIKE 'term%'`, NOT SQLite
FTS5. `sqflite` uses the OS's SQLite, and FTS5 is an optional compile-time module that is not
reliably present on older Android — an FTS5 query would throw at runtime there and kill search.
A normalized (lowercased, diacritics-stripped, romanized) `search` column with a plain index works
on every device, keeps the `sqflite` dependency, and is fast for a single region's feature count.

## 2. Goal

A search icon on the map opens a full-screen search page. Typing shows live (search-as-you-type)
results drawn from a prebuilt, on-device SQLite index of named features, ranked by distance
from the user (text relevance as tiebreak). Selecting a result returns to the map, centers + zooms
to it, drops a destination marker, and shows an info card (name, kind, distance). Works fully
offline after first launch.

## 3. Decisions (locked)

| Area | Decision |
|---|---|
| Searchable features | **Places, POIs, roads, and water** (all four) |
| Index source | **Dedicated index from raw OSM** — build-time extract → bundled SQLite DB (normalized `search` column) |
| Storage / engine | SQLite via the `sqflite` package, DB copied to storage on first launch (version-stamped). **Matching uses a normalized (lowercased + diacritics-stripped + romanized) `search` column with an index, queried via `LIKE 'term%'` — NOT FTS5.** FTS5 is an optional SQLite compile-time module not guaranteed on older Android; `LIKE` on a normalized indexed column works on every device and is fast for one region's data. |
| Result action | **Center map + drop a destination marker** + dismissible info card (name, kind, distance) |
| Search UI | **Search icon → full-screen search page** (bar + live results); returns to map on select |
| Ranking | **Distance from user, then text match**; falls back to map-center distance if no GPS fix |
| Routing | OUT OF SCOPE — Milestone 3 |

## 4. Scope

**In scope**
- Build-time pipeline: clip raw OSM to the Ghatshila bbox (`86.35,22.45,86.65,22.75`), extract named
  places/POIs/roads/water, write `assets/search/ghatshila.sqlite` (a `features` row table with a
  normalized, indexed `search` column).
- `SearchService`: copy the bundled DB to storage (version-stamped), open via `sqflite`, run
  normalized `LIKE 'term%'` prefix queries, rank distance-then-text, return `SearchResult`s.
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
  • features(id, name, name_en, kind, lat, lon, search)  -- `search` = normalized, indexed
  • INDEX idx_features_search ON features(search)
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

**New dependency:** `sqflite` (standard Flutter SQLite, Android + iOS) + `sqflite_common_ffi`
(dev-only, lets the ranking unit tests open a temp SQLite on the test VM / macOS).
**New build dependency:** an OSM extractor (`osmium`/`pyosmium`) to filter the pbf — not yet installed
(plan Task 0 installs it, as we did for the `pmtiles` CLI).

## 6. Data flow

**Build-time (scripted, once):**
1. Obtain a raw OSM extract covering the bbox (e.g. a Geofabrik Jharkhand `.osm.pbf`, clipped with
   `osmium extract --bbox`).
2. Filter to named features in places/POIs/roads/water; for each, capture display `name`, romanized
   `name_en` (from `name:en` or transliteration when available), a normalized `kind`, and a
   representative `lat/lon` (point for nodes; centroid for ways/areas). Compute a `search` string =
   `normalize(name) || ' ' || normalize(name_en)` where `normalize` lowercases, strips diacritics,
   and collapses whitespace (so typing English or local script both match).
3. Write `search.sqlite`: insert rows into `features` and create `idx_features_search` on `search`.
   Bundle under `assets/search/`. (Document the exact commands in `tool/generate_search_index`.)

**Runtime:**
1. On first launch (or version bump), `SearchService.ensureReady()` copies the DB to app storage and
   opens it. (Version-stamped like the tile assets.)
2. Each keystroke (debounced ~200ms): `query(text, origin, limit:30)` normalizes the term the same
   way and runs `SELECT ... FROM features WHERE search LIKE ? ` with a `'<norm-term>%'` (prefix) and
   a secondary `'% <norm-term>%'` (word-start) pattern so mid-name word matches also hit.
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
  lon     REAL NOT NULL,
  search  TEXT NOT NULL    -- normalize(name)+' '+normalize(name_en): lowercased,
                           -- diacritics-stripped, whitespace-collapsed
);
CREATE INDEX idx_features_search ON features(search);
```
The `search` column folds both name forms into one normalized, indexed string, so typing English or
local script matches the same row via `LIKE`. No FTS5 — works on every SQLite/Android version.
The same `normalize()` is applied to the user's query term before building the `LIKE` pattern.

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
- **Unit — `normalize()`:** lowercases, strips diacritics, collapses whitespace; deterministic for the
  same input used at build-time and query-time (so patterns match).
- **Unit — `SearchService` ranking:** seed a temp SQLite (via `sqflite_common_ffi` on the test VM)
  with a few rows; assert distance-then-text ordering, `LIKE` prefix + word-start matching, `name`
  vs `name_en` dual-match via the `search` column (type Latin → matches a Devanagari-named row),
  `limit` cap, empty-query → empty, and the no-origin (map-center) fallback.
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
