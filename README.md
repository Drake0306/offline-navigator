# Offline Navigator

An offline-first Flutter navigation app (Android + iOS + macOS desktop). **Milestone 1** delivers a fully offline MapLibre vector map of Ghatshila, Jharkhand — including a live GPS directional arrow pointer that rotates to your heading, 2.5D camera tilt, a follow-camera mode, and a permission banner. The bundled tile pack, glyph fonts, and style are copied to on-device storage on first launch so the map works completely in airplane mode afterwards.

---

## Prerequisites

| Requirement | Check |
|---|---|
| Flutter ≥ 3.35 / Dart ≥ 3.9 | `flutter --version` |
| Connected Android/iOS device or emulator | `flutter devices` |
| *(Dev-time only)* `pmtiles` CLI — to regenerate tiles | `go install github.com/protomaps/go-pmtiles@latest` |

---

## Regenerate offline data (optional — a pack is committed)

A pre-built `assets/tiles/ghatshila.pmtiles` and glyph fonts are already committed and bundled into the app. You only need these scripts if you want to refresh the tile data or fonts:

```bash
tool/generate_tiles.sh         # extract Ghatshila .pmtiles from Protomaps daily build
tool/fetch_assets.sh           # fetch offline glyph PBF ranges (Noto Sans Regular)
```

`generate_tiles.sh` accepts an optional `BUILD_DATE` argument (YYYYMMDD) in case the default date is no longer available on `build.protomaps.com`:

```bash
tool/generate_tiles.sh 20260501
```

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

The integration test proves the offline path end-to-end: it calls `TileService.ensureReady()`, verifies `style.json` is served from `127.0.0.1`, and confirms the tile server responds — all without any external network access.

> **macOS note:** the integration test also runs on macOS desktop (no mobile device needed). The `com.apple.security.network.server` entitlement required for the local HTTP server is already committed in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.

---

## Manual offline acceptance checklist

These steps exercise the full on-device experience that cannot be covered by automated tests (live GPS + visual rendering). Run them on a real Android or iOS device:

1. `flutter run` — let the map load once (this seeds the on-device tile cache).
2. Enable **airplane mode** on the device.
3. Confirm the Ghatshila basemap still renders (roads, water, labels).
4. Pan, zoom, and rotate — confirm smooth interaction.
5. Press the **3D button** (bottom-right) — confirm the camera tilts to ~50°.
6. Walk or use mock GPS near 22.586° N, 86.476° E — confirm the orange arrow pointer appears, rotates to heading, and the camera follows.
7. Manually pan the map — confirm follow mode disables and the **recenter button** re-enables it.

---

## Architecture

The app is a thin Flutter UI (`MapScreen`) over three focused modules:

- **`TileService`** — copies the bundled PMTiles pack and glyph fonts into application support storage on first launch, then starts an in-process `shelf` HTTP server on `127.0.0.1` that serves `/tiles/{z}/{x}/{y}.mvt`, `/fonts/{fontstack}/{range}.pbf`, and `/style.json` to MapLibre.
- **`LocationService`** — wraps `geolocator` with permission handling and exponential-moving-average smoothing of position + heading (with wraparound-aware heading interpolation).
- **`MapScreen`** + **`UserPointer`** — the MapLibre map widget wired to the tile server URL, a GeoJSON symbol layer for the rotatable pointer icon, follow-camera logic, tilt toggle, and the permission banner.

Full design rationale and architecture decisions:
- Spec: `docs/superpowers/specs/2026-05-31-offline-map-foundation-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-31-offline-map-foundation.md`
- Research: `offline-map-app-research.html`

---

## Verification status (Milestone 1)

| What | Status |
|---|---|
| `flutter analyze` — whole project | **PASS** — "No issues found!" |
| `flutter test` — 18 unit + widget tests | **PASS** — all 18 passed |
| Offline smoke test (`integration_test/offline_smoke_test.dart`) on macOS | **PASS** — tile server starts, `style.json` + tiles served from `127.0.0.1` with no network |
| On-device **mobile** visual rendering (Android / iOS) | **NOT YET VERIFIED** — no mobile device was available in the dev environment |
| Live GPS arrow pointer + follow camera on mobile | **NOT YET VERIFIED** — requires manual acceptance steps above on a real/emulated device |

The core offline infrastructure (tile pack, local HTTP server, asset copy, EMA smoothing) is covered by automated tests. The on-device visual and GPS experience has not been checked; the manual checklist above is the next verification step.
