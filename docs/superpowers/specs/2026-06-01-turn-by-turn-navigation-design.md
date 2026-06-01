# Milestone 4 — Turn-by-Turn Drive Mode (+ routing fixes) (Design Spec)

- **Date:** 2026-06-01
- **Status:** Approved (design); pending spec review → implementation plan
- **Project:** Offline-first Android + iOS navigation app ("Offline Navigator")
- **This milestone:** fix the routing bugs that made every route a straight line, and build the
  missing turn-by-turn DRIVE MODE (heading-up follow camera, compass, live maneuver banner,
  auto re-route).

---

## 1. Context

On the first real Android build, two problems surfaced:
1. **Every route drew as a straight line** through a blank canvas — even though the map (buildings,
   roads, water) rendered fine. Root cause: `ValhallaPlugin` opened bundled tiles from
   `assets/routing/...`, but Flutter exposes assets to Android native at **`flutter_assets/assets/...`**.
   So `ensureReady()` threw `FileNotFoundException`, the channel returned `ROUTE_FAILED`, and
   `fallbackToFake: true` SILENTLY drew a straight-line route. The silent fallback hid the bug for a
   whole build cycle.
2. **There is no turn-by-turn / drive mode.** Part 1 built the route line, a maneuver LIST, and the
   live-progress MATH (`nearestManeuverIndex`, `isOffRoute`), but never a "Start navigation → camera
   enters a heading-up follow/drive view that tracks you and rotates with your heading." The user's
   "navigation doesn't start, the view doesn't change, the compass doesn't work" is this missing
   feature, not a broken button. `geolocator` gives no heading when stationary, and nothing read the
   magnetometer — so the map never reoriented.

maplibre 0.3.5 supports everything drive mode needs: `animateCamera({center, zoom, bearing, pitch})`
for a heading-up tilted follow camera (verified in the installed package).

## 2. Goal

Routes follow real roads (fix), and a "Start" button enters a full driving experience: the map zooms
in, tilts ~60°, and **rotates so the direction of travel is up**, following the user; a top banner
shows the next maneuver + distance and advances live; going off-route auto-reroutes; an "End" button
exits. Heading comes from GPS course while moving and the **compass when slow/stopped**.

## 3. Decisions (locked)

| Area | Decision |
|---|---|
| Straight-line fix | `ValhallaPlugin` opens `flutter_assets/assets/routing/...` (DONE in code) |
| Failure behavior | **No silent fallback** — `ValhallaRoutingService(fallbackToFake: false)`; real errors shown. `FakeRoutingService` kept for tests only |
| Drive mode | **Full heading-up:** zoom ~17, pitch 60, bearing = heading (map rotates as you turn), tight follow |
| Heading source | **GPS course while moving (>~2 m/s), compass (magnetometer) when slow/stopped**; smoothed, shortest-path angle |
| Live progress | Banner advances through maneuvers; **auto re-route** when off-route (>~40 m, debounced) |
| Nav UI | Top maneuver banner (instruction + icon + distance, + secondary "then…"); bottom status (ETA/remaining + **End**); FABs hidden in drive mode (recenter kept) |
| State | A `NavState { idle, planning, navigating }` machine; "Start" triggers planning→navigating |
| New dep | `flutter_compass` (magnetometer heading) |
| Out of scope | Voice guidance; lane guidance; the region download manager (routing still limited to bundled Ghatshila tiles) |

## 4. Scope

**In scope**
- **Fixes:** asset path (done); remove silent fallback; clearer Valhalla error mapping.
- **`NavController`/`NavState`:** idle/planning/navigating transitions holding the active plan +
  current maneuver index.
- **`HeadingProvider`:** fuse GPS course + compass into a smoothed heading stream.
- **Drive-mode camera:** heading-up tilted follow on each fix (only while navigating), snapped to route.
- **Drive-mode UI:** maneuver banner, remaining ETA/distance, End button, FAB hide, route-behind trim,
  navigation chevron puck.
- **Live progress:** maneuver advance + debounced off-route auto re-route + arrival.

**Out of scope**
- Voice/TTS, lane guidance, speed limits; the download manager (routing stays within bundled tiles —
  driving past them ends in a graceful "outside the downloaded map area").

## 5. Architecture

```
MapScreen (orchestrator) — owns NavController
  ├── planning  → TripPlannerPanel (existing) + a new "Start" button
  └── navigating → NavigationOverlay (new): maneuver banner + status bar + End
        │ drives
        ▼
NavController (new) — NavState machine: idle/planning/navigating; activePlan; currentManeuverIndex;
  startNavigation(plan), exit(), advance(position), markOffRoute()
        │ consumes
        ▼
HeadingProvider (new) — Stream<double> heading: GPS course (moving) / compass (stopped), smoothed
  (uses geolocator Position.heading + flutter_compass; reuses _lerpAngle)
        │ + position drives
        ▼
Drive-mode camera (in MapScreen) — animateCamera(center: snapped, zoom 17, pitch 60, bearing: heading)
RoutingService (unchanged interface) — ValhallaRoutingService(fallbackToFake:false) for re-routes
Existing reused: nearestManeuverIndex / isOffRoute / distanceToRouteMeters (live_progress.dart),
  RoutePlan / Maneuver (route_plan.dart), RouteLayer (route line, _routeReady guard), UserPointer.
```

**Units & responsibilities**
- **`NavController`** — the state machine; pure-ish (no platform). Tested.
- **`HeadingProvider`** — heading fusion; pure logic over injected GPS/compass inputs. Tested.
- **`NavigationOverlay`** (widget) — banner + status + End. Widget-tested with a fixed plan/index.
- **`MapScreen`** (modified) — wires Start/End, the drive-mode camera, FAB hide, route-trim, and the
  live GPS→advance/re-route loop.
- **Fixes** in `ValhallaPlugin.kt` (asset path) + `map_screen.dart` (fallback off) + error mapping.

## 6. Data flow

**Start:** route computed in `planning` → user taps **Start** → `NavController.startNavigation(plan)`
→ state `navigating`; FABs hide; `NavigationOverlay` shown; subscribe to position + `HeadingProvider`.

**Each location/heading tick (navigating):**
1. Snap position to the route polyline (`distanceToRouteMeters` + projection).
2. `animateCamera(center: snapped, zoom 17, pitch 60, bearing: heading, ~700ms)`.
3. `currentManeuverIndex = nearestManeuverIndex(position, maneuverLocations)`; banner updates;
   recompute remaining distance/ETA; trim the route line behind the snapped point.
4. If `isOffRoute(position, geometry, 40m)` for N consecutive fixes (debounce) → `route()` from
   position to destination, redraw, continue; on routing failure → "outside the downloaded map area"
   banner state.
5. Within ~30 m of destination & past last maneuver → "You have arrived".

**End:** tap End → `NavController.exit()` → state `planning`; camera relaxes; FABs + panel return;
route still drawn.

## 7. Error handling & edge cases

- No GPS fix at start → "Waiting for GPS…"; camera holds at route start.
- Compass unavailable → GPS-course-only; heading holds when stopped (no error).
- Off-route re-route fails (outside tiles) → stop retrying; banner "Off route — outside the downloaded
  map area" + End/Re-plan.
- Arrival → "You have arrived"; no auto-exit.
- GPS jitter → snapping + EMA + shortest-path angle lerp; cap re-route frequency.
- Backgrounding mid-drive → pause camera/heading; resume on foreground (existing lifecycle observer).
- Style swap during nav → route line + chevron re-added via existing `_routeReady`/`_pointerSourceReady`
  guards.
- Routing failure now VISIBLE (no silent fallback) → real message in the planning panel; live states
  cover navigating.
- Offline guarantee unchanged → tiles local; heading from device sensors; no network.

## 8. Testing

- **Unit (pure Dart, green here):** `NavController` transitions (start→navigating w/ plan; exit→planning;
  clear→idle; advance updates index); `HeadingProvider` fusion (moving→GPS course; stopped→compass;
  missing-compass→GPS-only; smoothing/shortest-path); remaining-distance/ETA; off-route→re-route trigger
  (debounced, capped); `ValhallaRoutingService(fallbackToFake:false)` error mapping (no silent fake).
- **Widget (green here):** maneuver banner shows correct instruction/icon/distance for a plan+index;
  the **Start** button appears when routable and transitions to navigating; drive mode shows banner +
  End and hides the FABs; arrival/off-route banner states render.
- **Existing suite stays green** (interface unchanged; fake kept for tests).
- **Device (user):** plan a Ghatshila route → confirm it **follows roads** (asset fix) → **Start** →
  map enters drive mode, **rotates with heading** (incl. compass when stopped), follows you, banner
  advances, off-route reroutes, **End** exits.
- **Gate:** `flutter analyze` clean + `flutter test` green from real output.

## 9. Success criteria

1. After rebuild, a Ghatshila route **follows roads** (not a straight line); a routing failure shows a
   **real error**, not a silent straight line.
2. A planned route has a **Start** button that enters drive mode.
3. Drive mode: camera zooms/tilts and **rotates to heading** (GPS course moving, compass stopped),
   follows the user; a top banner shows + advances the next maneuver with distance; remaining ETA shows;
   off-route auto-reroutes; **End** exits.
4. All non-device logic + UI is `flutter test`-green; the live drive experience is verified on-device.

## 10. References

- M3 part 2 spec (native engine, the asset-path note): `2026-06-01-native-valhalla-routing-design.md`
- M3 part 1 plan (route domain, live-progress math reused): `2026-06-01-trip-planner-ui.md`
- maplibre 0.3.5 `MapController.animateCamera({center,zoom,bearing,pitch})` — installed package.
- Roadmap: `docs/superpowers/ROADMAP.md`
