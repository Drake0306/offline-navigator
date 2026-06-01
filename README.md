# Offline Navigator

An offline-first Flutter navigation app for **Android and iOS**. **Milestone 3 (part 1)** adds a **trip planner** — tap the directions button (right-side FABs) to open the trip planner panel. Set a start point (defaults to your location), set a destination via search or by long-pressing the map, and optionally add stops the same way. Choose from four travel modes: car, motorbike, bike, or walk. The planner draws a route line on the map and shows distance, ETA, and a step-by-step maneuver list.

> **Important — routing is not yet real road routing.** The route line is currently drawn by a `FakeRoutingService` that connects your points with straight lines (great-circle segments). It does **not** follow roads, paths, or any on-device map data. Real offline road routing powered by on-device Valhalla (native FFI + tile pipeline) is a **separate upcoming plan** that has not yet been built. Everything else — the trip planner UI, travel mode selector, maneuver list display, live-progress logic, and the `RoutingService` interface — is complete and fully tested.

**Milestone 2b** adds **offline destination search** — a search icon opens a full-screen search page that queries a bundled SQLite database of named places, POIs, roads, and water features; results are ranked nearest-first; tapping a result centers the map, drops a destination marker, and shows an info card. All search happens on-device with no network access required.

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

**Trip planner (Milestone 3 — routing):**

> Note: on **Android** the route is computed by the **real on-device Valhalla engine** over bundled
> Ghatshila routing tiles — the line should **follow roads** with a real maneuver list. On iOS (native
> bridge not yet built) or if the Android native engine is unavailable, the app falls back to a
> **straight-line placeholder** so the planner is never dead. Routing works only **within the bundled
> Ghatshila tiles** — a destination outside that area fails gracefully (the region download manager,
> a later milestone, removes that boundary).

18. Tap the **directions button** (right-side FABs, below the layers button) — confirm the trip planner panel opens.
19. Confirm the **Start** field defaults to your current location.
20. Set a **destination** by tapping the destination field and using search, or by long-pressing the map — confirm the destination is set and its label appears in the panel.
21. Tap **Get Directions** (or equivalent compute button) — confirm a route line draws on the map connecting your points with a distance and ETA shown in the panel.
22. Confirm a **maneuver list** appears below the summary (a step-by-step list of instructions).
23. Long-press the map at a different location to **add a stop** — confirm the stop appears in the panel's point list and the route updates.
24. **Remove the stop** (swipe or tap the remove button next to it) — confirm the stop is removed and the route updates.
25. Switch between the four **travel modes** (car, motorbike, bike, walk) — confirm each mode is selectable and the route ETA updates accordingly.
26. **Clear the trip** (close the panel or tap a clear button) — confirm the route line disappears and the panel resets.

**Native routing acceptance (Milestone 3 part 2 — Android only):**

27. On an **Android** device, plan a trip **inside Ghatshila** and confirm the drawn route **follows roads** (curves along the road network) with a real maneuver list — not a straight diagonal line. This proves the native Valhalla engine ran on-device.
28. Plan a trip whose destination is **far outside Ghatshila** (e.g. a point hundreds of km away) — confirm it **fails gracefully** ("no route" / "outside the downloaded map area"), not a crash. This is the expected boundary until the region download manager lands.
29. If the route comes back as a **straight line** on Android, the native engine fell back — check the `flutter run` logs for a `ValhallaPlugin`/MethodChannel error (the most likely cause is the asset path prefix: the plugin opens `assets/routing/...`; if not found it may need the `flutter_assets/` prefix).

---

## Native offline routing (Android — Milestone 3 part 2)

Real on-device routing uses the Valhalla engine (`io.github.rallista:valhalla-mobile`) over **bundled
Ghatshila routing tiles**, reached through a `MethodChannel` (`offline_navigator/valhalla`) — not FFI.
The Dart side (`ValhallaRoutingService`) builds the Valhalla request, calls the channel, and parses the
response with the same `parseValhallaRoute` used everywhere; `fallbackToFake: true` keeps the planner
working (straight-line) if the native engine is unavailable.

**Scope (honest):** this proves the engine runs on the phone. It routes **only where tiles exist
on-device** (currently Ghatshila). "Route any region you pick" requires the **region download manager**
(a later milestone): the phone can only *consume* pre-built tiles — it cannot generate them (tile
generation is a heavy computer/server job). The engine reads tiles from app storage, so the download
manager can later drop new regions there and routing works over them with no code change.

### Regenerate routing tiles (optional — committed already)
Requires Docker + osmium:
```bash
tool/generate_valhalla_tiles.sh   # builds + verifies assets/routing/valhalla_tiles.tar in Docker
```

### Build + run on an Android device
```bash
flutter pub get
flutter run   # on a connected Android device
```
First launch copies the bundled tiles into app storage and constructs the native router. Then follow
manual steps 27–29 above.

---

## Architecture

The app is a Flutter UI (`MapScreen` + `TripPlannerPanel`) over focused modules:

- **`TileService`** — copies the bundled PMTiles pack and glyph fonts into application support storage on first launch, then starts an in-process `shelf` HTTP server on `127.0.0.1` that serves `/tiles/{z}/{x}/{y}.mvt`, `/fonts/{fontstack}/{range}.pbf`, and all four styles at `/style/<name>.json` to MapLibre.
- **`MapStyleResolver`** — pure-Dart logic that maps (OS brightness, optional manual pick) → active `MapStyleId` (Standard / Light / Dark / Roads). No network access.
- **`LocationService`** — wraps `geolocator` with permission handling and exponential-moving-average smoothing of position + heading (with wraparound-aware heading interpolation).
- **`MapScreen`** + **`UserPointer`** — the MapLibre map widget wired to the tile server URL, a GeoJSON symbol layer for the rotatable pointer icon, follow-camera logic, tilt toggle, permission banner, layers FAB + style-picker bottom sheet, and the directions FAB that opens the trip planner.
- **Routing domain** (`lib/routing/`) — pure-Dart: `RoutePlan`/`RouteLeg`/`Maneuver` value types, polyline6 decoder, Valhalla-JSON parser, distance/duration formatters, `TripState` immutable reducer, live-progress (snap-to-route, current maneuver, off-route detection), and the `RoutingService` abstract interface. Two implementations: `FakeRoutingService` (straight-line, used in tests + as a fallback) and **`ValhallaRoutingService`** — the real engine on **Android**, which builds a Valhalla request, calls the native engine over the `offline_navigator/valhalla` MethodChannel, and parses the response into a `RoutePlan`. The Android native side is `ValhallaPlugin.kt` + the `valhalla-mobile` AAR; tiles are generated by `tool/generate_valhalla_tiles.sh` (Docker) and bundled. iOS native is a later part.
- **`TripPlannerPanel`** (`lib/trip/`) — the trip planner UI: start/stops/destination editor, four travel-mode chips, compute button, route-summary (distance + ETA), and scrollable maneuver list. Communicates with `MapScreen` to draw the route `LineStyleLayer` and endpoint markers.

Full design rationale and architecture decisions:
- Spec: `docs/superpowers/specs/2026-05-31-offline-map-foundation-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-31-offline-map-foundation.md`
- Trip planner plan: `docs/superpowers/plans/2026-06-01-trip-planner-ui.md`
- Research: `offline-map-app-research.html`

---

## Verification status (Milestone 3 part 2)

| What | Status |
|---|---|
| `flutter analyze` — whole project | **PASS** — "No issues found!" |
| `flutter test` — 75 unit + widget tests | **PASS** — all 75 passed |
| Trip planner UI + domain | **PASS** — routing domain (RoutePlan, polyline decoder, Valhalla-JSON parser, formatters, trip-state reducer, live-progress), `RoutingService` interface, and the trip planner panel are all unit- and widget-tested and green. |
| Valhalla routing tiles (Ghatshila) | **PASS (verified in Docker)** — `tool/generate_valhalla_tiles.sh` builds the tiles and a test route (Ghatshila 22.586,86.476 → 22.593,86.515) returns status 0, 5.69 km, 7 maneuvers, a road-following polyline. Bundled as `assets/routing/valhalla_tiles.tar` + `admins.sqlite` + `valhalla.json`. |
| `ValhallaRoutingService` (request / parse / error / fallback) | **PASS** — unit-tested with a mocked MethodChannel: per-mode request JSON, success→RoutePlan, `{code,message}`→RoutingException, and the straight-line fallback when the native side throws. |
| On-device Android route (native engine) | **NOT YET VERIFIED** — the Kotlin `ValhallaPlugin` + `valhalla-mobile` AAR cannot be compiled in this dev env (no Java/Android SDK build). The user builds + runs on an Android device (manual steps 27–29) to confirm a real road-following route. Fallback keeps the app usable if it doesn't link. |
| iOS native routing | **NOT IMPLEMENTED** — Android-first; iOS native bridge is a later part. iOS currently uses the straight-line fallback. |
| Offline smoke test (`integration_test/offline_smoke_test.dart`) | **WRITTEN, NOT YET RUN** — code complete and `flutter analyze`-clean, but never executed: the dev environment has no mobile device/emulator, and the macOS target needs full Xcode (only the Command Line Tools are installed here). Run it with `-d <device>` to confirm the offline path. |
| On-device **mobile** visual rendering (Android / iOS) | **NOT YET VERIFIED** — no mobile device was available in the dev environment |
| Live GPS arrow pointer + follow camera on mobile | **NOT YET VERIFIED** — requires the manual acceptance steps above on a real/emulated device |
| 4-style switcher visual appearance on mobile | **NOT YET VERIFIED** — style colors and layer rendering are on-device-manual; verified structurally by widget tests (sheet opens, all styles present, Auto tile present) |
| Auto dark mode live switch on mobile | **NOT YET VERIFIED** — `didChangePlatformBrightness` / `MapController.setStyle` re-triggering is on-device-manual; logic is covered by unit tests (`MapStyleResolver`) |
| Location-permission prompt at fresh install | **NOT YET VERIFIED** — platform channel behavior requires uninstall + reinstall on a real device; structural fix (boot-time `ensurePermission`) is in the widget test suite |
| Offline search — query/rank logic | **PASS** — unit-tested via `sqflite_common_ffi` (in-memory DB seeded in tests; prefix LIKE, nearest-first ranking, Devanagari script, limit, empty-query short-circuit all covered) |
| Offline search — on-device DB copy + UI | **NOT YET VERIFIED** — the DB-copy-on-first-launch path and the full search UX (search-as-you-type, destination marker, info card, style-swap persistence, airplane-mode operation) require the manual checklist steps 12–17 above on a real device |
| Trip planner UI — on-device visual + interaction | **NOT YET VERIFIED** — the on-device trip planner UX (directions button, panel open/close, long-press to add point, mode switching, route line drawing, maneuver list scroll) requires the manual checklist steps 18–26 above on a real device |

The core offline infrastructure (PMTiles reader, local HTTP tile/glyph/style server, asset-copy + version stamp, EMA location smoothing, GeoJSON pointer encoding, `MapStyleResolver`, multi-style server routes) is covered by automated unit/widget tests. All on-device visual behavior — map rendering, GPS arrow, style appearance, live dark-mode switching, and the permission prompt — requires the manual checklist above on a real Android or iOS device.
