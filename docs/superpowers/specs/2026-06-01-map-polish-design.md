# Milestone 2a — Map Polish (Design Spec)

- **Date:** 2026-06-01
- **Status:** Approved (design); pending spec review → implementation plan
- **Project:** Offline-first Android + iOS navigation app ("Offline Navigator")
- **This milestone:** fix the location-permission prompt, add auto dark mode, and add a 4-style map switcher — all fully offline.

---

## 1. Context

Milestone 1 delivered a fully offline MapLibre vector map of Ghatshila with a live GPS arrow
pointer, 2.5D tilt, follow camera, and a permission banner. On the first on-device run the user
reported: (a) the location-permission prompt never appeared, (b) the map does not follow the
phone's dark mode, and (c) there are no map-style options.

The user also requested "Terrain", "Street view", and search / trip-planner features. Those were
triaged out of this milestone:
- **Street view:** impossible offline (needs licensed panoramic imagery + a live service; not in OSM).
- **Terrain:** needs an elevation dataset (hillshade/contours) that is NOT in the bundled OSM vector
  tiles; deferred to a possible later milestone that generates + bundles terrain data.
- **Search** → Milestone 2b. **Trip planner / routing** → Milestone 3. Both are separate specs.

This spec covers **only Milestone 2a: Map Polish.** The app's offline data is OpenStreetMap
**vector** tiles only (layers: boundaries, buildings, earth, landcover, landuse, places, pois, roads,
water) served from an in-app `127.0.0.1` server — no imagery, no elevation.

## 2. Goal

1. The location-permission prompt reliably appears on launch, independent of map-style loading.
2. The map automatically follows the phone's light/dark setting (light→Standard, dark→Dark) until
   the user manually picks a style.
3. A "layers" button opens a sheet to switch between four visual styles — Standard, Light, Dark,
   Roads — each a theme over the same offline tiles. A manual pick sticks for the session; an
   "Auto" option hands control back to the OS-brightness following.

## 3. Decisions (locked)

| Area | Decision |
|---|---|
| Styles | **Four:** Standard, Light, Dark, Roads |
| Dark mode | **Auto + manual override** — follow OS brightness until a manual pick; manual sticks for the session |
| Auto pairing | Auto maps **light→Standard, dark→Dark**; Light and Roads are manual-only picks |
| Switcher UI | A **layers FAB** (above the tilt/recenter FABs) opens a bottom-sheet picker; shows the active style + an "Auto" affordance / "Reset to Auto" |
| Persistence | Manual pick is **session-only** (in-memory); resets to Auto on app restart (no disk storage) |
| Location fix | Request permission at **screen boot** (initState/`_boot`), decoupled from `onStyleLoaded` |
| Map data | **No new data** — all four styles use the existing local OSM tiles + glyphs |

## 4. Scope

**In scope**
- Decouple the location-permission request from map-style loading so it fires reliably at launch.
- Four `style.json` variants in `assets/style/`, each referencing the same local tile/glyph URLs.
- `TileService` copies all four style files to storage and serves each at `/style/<id>.json`.
- A pure-Dart `MapStyleResolver` that resolves (OS brightness, optional manual pick) → active style.
- `MapScreen` watches OS brightness, holds the manual pick, and swaps the active style via
  `MapController.setStyle`, re-adding the user pointer after each swap.
- A `StyleSheet` bottom-sheet picker with the four styles + "Reset to Auto".

**Out of scope (later milestones / not possible)**
- Offline search (M2b), trip planner / routing (M3), terrain (later, needs elevation data),
  street view (impossible offline), persisting the style pick across restarts.

## 5. Architecture

```
MapScreen (existing, slimmed)
  ├── requests location permission at boot ──► LocationService (unchanged)
  ├── watches OS brightness (MediaQuery.platformBrightnessOf)
  └── owns activeStyle state
            │ uses
            ▼
  MapStyleResolver (new, pure Dart, unit-tested)
     resolve(Brightness os, MapStyleId? manualPick) → MapStyleId
     • manualPick != null → manualPick
     • else os == dark    → MapStyleId.dark
     • else               → MapStyleId.standard
            │ active id → local style URL
            ▼
  TileService (extended)
     • ensureReady() copies all 4 style.json variants to storage
     • LocalTileServer serves GET /style/<id>.json (each __BASE__-rewritten)
     • MapReady exposes styleUrlFor(MapStyleId) (or a base + id→path map)
            │
            ▼
  StyleSheet (new widget) — the bottom-sheet picker
```

**Units & responsibilities**
- **`MapStyleId`** (enum: `standard, light, dark, roads`) — identifies a style; maps to an asset
  filename and a `/style/<id>.json` route.
- **`MapStyleResolver`** (pure function/class) — the only logic; resolves the active style. Unit-tested.
- **`TileService` / `LocalTileServer`** (extended) — serve four styles instead of one. The server
  already rewrites `__BASE__`; it now does so per style file and routes `/style/<id>.json`.
- **`MapScreen`** (modified) — boot-time permission request; brightness watch; active-style state;
  `setStyle` on change + pointer re-add; layers FAB.
- **`StyleSheet`** (new widget) — picker UI; reports the chosen `MapStyleId` or "auto".

## 6. Data flow

**Location prompt (the fix)**
1. `initState`/`_boot` calls `LocationService.ensurePermission()` immediately, independent of the map.
2. Two readiness flags are tracked: `permissionGranted` and `styleLoaded`.
3. Pointer source/layer + the position-stream subscription are wired only when **both** are true,
   so neither ordering (permission-first or style-first) can drop the wiring.
4. If permission is denied, the banner shows at once; the map still pans/zooms.

**Style switching**
1. Active style = `MapStyleResolver.resolve(currentBrightness, manualPick)`.
2. On change (brightness change while in Auto, or a manual pick), call
   `controller.setStyle(styleUrlFor(active))`.
3. `setStyle` clears runtime-added layers, so reset `_pointerReady = false`; when the new style's
   `onStyleLoaded` fires, re-add the pointer image/source/layer and resume the stream. Camera
   (center/zoom/tilt/follow) is preserved across the swap.
4. Tapping "Reset to Auto" clears `manualPick`, re-enabling brightness following.

**Style files (build-time)**
- Four `style.json` files are produced from one shared base structure with per-style palettes (a
  small generator script OR four template-derived committed files — the plan picks the cleaner of
  the two; the committed outcome is four files under `assets/style/`). Each keeps the literal
  `__BASE__` tokens for the tile/glyph URLs.

## 7. Styles

| Style | Look |
|---|---|
| **Standard** | Current colorful day map (warm land, blue water, white roads, labels). |
| **Light** | Muted, low-contrast minimal (soft greys/off-white, deemphasized fills). |
| **Dark** | Night map (dark background, dimmed roads, light text with dark halos). |
| **Roads** | Navigation look (roads emphasized; buildings/landuse muted; fewer labels). |

All four reference the same `protomaps` vector source and `Noto Sans Regular` glyphs via `__BASE__`.

## 8. Error handling & edge cases

- **Style swap clears the pointer** → reset `_pointerReady`; re-add pointer on the new style's load.
- **Rapid style toggling** → `_pointerReady` guard + existing try/catch; a fast repeat no-ops.
- **Brightness change during a manual session** → ignored (manual wins); no flicker.
- **Permission denied at boot** → banner shows immediately; map remains interactive.
- **Permission/style ordering race** → resolved by the two-flag (`permissionGranted`, `styleLoaded`) gate.
- **A style file fails to load/parse** → fall back to Standard and log; never a blank map.
- **Offline guarantee preserved** → every style references only local `127.0.0.1` URLs; no new network.

## 9. Testing

- **Unit (real):** `MapStyleResolver` — auto→Standard in light, auto→Dark in dark, manual pick
  overrides both, reset-to-auto restores following. `TileService`: all four style assets are
  discovered and each served `/style/<id>.json` returns 200 with `__BASE__` rewritten.
- **Widget:** layers FAB present (keyed) and opens `StyleSheet`; selecting a style updates the
  active selection; `MapScreen(autoStart:false)` still renders controls with no platform channels.
- **Manual on-device:** toggle phone dark mode → map follows; open sheet → switch each of the 4
  styles → pointer re-appears each time; "Reset to Auto" re-enables following; verify in airplane mode.
- **Gate:** `flutter analyze` clean + `flutter test` green, verified from actual command output
  before handing off for a device run.

## 10. Success criteria

1. Launching the app reliably shows the OS location-permission prompt (or the in-app banner if
   previously denied) — independent of whether/when the map style finishes loading.
2. With no manual pick, the map shows Dark when the phone is in dark mode and Standard otherwise,
   and switches live when the phone's setting changes.
3. The layers button opens a picker; choosing Standard/Light/Dark/Roads changes the map and keeps
   the GPS pointer; "Reset to Auto" restores OS-brightness following.
4. Everything works in airplane mode after first launch.

## 11. References

- M1 spec: `docs/superpowers/specs/2026-05-31-offline-map-foundation-design.md`
- Research: `offline-map-app-research.html`
