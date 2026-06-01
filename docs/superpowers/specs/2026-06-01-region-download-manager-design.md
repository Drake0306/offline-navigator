# Milestone 5 — Offline Region Download Manager (Design Spec)

- **Date:** 2026-06-01
- **Status:** Approved (design); proceeding to plan + build (user opted to skip the spec-review gate)
- **Project:** Offline-first Android + iOS navigation app ("Offline Navigator")
- **This milestone:** let the user download per-district regions (map + routing + search) on
  demand to device storage, switch the active region, and have the whole app render/route/search
  over it — fully offline after the download. Resolves the practical routing failure (the only
  on-device routable area today is a ~50 km Ghatshila box, so routes from anywhere else fail).

---

## 1. Context

Today the app ships a single tiny **bundled** region (Ghatshila): one `.pmtiles` (map), one Valhalla
`.tar` + `admins.sqlite` + `valhalla.json` (routing, ~14 tiles, ~50 km box), and one `.sqlite`
(search, 107 features). Three consumers read those **hardcoded bundled assets**:

- `TileService` — copies `assets/tiles/ghatshila.pmtiles` to storage, opens `PmTilesReader`, serves
  via `LocalTileServer`.
- `ValhallaPlugin.kt` / `ValhallaRoutingService` — copies `assets/routing/*` to `filesDir/routing`,
  constructs a `ValhallaActor` over that config.
- `SearchService` — copies `assets/search/ghatshila.sqlite` to storage, opens it read-only.

Two problems this milestone fixes: (a) you can only route/search/see-labels where the bundled tiles
exist — so standing anywhere but Ghatshila, routing fails ("no road near here"); (b) there's no way to
add coverage. The engine itself is healthy (verified on-device: `valhalla-mobile` 0.3.0 loads the tar
and reads tiles) — the limit is purely **coverage**.

## 2. Goal

A **Settings → Download Regions** screen lists Jharkhand districts from an online catalog. The user
downloads a district once (the one online moment), and from then on the map renders it, routing works
within it, and search finds its places — all offline. The user can switch the **active region**,
delete regions, and see sizes/progress. Ghatshila stays as a **built-in default region** so the app
works out of the box and existing tests stay green.

## 3. Decisions (locked)

| Area | Decision |
|---|---|
| Granularity | **Per-district** packages (~tens of MB each). Like Google's offline areas. |
| Hosting | **GitHub Releases** on `Drake0306/offline-navigator` (publishable from this machine via `gh`, authed as Drake0306). Public asset URLs. |
| Catalog | A `regions.json` manifest (release asset) listing every district: id, name, bbox, version, per-file URL + size + sha256. |
| Region package | Per district: `<id>.pmtiles`, `<id>.valhalla.tar`, `<id>.admins.sqlite`, `<id>.search.sqlite`, plus a per-region manifest. `valhalla.json` is **generated on-device** from a template (so paths are correct) rather than shipped. |
| On-device layout | `applicationSupport/regions/<id>/{tiles.pmtiles, valhalla.tar, admins.sqlite, valhalla.json, search.sqlite, manifest.json}`. |
| Active region | A persisted `activeRegionId`; consumers read that region's files. Default = the built-in `ghatshila` region (seeded from bundled assets on first launch). |
| Built-in default | Ghatshila remains bundled and is installed as a pre-existing region on first run (no download needed); the app is never dead offline. |
| Online touchpoint | Only the catalog fetch + file downloads need internet. Everything else stays offline. |
| Data generation | Per-district packages built **here via Docker** from a **Geofabrik Jharkhand `.osm.pbf`** extract (Overpass times out at state scale). First district: **East Singhbhum** (contains Ghatshila). |
| Out of scope | On-demand/draw-a-box server generation; non-Jharkhand states (the pipeline is region-agnostic, so more can be added later); iOS native routing (still Android-first). |

## 4. Architecture

```
Settings screen (new)
  └── RegionManagerScreen (new) — district list from RegionCatalog; per-row download/cancel/delete/activate
        │ uses
        ▼
RegionController (new, ChangeNotifier) — installed regions, activeRegionId, in-flight downloads
  ├── RegionCatalog (new)    — fetch + parse regions.json (online)
  ├── RegionStore (new)      — on-device install/list/delete/version; resolves a region's file paths
  ├── RegionDownloader (new) — streamed download w/ progress + sha256 verify; cancelable
  └── Region / RegionFiles / RegionManifest (new) — value types (id, name, bbox, version, files)
        │ the active region drives
        ▼
Region-aware consumers (MODIFIED):
  ├── TileService(activeRegion)   — PmTilesReader over the active region's tiles.pmtiles
  ├── ValhallaRoutingService + ValhallaPlugin.kt — route over the active region's valhalla.tar/admins/config
  └── SearchService(activeRegion) — open the active region's search.sqlite
MapScreen (MODIFIED) — recenters to the active region bbox; rebuilds consumers on region switch;
  a Settings entry point (top-left, near search).
```

**Responsibilities & boundaries**
- **Region domain** (`lib/regions/`) — pure-Dart value types + store + catalog parsing + downloader.
  Unit-tested with a fake HTTP client and a temp dir.
- **RegionController** — orchestration/state machine. Tested.
- **Region-aware consumers** — each gains a "use this region directory" path; the bundled-asset path
  becomes the seeding of the default region. Tested where logic allows (paths/selection); rendering is
  device-manual.
- **RegionManagerScreen / Settings** — widget-tested with a fake controller.
- **Data/ops** — `tool/generate_region.sh <bbox> <id>` (generalize the existing scripts to any bbox +
  Geofabrik source), `tool/build_region_catalog.py`, and `gh release` upload. Verified by a Docker
  test route inside the district.

## 5. Data flow

**Browse + download:** open Settings → Download Regions → `RegionCatalog.fetch()` lists districts →
tap a district → `RegionDownloader` streams its files into `regions/<id>/` with a progress bar →
sha256-verify each → write `manifest.json` → it appears as installed.

**Activate:** tap an installed region → `RegionController.setActive(id)` persists `activeRegionId` →
consumers are rebuilt against `regions/<id>/` (tile server restarts on the new pmtiles, Valhalla
re-inits on the new tar, search reopens the new sqlite) → map animates to the region bbox.

**Route/search/render:** unchanged from the user's perspective, but now scoped to the active region's
files. Routing inside a downloaded district works; outside any installed region it fails gracefully
("download this area to navigate here").

**Delete:** remove `regions/<id>/`; if it was active, fall back to the built-in `ghatshila`.

## 6. Region package + catalog format

`regions.json` (catalog):
```json
{
  "schemaVersion": 1,
  "regions": [
    {
      "id": "in-jh-east-singhbhum",
      "name": "East Singhbhum (Jamshedpur)",
      "state": "Jharkhand",
      "bbox": [86.0, 22.2, 86.9, 23.1],
      "version": 1,
      "files": {
        "tiles":  {"url": "https://github.com/.../east-singhbhum.pmtiles",      "bytes": 0, "sha256": "..."},
        "valhalla":{"url":"https://github.com/.../east-singhbhum.valhalla.tar",  "bytes": 0, "sha256": "..."},
        "admins": {"url": "https://github.com/.../east-singhbhum.admins.sqlite", "bytes": 0, "sha256": "..."},
        "search": {"url": "https://github.com/.../east-singhbhum.search.sqlite", "bytes": 0, "sha256": "..."}
      }
    }
  ]
}
```
Per-region on-device `manifest.json` = the catalog entry + an `installedAt` stamp. `valhalla.json` is
written on-device from a bundled template with `__APPDIR__` → `regions/<id>` (same mechanism the plugin
already uses).

## 7. Error handling & edge cases

- **No internet on the catalog/download** → clear "couldn't reach the region catalog — connect to the
  internet to download regions" with retry; installed regions still work offline.
- **Interrupted download** → partial files go to a `.part` staging dir; only promoted to `regions/<id>/`
  after every file verifies. A failed/canceled download leaves no half-region.
- **Checksum mismatch / corrupt file** → discard, surface "download was corrupted, try again".
- **Disk full on device** → catch, show "not enough space for <region> (<size>)", clean up `.part`.
- **Route/search with no region for the area** → graceful message, not a crash (existing 171 → "outside
  the downloaded map area" mapping is reused).
- **Switching region mid-use** → consumers are torn down/rebuilt; the map guards (existing
  `_routeReady`/`_pointerSourceReady` style guards) prevent touching a destroyed source.
- **Version bump of an installed region** → catalog `version` > installed → offer "update available".
- **Offline guarantee** → after download, no network; the local tile server, native router, and SQLite
  all read device files.

## 8. Testing

- **Unit (pure Dart):** catalog JSON parse (valid/malformed/missing fields); `RegionStore` install/list/
  delete/active-persistence over a temp dir; `RegionDownloader` progress + sha256 verify + cancel +
  `.part` promotion, with a fake HTTP client; `RegionController` transitions.
- **Widget:** `RegionManagerScreen` with a fake controller — list renders, download shows progress,
  installed shows active/delete, activate switches; a Settings entry point exists on the map.
- **Consumer wiring:** `TileService`/`SearchService` open a region directory passed in (tested via temp
  dirs + a seeded region); `ValhallaRoutingService` targets the active region (request/parse already
  tested; path selection unit-tested).
- **Existing suite stays green** — Ghatshila-as-default keeps current behavior; bundled-asset seeding is
  the default region's install path.
- **Data/ops (Docker, here):** `tool/generate_region.sh` builds East Singhbhum; a Docker test route
  *inside* the district returns status 0 with a road-following polyline; catalog validates; assets
  upload to a GitHub Release.
- **Device (user):** Settings → download your district → it becomes active → the map shows it, **routing
  works there**, search finds its places; airplane-mode afterwards still works; delete falls back to
  Ghatshila.

## 9. Success criteria

1. A **Settings → Download Regions** screen lists Jharkhand districts from an online catalog with sizes.
2. Downloading a district stores it on-device with progress + integrity checks; it survives app restart.
3. Activating a region makes the **map render it, routing work within it, and search find its places** —
   fully offline after download.
4. Ghatshila still works out of the box; deleting the active region falls back to it.
5. East Singhbhum is generated, published to GitHub Releases, and downloadable end-to-end.
6. All non-device logic + UI is `flutter test`-green; the download + on-device experience is user-verified.

## 10. Build order (each part shippable)

1. **Region core** (`lib/regions/`): models, catalog, store, downloader, `RegionController`. Pure Dart.
2. **Region-aware consumers**: `TileService`, `SearchService`, `ValhallaRoutingService`/`ValhallaPlugin`
   read the active region; Ghatshila seeded as default; map recenters on switch.
3. **Settings + Download UI**: Settings screen + `RegionManagerScreen` wired to `RegionController`.
4. **Data + hosting**: `tool/generate_region.sh` (Geofabrik + Docker, region-agnostic), build
   `regions.json`, generate East Singhbhum, publish to GitHub Releases.

## 11. References

- M4 drive-mode spec: `2026-06-01-turn-by-turn-navigation-design.md`
- Native routing + version pin: `2026-06-01-native-valhalla-routing-design.md`; engine pinned to
  `valhalla-mobile` 0.3.0 (newest with public `ValhallaActor`).
- Existing pipeline scripts: `tool/generate_valhalla_tiles.sh`, `tool/generate_tiles.sh`,
  `tool/generate_search_index.sh`.
- Geofabrik Jharkhand extract: `download.geofabrik.de/asia/india/jharkhand-latest.osm.pbf`.
