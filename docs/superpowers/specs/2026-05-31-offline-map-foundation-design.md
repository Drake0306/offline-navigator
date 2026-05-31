# Milestone 1 — Offline Map Foundation (Design Spec)

- **Date:** 2026-05-31
- **Status:** Approved (design); pending spec review → implementation plan
- **Project:** Offline-first Android + iOS navigation app
- **This milestone:** the first buildable slice — a fully offline map with a live GPS pointer

---

## 1. Context

We are building a highly accurate, **offline-first** navigation app for **both Android and iOS**.
After an initial download the app must work with no internet, using only GPS. The full product
(downloadable regions, offline search, multi-mode routing, full turn-by-turn) is decomposed into
milestones along the roadmap in `offline-map-app-research.html`. The chosen overall stack is:

> **MapLibre Native** (rendering) · **OpenStreetMap → PMTiles** (data) · **Valhalla** (routing, later)
> · **SQLite FTS5** (search, later) · **Fused Location / CoreLocation** (location), with a
> **Flutter** cross-platform UI over native modules. Mapbox Navigation SDK is the routing fallback.

This document specifies **only Milestone 1: the Offline Map Foundation**. Everything else is
explicitly deferred to later milestones, each of which will get its own spec → plan → implementation.

## 2. Goal

A Flutter app that renders a **fully offline** MapLibre vector map of **Ghatshila, Jharkhand, India**,
shows the user's live GPS position as a **rotatable directional arrow** (not a dot) that follows them,
and supports a **2.5D tilt**. It must keep working in airplane mode after first launch. This is the
foundation every later milestone builds on, and it de-risks the MapLibre + Flutter + offline-tiles core.

## 3. Decisions (locked for this milestone)

| Area | Decision | Notes |
|---|---|---|
| Platforms | Android **and** iOS | One Flutter codebase; native rendering via the plugin |
| Run target | User sets up their own device/emulator | We build for both; provide setup + run instructions. (Local box: Flutter ✅, no full Xcode, no Java/ANDROID_HOME yet.) |
| Map plugin | Official **`maplibre`** Flutter plugin | MapLibre-blessed; native rendering on both platforms |
| Tile format | **PMTiles** (single file) | Served on-device by an in-app local server; try `pmtiles://` direct first, fall back to the server |
| Test region | **Ghatshila, Jharkhand** (town + Galudih area) | bbox ≈ `86.35,22.45,86.65,22.75` (Ghatshila ≈ 22.59°N, 86.48°E); tunable |
| Tile source (M1) | Extract bbox from **Protomaps public build** via `pmtiles extract` | Fast path; self-hosted Geofabrik→Planetiler pipeline deferred to the download-manager milestone |
| Style | Open-source **`protomaps-themes-base`** MapLibre style | Glyphs + sprites bundled for offline |
| Bundle ID | `com.talentbridge.offlinenavigator` (default) | Changeable |

## 4. Scope

**In scope**
- New Flutter app targeting Android + iOS.
- One bundled **Ghatshila PMTiles** vector pack + local `style.json` + glyphs + sprites, copied into
  app storage on first launch (version-stamped).
- **In-app local tile server** (Dart `shelf`) that range-reads the PMTiles and serves
  `/{z}/{x}/{y}` tiles + style/glyphs/sprites to MapLibre.
- Full-screen map: **pan / zoom / rotate**, plus **2.5D tilt (pitch)** via gesture and a button.
- Live **GPS → custom directional arrow pointer** that rotates to heading and follows the user, with
  a **recenter/follow** button. Pointer is built **swappable** (car/bike icons later) but only the
  arrow is exposed now.
- **Location-permission handling** (request, granted, denied, permanently-denied → open settings).
- Verified to work in **airplane mode** after first launch.

**Out of scope (later milestones)**
- Region **download manager** / multiple regions (one region is bundled now).
- **Search / geocoding** (Milestone 2).
- **Routing, trip planning, turn-by-turn / Valhalla** (Milestone 3+).
- **Speedometer overlay & vehicle-icon swapping** (Milestone 4 — pointer is swappable by design, UI not exposed).
- Voice guidance, 3D.

## 5. Architecture

Thin UI over focused modules, each with one responsibility and a clean interface so they can be
tested and swapped independently.

```
MapScreen (UI): full-screen map · recenter/follow btn · tilt btn · permission prompts
        │ consumes                              │ consumes
   TileService                             LocationService
   • copy assets → app storage             • GPS position / speed / accuracy
   • start local tile server               • heading (GPS course; compass fallback)
   • return local style URL                • permissions
        │ serves tiles/glyphs/sprites           • smoothing
        │ over 127.0.0.1                     Stream<UserLocation>
   MapLibre (maplibre Flutter plugin): native vector rendering · pitch/tilt · rotatable arrow symbol
```

**Module interfaces**
- `TileService`: `Future<MapStyle> ensureReady()` (idempotent: copies assets if version changed,
  starts the local server, returns the local style URL), `Future<void> dispose()`.
- `LocationService`: `Stream<UserLocation> positions`, `Future<PermStatus> ensurePermission()`.
  `UserLocation { lat, lng, headingDeg, speedMps, accuracyM, timestamp }`.
- `MapScreen`: consumes both; manages the pointer symbol, follow-camera, tilt + recenter controls.

**Deliberately included** (commonly forgotten in offline maps):
- **Offline glyphs + sprites** served locally — without them labels/icons break offline.
- **Pointer built swappable** from day one so Milestone 4 vehicle icons + speedometer slot in without rework.

## 6. Data flow

**Runtime (every launch)**
1. `TileService.ensureReady()` checks a version stamp in app storage; first launch / version bump →
   copy `ghatshila.pmtiles` + style + glyphs + sprites from assets to app storage.
2. Start `shelf` server on `127.0.0.1:<free-port>`; rewrite style tile/glyph/sprite URLs to it;
   return the local style URL.
3. `MapScreen` loads MapLibre with that style → Ghatshila renders offline.
4. `LocationService.ensurePermission()` → on grant, start position + heading streams.
5. Each update → move/rotate the arrow pointer; if **follow mode** on, glide the camera to the user
   (preserving zoom + tilt).
6. **Tilt** button toggles pitch (0 ↔ ~50°); **recenter** re-enables follow.
7. Airplane mode → all reads are local files / localhost → works fully offline.

**Tile generation (dev-time, scripted — `tool/generate_tiles.sh`, not part of the app)**
- **M1 (fast path):** `pmtiles extract <protomaps-build-url> ghatshila.pmtiles --bbox=86.35,22.45,86.65,22.75`,
  styled with `protomaps-themes-base`; bundle its glyphs + sprites.
- **Later (download-manager milestone):** self-hosted **Geofabrik India → osmium clip → Planetiler**.

## 7. Project structure

```
lib/
  main.dart · app.dart                  entry + theme
  map/      map_screen.dart · user_pointer.dart · camera helpers
  tiles/    tile_service.dart · local_tile_server.dart · pmtiles_reader.dart
  location/ location_service.dart · user_location.dart
  common/   app_paths.dart              storage paths + version stamp
assets/     tiles/ghatshila.pmtiles · style/ · glyphs/ · sprites/ · icons/pointer_arrow
tool/       generate_tiles.sh           pmtiles-extract script (documented)
test/                                   unit + widget tests
integration_test/                       offline smoke test
docs/superpowers/specs/                 this spec
```

**Packages:** `maplibre` (rendering), `geolocator` (position/speed; GPS course primary heading,
compass fallback when stationary), `shelf` (local server), `path_provider` (storage), a PMTiles reader
(the `pmtiles` Dart package or a small range-reader).

## 8. Error handling & edge cases

- Location **permission denied / permanently denied** → non-blocking banner with "enable location" +
  open-settings; map still pans/zooms (no pointer/follow).
- Device **location services off** → prompt to enable.
- **No fix / low accuracy** → faded pointer + "acquiring GPS"; suppress camera jumps on noisy fixes.
- **Asset copy fails / disk full**, **local-server port busy** (retry another port),
  **corrupt PMTiles** → clear error state + retry / re-copy from assets.
- **Backgrounding** → pause location stream (battery); resume on foreground.
- **iOS vs Android permissions** → Info.plist usage strings + AndroidManifest entries for both.
- **Style/glyph/sprite load failure** → fail loudly in dev (this is why we bundle them).

## 9. Testing strategy (test-driven where it fits)

- **Unit:** `pmtiles_reader` (parse header/directory, return a known tile from a tiny fixture),
  `local_tile_server` (correct bytes for a z/x/y), location smoothing, version-stamp logic.
- **Widget:** `MapScreen` renders + controls present; permission-denied banner shows (mocked services).
- **Integration smoke test:** launch with networking disabled, assert the style loads from `127.0.0.1`
  and a tile returns 200 (**proves offline**); feed a mock location and confirm the pointer moves.
- **Manual:** Android emulator with a mock GPS route → pan/zoom/tilt/follow + airplane-mode check.

## 10. Success criteria

1. App launches → Ghatshila offline map appears; pan/zoom/rotate/tilt are smooth.
2. With real or mock GPS, the arrow pointer sits at the correct location, rotates with heading, and
   follows movement; recenter works.
3. **All networking off → everything still works.**
4. Runs on an Android emulator/device (and on iOS once full Xcode is available).

## 11. Open items / risks to confirm during implementation

- **`pmtiles://` direct support** in the `maplibre` plugin on mobile is uncertain → spike it; the
  local-server fallback is the safety net.
- Exact **`maplibre` plugin API** for symbol rotation, pitch control, and a follow-camera → confirm
  against the chosen plugin version.
- **Heading source** quality (GPS course vs compass) for a smooth pointer → tune in-app.
- **Glyphs/sprites packaging** for `protomaps-themes-base` offline → confirm the font stacks needed.
- **PMTiles reader** choice (Dart `pmtiles` package vs small custom range-reader) → decide during the
  tile-service spike.

## 12. References

- `offline-map-app-research.html` — full architecture & tech-stack research (8 verified findings).
