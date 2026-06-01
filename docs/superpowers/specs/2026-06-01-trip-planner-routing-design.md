# Milestone 3 — Trip Planner with Offline Routing (Design Spec)

- **Date:** 2026-06-01
- **Status:** Approved (design); pending spec review → implementation plan(s)
- **Project:** Offline-first Android + iOS navigation app ("Offline Navigator")
- **This milestone:** plan a trip A→B with intermediate stops, routed fully offline over downloaded
  map data, with a maneuver list and live progress. Engine: **Valhalla** (tiled, on-device).

---

## 1. Context & vision

Milestones 1–2 delivered the offline map, styles/dark mode, and offline search. This milestone adds
**routing / trip planning**. The user's stated vision (which shapes the whole architecture):

> The app is not about one baked-in region. A user downloads a map area of **any size** (bounded only
> by their phone's storage — city, country, or continent). **Inside the downloaded area, navigation
> works fully offline.** Internet off → local navigation over what's downloaded. Internet on → more
> area becomes available. Routing must work over *whatever* is downloaded, at any scale.

Two consequences are **locked architectural principles**:
1. **No size cap** — coverage is bounded by device storage, not a hardcoded limit.
2. **Tiled + hierarchical routing is mandatory** — you cannot hold a continental road graph in memory;
   the router must load only the tiles along a route's corridor, so memory stays bounded regardless of
   total downloaded size. This is exactly **Valhalla's** design, which is why it's the chosen engine.
3. **Region-agnostic engine** — routing is an algorithm over per-region tile data; we build it
   generically and test on the one region we have (Ghatshila). The future **region download manager**
   (queued milestone) feeds it larger regions by running the same tile pipeline per download.

**Honest risk note:** the research flagged on-device Valhalla (`Rallista/valhalla-mobile`) as "not yet
production-ready." The user chose to build the full stack and verify on-device at the end. This spec is
structured so that **only the native Valhalla seam is unverifiable in the dev environment** (no mobile
device, no full Xcode, no Docker here); everything above it is pure Dart and verified with `flutter
test` using a fake routing service. See §6.

## 2. Goal

From the map, the user opens a trip planner, sets a start (defaults to GPS), a destination, and
optional ordered stops (via search or map long-press), picks a travel mode (car/motorbike/bike/walk),
and gets an offline-computed route drawn on the map with total distance + ETA, a scrollable maneuver
list, and live progress (current step highlighted, advancing as they move; off-route → re-route). No
voice (deferred). Works fully offline within downloaded tiles.

## 3. Decisions (locked)

| Area | Decision |
|---|---|
| Engine | **Valhalla**, tiled + hierarchical, on-device via `Rallista/valhalla-mobile` (Android AAR + iOS SPM/xcframework) |
| Scale | **No cap** — bounded by device storage; tiled routing keeps memory bounded at any total size |
| Region model | **Region-agnostic** — same engine over any region's tiles; tested on Ghatshila; download manager feeds bigger regions later |
| Travel modes | **car, motorbike, bike, walk** (Valhalla costing: auto / motorcycle / bicycle / pedestrian) |
| Set points | Start defaults to **GPS** (editable); destination + stops via **search** OR **map long-press**; stops = editable ordered list |
| Guidance | **Route line + distance/ETA + maneuver list + live progress** (snap-to-route, highlight current step, off-route re-route). No voice. |
| Boundary | UI/domain depend on a **`RoutingService` interface**, never on Valhalla directly — so the planner is built + tested with a `FakeRoutingService` and the native engine is a drop-in |
| Build approach | Build the full stack; the native Valhalla bridge is verified **on the user's device** |

## 4. Decomposition (sub-milestones)

Ordered so the risky native work is isolated and the testable Dart work isn't blocked behind it. Each
sub-milestone gets its own implementation plan; this one spec covers all of M3.

| Sub | What | Verifiable in dev env? |
|---|---|---|
| **M3.0** | Valhalla **tile pipeline** (build-time, Docker): OSM bbox → `valhalla_build_tiles` → `assets/routing/ghatshila_tiles.tar` | Scripted here; tile *generation* needs Docker on the user's machine |
| **M3.1** | **Native build + FFI bridge**: `valhalla-mobile` Android AAR + iOS SPM; Dart `ValhallaRoutingService` calling `route(requestJson)→responseJson`; `ensureReady()` extracts bundled tiles | **Device-only** — the make-or-break seam |
| **M3.2** | **Route domain model** (pure Dart): `RoutePlan/RouteLeg/Maneuver/TripStop`, polyline decode, Valhalla-JSON parser, formatters | ✅ unit-tested here |
| **M3.3** | **Trip planner UI**: set points (GPS/search/long-press), mode selector, draw route, distance/ETA, maneuver list | ✅ widget-tested here with `FakeRoutingService` |
| **M3.4** | **Live progress**: snap GPS to route, highlight current maneuver, advance, off-route re-route | ✅ logic unit-tested here; visual on-device |

## 5. Architecture

```
TripPlannerScreen / TripPanel (UI)
  • set start (GPS default) / destination / ordered stops (search or map long-press)
  • mode selector (car/motorbike/bike/walk)
  • draws route line (style-swap-safe via _routeReady guard) + start/stop/dest markers
  • bottom sheet: distance + ETA + scrollable maneuver list
        │ depends on (interface only)
        ▼
RoutingService (abstract)
  Future<RoutePlan> route(List<LatLng> points, TravelMode mode)
  Future<void> ensureReady()
        ├── FakeRoutingService     (tests + dev: canned RoutePlan)
        └── ValhallaRoutingService (prod: builds request JSON → native bridge → parser → RoutePlan)
                  │ calls
                  ▼
        Native bridge (platform): route(requestJson) → responseJson
          Android: com.rallista:valhalla (AAR);  iOS: valhalla-mobile SPM/xcframework
          tiles: bundled ghatshila_tiles.tar → extracted to app storage (version-stamped)

TripState (pure Dart) — ordered points (start..stops..dest), mode; reduces add/remove/reorder
Route domain (pure Dart) — RoutePlan/RouteLeg/Maneuver, polyline decoder, JSON parser, formatters
LiveProgress (pure Dart) — snap-to-route, current-maneuver, off-route detection
```

**Units & responsibilities**
- **`RoutingService`** (interface) — the seam; UI/domain never import Valhalla.
- **`RoutePlan` + parser + polyline decoder + formatters** — pure Dart; the contract, tested against a
  captured Valhalla JSON fixture so the UI is correct before the native lib exists.
- **`TripState`** — immutable trip: ordered points + mode; pure reducer for add/remove/reorder/clear.
- **`ValhallaRoutingService`** — request-builder (testable) + native call + parse. Only the native call
  is device-only.
- **`LiveProgress`** — point-to-polyline snapping, current-maneuver selection, off-route threshold.
- **`TripPlannerScreen`/`TripPanel`** — the UI; consumes `RoutingService` + `RoutePlan`.

## 6. What is and isn't verifiable in the dev environment

- ✅ **Verified here (`flutter test`):** domain model, polyline decoder, JSON parser (vs fixture),
  formatters, `TripState` reducer, off-route/maneuver-advance logic, request-builder JSON, and the
  **entire UI** via `FakeRoutingService`.
- ⚠️ **User's machine (Docker):** generating `ghatshila_tiles.tar` (committed once so the app builds
  without Docker).
- ❌ **User's device only:** whether `valhalla-mobile` compiles/links and actually returns a route on
  Android + iOS. This is the one unproven seam; the spec/plan will say so explicitly and provide exact
  build/run commands. If it can't be made to work, the `RoutingService` interface lets a custom-Dart
  router drop in later without touching the UI (documented fallback).

## 7. Data flow

**Build-time (M3.0, scripted, needs Docker):**
1. Get OSM road network for the bbox (`.osm.pbf`, same bbox as search: `86.35,22.45,86.65,22.75`).
2. `docker run … valhalla_build_tiles` → `valhalla_tiles/` + config.
3. Pack → `assets/routing/ghatshila_tiles.tar`; commit it.
   (The script takes a bbox/pbf arg → region-agnostic; the download manager calls it per region later.)

**Runtime:**
1. `RoutingService.ensureReady()` extracts the bundled tar to app storage (version-stamped, like
   tiles/search DB) and configures the engine to read it.
2. User sets start/dest/stops + mode → `route(points, mode)` builds Valhalla's request JSON
   (locations + costing per mode) → native `route()` → response JSON → parser → `RoutePlan`.
3. UI draws the polyline (style-swap-safe layer), markers, and the distance/ETA + maneuver sheet.
4. Live: each GPS fix → snap to route → highlight current maneuver, update remaining distance/ETA; if
   off-route beyond a threshold → debounced re-route from current position.

## 8. Error handling & edge cases

- Engine fail / tiles missing / not ready → `RoutingException` → "Routing unavailable" + retry; map &
  search keep working; never crashes.
- No route exists → "No route found between these points."
- Point outside downloaded coverage → "destination is outside the downloaded map area" (the seam where
  the download manager / online mode plug in later).
- < 2 points → no route; planner waits for a destination.
- No GPS fix → start shows "Set start point" instead of a missing location.
- Route across style swaps → re-added via `_routeReady` guard (iOS-crash-safe pattern).
- Off-route → debounced re-route (don't thrash on one noisy fix); cap frequency.
- Rapid stop edits → debounce recompute; drop stale in-flight results (sequence-id pattern).
- Offline guarantee → tiles local, engine reads locally, zero network in the routing path.

## 9. Testing

- **Unit (pure Dart):** polyline decoder (known vectors); Valhalla-JSON → `RoutePlan` parser (captured
  fixture); distance/duration formatters; off-route detection (point-to-polyline); maneuver-advance;
  `TripState` reducer; `ValhallaRoutingService` request-builder JSON per mode.
- **Widget (with `FakeRoutingService`):** planner renders; adding a destination computes + draws a
  route; stop reorder/delete; mode switch re-routes; maneuver list; "no route"/"unavailable" states;
  clear-trip wipes everything.
- **Manual on-device (user):** generate tiles (Docker) → build with native dep → plan A→B + a stop →
  see line + distance/ETA + maneuvers → walk/mock-GPS along it → live progress → airplane-mode check.
- **Gate:** `flutter analyze` clean + `flutter test` green (all non-device tests), from real output,
  before each sub-milestone handoff.

## 10. Success criteria

1. The trip planner opens from the map; start defaults to GPS; destination + ordered stops set via
   search or map long-press; mode selectable (car/motorbike/bike/walk).
2. A route is computed **offline** over the bundled tiles and drawn on the map with total distance +
   ETA and a scrollable maneuver list.
3. Live progress highlights the current maneuver and advances along the route; going off-route triggers
   a re-route. Works in airplane mode.
4. All non-device logic + UI is `flutter test`-green via `FakeRoutingService`; the native Valhalla path
   is verified on the user's device per the manual steps.

## 11. References

- Research: `offline-map-app-research.html` (Valhalla on-device, tiled offline routing, valhalla-mobile)
- M2b spec (search, the destination point reused as a trip endpoint): `2026-06-01-offline-search-design.md`
- Roadmap (download manager + online toggle queued): `docs/superpowers/ROADMAP.md`
