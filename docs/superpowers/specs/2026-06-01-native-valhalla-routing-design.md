# Milestone 3 Part 2 — Native Valhalla Routing on Android (Design Spec)

- **Date:** 2026-06-01
- **Status:** Approved (design); pending spec review → implementation plan
- **Project:** Offline-first Android + iOS navigation app ("Offline Navigator")
- **This milestone:** replace the placeholder `FakeRoutingService` with a REAL on-device routing
  engine (Valhalla via `valhalla-mobile`) on **Android**, over BUNDLED Ghatshila routing tiles, to
  prove the native engine runs on the phone.

---

## 1. Context & honest scope

M3 Part 1 built the trip-planner UI + domain over a `RoutingService` interface, with a placeholder
`FakeRoutingService` returning straight-line routes. This part swaps in a real engine on Android.

**Critical, user-acknowledged architecture fact:** a phone **cannot generate** routing tiles. Tile
generation (`valhalla_build_tiles`) is a heavy computer/server batch job over raw OSM. The phone only
**consumes** pre-built tiles. Therefore routing works **only where tiles exist on the device.**

**Scope of THIS part (deliberately limited):** bundle Valhalla routing tiles for the **Ghatshila
area only** and get real, road-following routing working on the user's Android phone. This **proves
the native engine runs on-device** (the project's single riskiest unknown). It does **NOT** route
arbitrary regions: e.g. **Ghatshila → Visakhapatnam (~600 km) will correctly fail** because those
tiles aren't on the device. That failure is expected behaviour, not a bug — it's the boundary the
**download manager** milestone removes next.

**Built to become the real thing:** the engine reads tiles from **app storage** (not hardcoded
assets), so the future download manager can drop new regions' tiles into the same storage and routing
"just works" over them. Nothing here is throwaway.

**Verified API (read from the `Rallista/valhalla-mobile` source, not guessed):**
- Android dep `io.github.rallista:valhalla-mobile:0.1.0`, package `com.valhalla.valhalla`.
- Raw seam: `ValhallaActor(configPath: String).route(request: String): String` — request and response
  are plain JSON strings. Response is the Valhalla `trip{...}` shape OUR EXISTING `parseValhallaRoute`
  already handles. Errors come back as `{"code":<int>,"message":"..."}` (e.g. code 171 "No suitable
  edges near location").
- Config: a `valhalla.json` whose tile path points at the tiles; `ValhallaActor` is constructed with
  that config file's path. Tiles can be a tar extract + `admins.sqlite`.
- (iOS exists — `import Valhalla`, `Valhalla(config).route(...)`, `ValhallaConfig(tileExtractTar:)` —
  but is OUT of scope for this part; Android first.)

## 2. Goal

Plan a Ghatshila A→B(+stops) trip and get a real route that **follows roads** (vs. Part 1's straight
line), with the maneuver list + distance/ETA already built in Part 1, computed fully offline on the
device by the native Valhalla engine over bundled tiles.

## 3. Decisions (locked)

| Area | Decision |
|---|---|
| Platform | **Android first** (iOS in a later part) |
| Engine | Valhalla via `io.github.rallista:valhalla-mobile:0.1.0` (Android AAR) |
| Bridge | **MethodChannel** `offline_navigator/valhalla` (NOT FFI — the lib exposes a clean `route(String)→String`) |
| Tiles | **Bundled** Ghatshila `valhalla_tiles.tar` + `admins.sqlite` + a `valhalla.json` template; generated here via Docker and **verified to route in Docker before commit** |
| Tile loading | Native side copies tiles into **app storage** (version-stamped) and points the config there — so the download manager can later add regions to the same store |
| Bbox | Slightly LARGER than the map/search bbox (pad ~0.1°) so edge roads connect for routing |
| Reuse | Response parsed by the EXISTING `parseValhallaRoute` (Part 1) → `RoutePlan` |
| Fallback | Runtime flag: on native failure, fall back to `FakeRoutingService` so the app still routes while debugging. Default **on**. |
| Out of scope | iOS native; routing outside the bundled tiles; the download manager / tile hosting (next milestone) |

## 4. Architecture

```
TripPlannerPanel (Part 1, unchanged) → RoutingService (interface, Part 1)
                                              ├── FakeRoutingService (tests + fallback)
                                              └── ValhallaRoutingService (NEW, Android)
                                                       │ MethodChannel 'offline_navigator/valhalla'
                                                       ▼
                                            Kotlin ValhallaPlugin (NEW)
                                              • ensureReady: copy bundled tar+admins.sqlite → app
                                                storage (version-stamped), write valhalla.json
                                                pointing there, cache ValhallaActor(configPath)
                                              • route(requestJson) → ValhallaActor.route() → responseJson
                                                       │ uses
                                                       ▼
                                            io.github.rallista:valhalla-mobile (AAR)
                                              ValhallaActor(configPath).route(String) → String
                                            tiles: assets/routing/valhalla_tiles.tar (+ admins.sqlite)
                                                   generated by tool/generate_valhalla_tiles.sh (Docker)
```

**Units & responsibilities**
- **`tool/generate_valhalla_tiles.sh`** — Docker pipeline (build_config → build_admins → build_tiles
  → pack tar); region-agnostic (bbox arg). Run here; verifies a test route before committing assets.
- **`ValhallaPlugin.kt`** — the MethodChannel handler: tile/config setup + `route`.
- **`ValhallaRoutingService` (Dart)** — implements `RoutingService`; request-builder + error-mapping +
  feeds responses to the existing parser. Unit-tested with a mocked channel.
- **`MapScreen`** — swap `_routing` from `FakeRoutingService` to `ValhallaRoutingService` (with the
  fallback flag). No other UI change — the interface is unchanged.

## 5. Data flow

**Build-time (here, Docker — committed once):**
1. Get raw OSM `.osm.pbf` for the padded Ghatshila bbox.
2. Docker: `valhalla_build_config` → `valhalla_build_admins` (→ `admins.sqlite`) → `valhalla_build_tiles`
   → tar the tiles → `valhalla_tiles.tar`.
3. Verify in Docker: `valhalla_run_route` on a Ghatshila A→B returns a real `trip{...}` with
   road-following shape. Only then commit `assets/routing/{valhalla_tiles.tar, admins.sqlite,
   valhalla.json}`.

**Runtime (device):**
1. `ValhallaRoutingService.ensureReady()` → channel `ensureReady`: native copies the bundled tar +
   admins.sqlite into app storage (version-stamped), writes `valhalla.json` with the storage tile
   path, constructs + caches `ValhallaActor(configPath)`.
2. `route(points, mode)` → build request JSON `{"locations":[{"lat","lon"}...],"costing":
   <mode.costing>,"units":"kilometers"}` → channel `route` → native `ValhallaActor.route(json)` →
   response JSON.
3. Dart: if response is `{"code","message"}` → `RoutingException`; else `parseValhallaRoute` →
   `RoutePlan`. UI draws the road-following line + maneuvers (Part 1 code, unchanged).

## 6. Error handling & edge cases

- Engine not ready / tiles missing → `ensureReady` throws → `RoutingException("Routing engine unavailable")`; panel shows error; map/search keep working.
- No route / "no suitable edges" (Valhalla code 171) → `RoutingException("No route found near here")`.
- Point outside bundled tiles → Valhalla error → "destination is outside the downloaded map area"
  (honest: only Ghatshila tiles exist this part).
- Native channel failure (AAR not linked / platform exception) → caught in Dart; if fallback flag on,
  transparently use `FakeRoutingService` so the app still routes while debugging; else show error.
  Default: fallback ON.
- Malformed response → `parseValhallaRoute` throws `FormatException` → wrapped as `RoutingException`.
- Offline guarantee → tiles are local files in app storage; engine on-device; zero network in routing.

## 7. Testing

- **Docker (here, before commit):** the tiles route a Ghatshila A→B with road-following geometry —
  proves the data independent of the phone.
- **Unit (Dart, `flutter test` here, mocked MethodChannel):** request-builder produces correct
  Valhalla JSON per mode (car→auto, motorbike→motorcycle, bike→bicycle, walk→pedestrian); error-mapping
  ({"code":171,...} → RoutingException; a valid `trip` → RoutePlan via the existing parser); the
  fallback path (channel throws + flag on → returns a FakeRoutingService route).
- **Existing suite stays green:** trip-planner UI tests keep using `FakeRoutingService` (interface
  unchanged) — whole suite remains `flutter test`-verifiable without a device.
- **Device (user):** build the Android app with the AAR; plan a Ghatshila A→B; confirm the line now
  FOLLOWS ROADS with a real maneuver list (vs. Part 1's straight line). This proves the native engine
  runs on the phone.
- **Gate:** `flutter analyze` clean + `flutter test` green from real output before handoff.

## 8. Success criteria

1. The tile pipeline produces `valhalla_tiles.tar` + `admins.sqlite` that route a Ghatshila A→B in
   Docker (verified here).
2. `ValhallaRoutingService` builds correct per-mode requests and maps responses/errors correctly
   (unit-tested); the app swaps it in behind the unchanged `RoutingService` interface.
3. On the user's Android device, a Ghatshila trip draws a **road-following** route with maneuvers,
   computed offline by the native engine.
4. A route outside the bundled tiles fails gracefully ("outside the downloaded map area") — the
   expected boundary the download manager removes next. App never crashes; fallback keeps it usable.

## 9. References

- M3 spec (overall routing vision, tiled/region-agnostic): `2026-06-01-trip-planner-routing-design.md`
- M3 part 1 plan (domain + UI + the `parseValhallaRoute` parser this reuses): `2026-06-01-trip-planner-ui.md`
- `Rallista/valhalla-mobile` source (verified API): repo `android/valhalla/src/main/java/com/valhalla/valhalla/`
- Roadmap (download manager + tile hosting = the "route anywhere you download" vision): `docs/superpowers/ROADMAP.md`
