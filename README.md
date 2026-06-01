# Offline Navigator

An offline-first Flutter navigation app for **Android and iOS**. **Milestone 2b** adds **offline destination search** — a search icon opens a full-screen search page that queries a bundled SQLite database of named places, POIs, roads, and water features; results are ranked nearest-first; tapping a result centers the map, drops a destination marker, and shows an info card. All search happens on-device with no network access required.

**Milestone 2a** added three capabilities: a **4-style map switcher** (Standard, Light, Dark, Roads) behind a layers button and bottom-sheet picker; **auto dark mode** that follows the phone's system brightness (Standard in light mode, Dark in dark mode) with a live switch when you toggle the system setting; and a **fixed location-permission prompt** that now appears at launch on a fresh install, independent of map loading. All behavior is fully offline.

Milestone 1 delivered a fully offline MapLibre vector map of Ghatshila, Jharkhand — including a live GPS directional arrow pointer that rotates to your heading, 2.5D camera tilt, a follow-camera mode, and a permission banner. The bundled tile pack, glyph fonts, and styles are copied to on-device storage on first launch so the map works completely in airplane mode afterwards.

> A macOS desktop target is also scaffolded — purely so the offline integration test can be run without a mobile device once full Xcode is installed (see Verification status). macOS is not a shipping target.

---

## Prerequisites

| Requirement | Check |
|---|---|
| Flutter ≥ 3.35 / Dart ≥ 3.9 | `flutter --version` |
| Connected Android/iOS device or emulator | `flutter devices` |
| *(Dev-time only)* `pmtiles` CLI — to regenerate tiles | `go install github.com/protomaps/go-pmtiles@latest` |

---

## Regenerate offline data (optional — a pack is committed)

A pre-built `assets/tiles/ghatshila.pmtiles`, glyph fonts, and `assets/search/ghatshila.sqlite` are already committed and bundled into the app. You only need these scripts if you want to refresh the tile data, fonts, or search index:

```bash
tool/generate_tiles.sh         # extract Ghatshila .pmtiles from Protomaps daily build
tool/fetch_assets.sh           # fetch offline glyph PBF ranges (Noto Sans Regular)
tool/generate_search_index.sh  # build the offline search DB from raw OpenStreetMap (Overpass API)
```

`generate_tiles.sh` accepts an optional `BUILD_DATE` argument (YYYYMMDD) in case the default date is no longer available on `build.protomaps.com`:

```bash
tool/generate_tiles.sh 20260501
```

### Regenerating the search index

`tool/generate_search_index.sh` requires `curl`, `python3`, and `sqlite3` (all standard on macOS). It queries the **Overpass API** for raw OpenStreetMap named features within the Ghatshila bounding box — no large file downloads needed, and no internet access is required at runtime (the app ships the resulting DB). It then calls `tool/build_search_index.py` which normalizes names and writes `assets/search/ghatshila.sqlite`.

```bash
tool/generate_search_index.sh
```

The script prints per-kind feature counts when done. The current committed DB has **107 features** (79 places, 21 POIs, 7 water, 0 roads). The roads count is 0 because OSM genuinely has no named highways in this rural Ghatshila bbox — this is correct OSM data, not an extraction bug. The road extraction code is in place and will pick up roads if/when OSM contributors add named highways to the area.

---

## Run

```bash
flutter pub get
flutter run           # on a connected Android/iOS device or emulator
```

On first launch the app copies the bundled tile pack and glyphs into application support storage (this takes a few seconds). Subsequent launches — including in airplane mode — read directly from storage.

---

## Test

```bash
# Unit + widget tests (no device required)
flutter test

# Offline integration smoke test (requires a connected device/emulator)
flutter test integration_test/offline_smoke_test.dart -d <device-id>
```

The integration test proves the offline path end-to-end: it calls `TileService.ensureReady()`, verifies the style is served from `127.0.0.1`, and confirms the tile server responds — all without any external network access.

> **macOS note:** the integration test is also runnable on macOS desktop (no mobile device needed) — useful for verifying the offline path on a dev machine. This requires **full Xcode** (not just the Command Line Tools). The `com.apple.security.network.server`/`client` entitlements the local HTTP server needs are already committed in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.

---

## Manual offline acceptance checklist

These steps exercise the full on-device experience that cannot be covered by automated tests (live GPS + visual rendering). Run them on a real Android or iOS device:

1. `flutter run` — let the map load once (this seeds the on-device tile cache).
2. Enable **airplane mode** on the device.
3. Confirm the Ghatshila basemap still renders (roads, water, labels).
4. Pan, zoom, and rotate — confirm smooth interaction.
5. Press the **3D button** (bottom-right) — confirm the camera tilts to ~50°.
6. Walk or use mock GPS near 22.586° N, 86.476° E — confirm the orange arrow pointer appears, rotates to heading, and the camera follows.
7. Manually pan away from your location, then press the **recenter button** (bottom-right) — confirm the camera animates back to your position and resumes following. (v1 keeps follow on until you recenter; it does not auto-disable on a manual pan.)
8. Tap the **layers button** (bottom-right, top FAB) — confirm the style sheet opens with Standard / Light / Dark / Roads + Auto.
9. Pick each style — confirm the map restyles and the GPS arrow re-appears.
10. Pick **Auto**, then toggle the phone's system dark mode — confirm the map switches between the Standard (light) and Dark styles automatically.
11. Confirm the **location-permission prompt appears on a fresh install** at launch (uninstall + reinstall to retest), independent of the map loading.

**Offline search (Milestone 2b):**

12. Tap the **search icon** (top-left, below the status bar) — confirm the full-screen search page opens.
13. Type **"Ghatshila"** — confirm live results appear with distance labels (nearest first). Type **"Galudih"** — confirm a different set of results.
14. Tap a result — confirm the map centers and zooms to it, a destination marker drops on the map, and an info card appears at the bottom showing the name and kind.
15. Tap the **×** button on the info card — confirm the card and marker both disappear.
16. Open search again, pick a result, then switch map style via the layers button — confirm the destination marker **persists** after the style swap.
17. Enable **airplane mode**, then open search and type a query — confirm results still appear (search is fully offline, no network needed).

---

## Architecture

The app is a thin Flutter UI (`MapScreen`) over three focused modules:

- **`TileService`** — copies the bundled PMTiles pack and glyph fonts into application support storage on first launch, then starts an in-process `shelf` HTTP server on `127.0.0.1` that serves `/tiles/{z}/{x}/{y}.mvt`, `/fonts/{fontstack}/{range}.pbf`, and all four styles at `/style/<name>.json` to MapLibre.
- **`MapStyleResolver`** — pure-Dart logic that maps (OS brightness, optional manual pick) → active `MapStyleId` (Standard / Light / Dark / Roads). No network access.
- **`LocationService`** — wraps `geolocator` with permission handling and exponential-moving-average smoothing of position + heading (with wraparound-aware heading interpolation).
- **`MapScreen`** + **`UserPointer`** — the MapLibre map widget wired to the tile server URL, a GeoJSON symbol layer for the rotatable pointer icon, follow-camera logic, tilt toggle, permission banner, and the layers FAB + style-picker bottom sheet.

Full design rationale and architecture decisions:
- Spec: `docs/superpowers/specs/2026-05-31-offline-map-foundation-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-31-offline-map-foundation.md`
- Research: `offline-map-app-research.html`

---

## Verification status (Milestone 2b)

| What | Status |
|---|---|
| `flutter analyze` — whole project | **PASS** — "No issues found!" |
| `flutter test` — 46 unit + widget tests | **PASS** — all 46 passed |
| Offline smoke test (`integration_test/offline_smoke_test.dart`) | **WRITTEN, NOT YET RUN** — code complete and `flutter analyze`-clean, but never executed: the dev environment has no mobile device/emulator, and the macOS target needs full Xcode (only the Command Line Tools are installed here). Run it with `-d <device>` to confirm the offline path. |
| On-device **mobile** visual rendering (Android / iOS) | **NOT YET VERIFIED** — no mobile device was available in the dev environment |
| Live GPS arrow pointer + follow camera on mobile | **NOT YET VERIFIED** — requires the manual acceptance steps above on a real/emulated device |
| 4-style switcher visual appearance on mobile | **NOT YET VERIFIED** — style colors and layer rendering are on-device-manual; verified structurally by widget tests (sheet opens, all styles present, Auto tile present) |
| Auto dark mode live switch on mobile | **NOT YET VERIFIED** — `didChangePlatformBrightness` / `MapController.setStyle` re-triggering is on-device-manual; logic is covered by unit tests (`MapStyleResolver`) |
| Location-permission prompt at fresh install | **NOT YET VERIFIED** — platform channel behavior requires uninstall + reinstall on a real device; structural fix (boot-time `ensurePermission`) is in the widget test suite |
| Offline search — query/rank logic | **PASS** — unit-tested via `sqflite_common_ffi` (in-memory DB seeded in tests; prefix LIKE, nearest-first ranking, Devanagari script, limit, empty-query short-circuit all covered) |
| Offline search — on-device DB copy + UI | **NOT YET VERIFIED** — the DB-copy-on-first-launch path and the full search UX (search-as-you-type, destination marker, info card, style-swap persistence, airplane-mode operation) require the manual checklist steps 12–17 above on a real device |

The core offline infrastructure (PMTiles reader, local HTTP tile/glyph/style server, asset-copy + version stamp, EMA location smoothing, GeoJSON pointer encoding, `MapStyleResolver`, multi-style server routes) is covered by automated unit/widget tests. All on-device visual behavior — map rendering, GPS arrow, style appearance, live dark-mode switching, and the permission prompt — requires the manual checklist above on a real Android or iOS device.
