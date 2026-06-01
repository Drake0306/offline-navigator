# Turn-by-Turn Drive Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix routing failures (no silent fallback; clearer errors — the asset-path fix is already committed) and build the missing turn-by-turn DRIVE MODE: a "Start" button that enters a heading-up tilted follow camera that rotates with the user's heading (GPS course while moving, compass when stopped), a live maneuver banner, remaining ETA/distance, debounced off-route auto-reroute, and an End button.

**Architecture:** A `NavController` (pure-ish state machine: idle/planning/navigating, active plan, current maneuver index, off-route detection) plus a `HeadingProvider` (fuses geolocator GPS course + flutter_compass into a smoothed heading stream) drive a `NavigationOverlay` widget (maneuver banner + status bar + End) and, in `MapScreen`, a heading-up `animateCamera({zoom, pitch, bearing})` loop. The routing domain + live-progress math (`nearestManeuverIndex`, `isOffRoute`) from earlier milestones are reused. The `RoutingService` interface is unchanged; only `MapScreen` flips `ValhallaRoutingService(fallbackToFake:false)`.

**Tech Stack:** Flutter 3.44 / Dart 3.12; `maplibre` ^0.3.5 (`animateCamera({center, zoom, bearing, pitch})`); `geolocator` (Position.heading/speed); `flutter_compass` ^0.8.1 (`FlutterCompass.events` → `.heading`, 0-360, null if no sensor); existing routing domain. Package: `offline_navigator`.

---

## Conventions & ground rules

- **TDD for pure logic** (NavController, HeadingProvider fusion, ETA/remaining, off-route trigger). Widgets get widget tests. The live camera/heading visuals are device-only.
- **Verify before claiming green:** run `flutter analyze` and `flutter test` and read the ACTUAL final line before saying a task passes or committing. Never commit with analyzer issues or failing tests.
- **Commit after each task.** Run from repo root `/Users/roy/Developer/Github/offline_map`.
- **No mobile device here:** Dart + widget tests are verified here; the on-device drive experience (camera rotation, compass) is the user's step.

### Verified facts / reuse
- `lib/routing/live_progress.dart`: `double distanceToRouteMeters(LatLng, List<LatLng>)`, `bool isOffRoute(LatLng, List<LatLng>, {double thresholdMeters = 40})`, `int nearestManeuverIndex(LatLng, List<LatLng>)`.
- `lib/routing/route_plan.dart`: `RoutePlan{geometry: List<LatLng>, legs, distanceMeters, duration, get maneuvers}`; `Maneuver{instruction, distanceMeters, duration, location: LatLng, type: ManeuverType}`.
- `lib/routing/lat_lng.dart`: `LatLng(lat, lng)`. `lib/location/user_location.dart`: `UserLocation{lat, lng, headingDeg, speedMps, accuracyM, timestamp}` + `smoothedTowards` + a static `_lerpAngle` (shortest-path angle — reimplement inline where needed; it's private).
- `lib/routing/route_format.dart`: `formatDistance(double)`, `formatDuration(Duration)`.
- `maplibre` `MapController.animateCamera({Geographic? center, double? zoom, double? bearing, double? pitch, Duration nativeDuration})` — `Geographic(lon:, lat:)`.
- `flutter_compass` 0.8.1: `FlutterCompass.events` is a `Stream<CompassEvent?>`; `event.heading` is `double?` (degrees, 0=N, null when no sensor).
- `map_screen.dart` currently: a `bool _planning` flag (line ~79), `_startTrip()` (~477), `_onPlanChanged(RoutePlan?)` (~494) drawing the route line, an `onEvent` long-press adding points (~528), the FAB column with `directionsButton` (~588-620), and `if (_planning) TripPlannerPanel(...)` (~625). `_plan` holds the current `RoutePlan?`. `_lastLoc` is the latest `UserLocation?`. `_controller` is `MapController?`, `_routeReady` guards the route line.

---

## File structure

```
lib/nav/nav_state.dart                 NEW  NavState enum + NavController (idle/planning/navigating)
lib/nav/heading_provider.dart           NEW  fuse GPS course + compass → smoothed heading
lib/nav/trip_progress.dart              NEW  remaining distance/ETA + arrival + maneuver-advance (pure)
lib/nav/navigation_overlay.dart         NEW  drive-mode UI: maneuver banner + status bar + End
lib/map/map_screen.dart                 MOD  Start/End, drive-mode camera, FAB hide, nav loop; fallback off
lib/trip/trip_planner_panel.dart        MOD  add a "Start" button (onStart callback) when routable
pubspec.yaml                            MOD  add flutter_compass
test/nav/nav_state_test.dart            NEW
test/nav/heading_provider_test.dart     NEW
test/nav/trip_progress_test.dart        NEW
test/nav/navigation_overlay_test.dart   NEW
test/trip/trip_planner_panel_test.dart  MOD  (Start button present + fires when routable)
```

---

## Task 1: Stop the silent fallback + clearer errors

**Files:**
- Modify: `lib/map/map_screen.dart`
- Modify: `lib/routing/valhalla_routing_service.dart`
- Modify: `test/routing/valhalla_routing_service_test.dart`

- [ ] **Step 1: Flip MapScreen to no-fallback**

In `lib/map/map_screen.dart`, change the routing field:
```dart
// No silent fallback: a native routing failure now surfaces a real error in
// the trip panel instead of secretly drawing a straight line. (FakeRoutingService
// is kept for tests only.) Routing works only within the bundled Ghatshila tiles.
final RoutingService _routing = ValhallaRoutingService(fallbackToFake: false);
```

- [ ] **Step 2: Add a clearer "no suitable edges" message + a tiny test**

In `lib/routing/valhalla_routing_service.dart`, improve the error mapping. Replace the error-branch:
```dart
    if (decoded is Map && decoded.containsKey('code') &&
        !decoded.containsKey('trip')) {
      final code = (decoded['code'] as num?)?.toInt();
      final msg = (decoded['message'] as String?) ?? 'No route found';
      // 171 = no suitable edges near a location (point off the road network or
      // outside the downloaded tiles).
      if (code == 171) {
        throw const RoutingException(
            'No route found near here — the point may be outside the downloaded map area.');
      }
      throw RoutingException(msg);
    }
```
Add to `test/routing/valhalla_routing_service_test.dart` (keep existing tests):
```dart
  test('maps Valhalla code 171 to a friendly "outside map area" message',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ensureReady') return null;
      if (call.method == 'route') {
        return '{"code":171,"message":"No suitable edges near location"}';
      }
      return null;
    });
    final svc = ValhallaRoutingService(fallbackToFake: false);
    await expectLater(
      () => svc.route(const [LatLng(0, 0), LatLng(1, 1)], TravelMode.car),
      throwsA(isA<RoutingException>().having(
          (e) => e.message, 'message', contains('outside the downloaded map area'))),
    );
  });
```

- [ ] **Step 3: Run tests + analyze**

Run: `flutter test test/routing/valhalla_routing_service_test.dart` → PASS (5 tests). Then whole-project `flutter analyze` (clean) + `flutter test` (all pass). The map_screen widget tests never invoke routing, so they stay green.

- [ ] **Step 4: Commit**

```bash
git add lib/map/map_screen.dart lib/routing/valhalla_routing_service.dart test/routing/valhalla_routing_service_test.dart
git commit -m "fix: stop silent straight-line fallback; clearer Valhalla error messages"
```

---

## Task 2: NavController + NavState (pure, TDD)

**Files:**
- Create: `lib/nav/nav_state.dart`
- Test: `test/nav/nav_state_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nav/nav_state_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/nav/nav_state.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';

RoutePlan _plan() => const RoutePlan(
      geometry: [LatLng(22.58, 86.47), LatLng(22.60, 86.49)],
      legs: [
        RouteLeg(distanceMeters: 1000, duration: Duration(minutes: 5), maneuvers: [
          Maneuver(instruction: 'Head north', distanceMeters: 1000,
              duration: Duration(minutes: 5), location: LatLng(22.58, 86.47),
              type: ManeuverType.start),
          Maneuver(instruction: 'Arrive', distanceMeters: 0,
              duration: Duration.zero, location: LatLng(22.60, 86.49),
              type: ManeuverType.destination),
        ]),
      ],
      distanceMeters: 1000,
      duration: Duration(minutes: 5),
    );

void main() {
  test('starts idle', () {
    expect(NavController().state, NavState.idle);
  });

  test('planning() -> planning; startNavigation -> navigating with plan', () {
    final c = NavController()..planning();
    expect(c.state, NavState.planning);
    c.startNavigation(_plan());
    expect(c.state, NavState.navigating);
    expect(c.activePlan, isNotNull);
    expect(c.currentManeuverIndex, 0);
  });

  test('advanceTo sets the nearest maneuver index', () {
    final c = NavController()..planning()..startNavigation(_plan());
    // Near the destination maneuver (index 1).
    c.advanceTo(const LatLng(22.5995, 86.4895));
    expect(c.currentManeuverIndex, 1);
  });

  test('exit() -> planning (keeps no active plan); clear() -> idle', () {
    final c = NavController()..planning()..startNavigation(_plan());
    c.exit();
    expect(c.state, NavState.planning);
    expect(c.activePlan, isNull);
    c.clear();
    expect(c.state, NavState.idle);
  });

  test('notifies listeners on transition', () {
    final c = NavController();
    var n = 0;
    c.addListener(() => n++);
    c.planning();
    c.startNavigation(_plan());
    expect(n, greaterThanOrEqualTo(2));
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/nav/nav_state_test.dart`
Expected: FAIL — `NavState`/`NavController` undefined.

- [ ] **Step 3: Implement**

Create `lib/nav/nav_state.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/live_progress.dart';
import 'package:offline_navigator/routing/route_plan.dart';

/// The screen's high-level mode.
enum NavState { idle, planning, navigating }

/// Drives the navigation state machine. Holds the active route being driven and
/// the current maneuver index, advanced from live positions. A [ChangeNotifier]
/// so the UI rebuilds on transitions.
class NavController extends ChangeNotifier {
  NavState _state = NavState.idle;
  RoutePlan? _activePlan;
  int _currentManeuverIndex = 0;

  NavState get state => _state;
  RoutePlan? get activePlan => _activePlan;
  int get currentManeuverIndex => _currentManeuverIndex;

  /// Enter trip-planning mode.
  void planning() {
    _state = NavState.planning;
    notifyListeners();
  }

  /// Begin driving [plan].
  void startNavigation(RoutePlan plan) {
    _activePlan = plan;
    _currentManeuverIndex = 0;
    _state = NavState.navigating;
    notifyListeners();
  }

  /// Update the current maneuver from a live [position]. No-op unless navigating.
  void advanceTo(LatLng position) {
    final plan = _activePlan;
    if (_state != NavState.navigating || plan == null) return;
    final locs = [for (final m in plan.maneuvers) m.location];
    if (locs.isEmpty) return;
    final idx = nearestManeuverIndex(position, locs);
    if (idx != _currentManeuverIndex) {
      _currentManeuverIndex = idx;
      notifyListeners();
    }
  }

  /// Replace the active plan after a re-route (stays navigating).
  void replacePlan(RoutePlan plan) {
    _activePlan = plan;
    _currentManeuverIndex = 0;
    notifyListeners();
  }

  /// Leave driving, back to planning (route stays available in the UI).
  void exit() {
    _activePlan = null;
    _currentManeuverIndex = 0;
    _state = NavState.planning;
    notifyListeners();
  }

  /// Reset to idle (no trip).
  void clear() {
    _activePlan = null;
    _currentManeuverIndex = 0;
    _state = NavState.idle;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/nav/nav_state_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/nav/nav_state.dart test/nav/nav_state_test.dart
git commit -m "feat: add NavController state machine (idle/planning/navigating, tested)"
```

---

## Task 3: HeadingProvider — fuse GPS course + compass (pure, TDD)

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/nav/heading_provider.dart`
- Test: `test/nav/heading_provider_test.dart`

- [ ] **Step 1: Add flutter_compass**

In `pubspec.yaml` dependencies add `flutter_compass: ^0.8.1`. Run `flutter pub get`.

- [ ] **Step 2: Write the failing test (pure fusion logic — no real sensors)**

The provider's FUSION is a pure function we test directly; the streams are wired in the widget layer.
Create `test/nav/heading_provider_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/nav/heading_provider.dart';

void main() {
  test('moving fast -> uses GPS course', () {
    // speed above threshold: trust GPS course (120), ignore compass (10).
    expect(fuseHeading(gpsCourseDeg: 120, speedMps: 5, compassDeg: 10, lastDeg: 0),
        closeTo(120, 1e-6));
  });

  test('slow/stopped -> uses compass', () {
    expect(fuseHeading(gpsCourseDeg: 120, speedMps: 0.2, compassDeg: 10, lastDeg: 0),
        closeTo(10, 1e-6));
  });

  test('stopped with no compass -> holds last heading', () {
    expect(fuseHeading(gpsCourseDeg: 120, speedMps: 0.2, compassDeg: null, lastDeg: 47),
        closeTo(47, 1e-6));
  });

  test('moving but GPS course invalid (negative) -> holds last', () {
    expect(fuseHeading(gpsCourseDeg: -1, speedMps: 5, compassDeg: null, lastDeg: 33),
        closeTo(33, 1e-6));
  });

  test('result is always normalized to [0,360)', () {
    final h = fuseHeading(gpsCourseDeg: 370, speedMps: 5, compassDeg: null, lastDeg: 0);
    expect(h, greaterThanOrEqualTo(0));
    expect(h, lessThan(360));
    expect(h, closeTo(10, 1e-6));
  });
}
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `flutter test test/nav/heading_provider_test.dart`
Expected: FAIL — `fuseHeading` undefined.

- [ ] **Step 4: Implement**

Create `lib/nav/heading_provider.dart`:
```dart
import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Speed (m/s) above which GPS course is trusted over the compass.
const double kMovingSpeedMps = 2.0;

/// Pure heading fusion: while moving with a valid GPS course, use it; otherwise
/// use the compass; if neither is available, hold [lastDeg]. Result normalized
/// to [0, 360).
double fuseHeading({
  required double gpsCourseDeg,
  required double speedMps,
  required double? compassDeg,
  required double lastDeg,
}) {
  double pick;
  final gpsValid = gpsCourseDeg >= 0; // geolocator uses negative for "unknown"
  if (speedMps >= kMovingSpeedMps && gpsValid) {
    pick = gpsCourseDeg;
  } else if (compassDeg != null) {
    pick = compassDeg;
  } else if (gpsValid) {
    pick = gpsCourseDeg;
  } else {
    pick = lastDeg;
  }
  final n = pick % 360;
  return n < 0 ? n + 360 : n;
}

/// Streams a fused heading by combining geolocator positions (GPS course + speed)
/// with the magnetometer (flutter_compass). Holds the last good heading when
/// stationary and no compass is available.
class HeadingProvider {
  HeadingProvider({Stream<CompassEvent?>? compass})
      : _compass = compass ?? FlutterCompass.events;

  final Stream<CompassEvent?>? _compass;
  final _controller = StreamController<double>.broadcast();
  StreamSubscription<CompassEvent?>? _compassSub;
  double _last = 0;
  double? _lastCompass;

  Stream<double> get headings => _controller.stream;

  void start() {
    _compassSub = _compass?.listen((e) => _lastCompass = e?.heading);
  }

  /// Feed a position update; emits a fused heading.
  void onPosition(Position p) {
    _last = fuseHeading(
      gpsCourseDeg: p.heading,
      speedMps: p.speed,
      compassDeg: _lastCompass,
      lastDeg: _last,
    );
    _controller.add(_last);
  }

  Future<void> dispose() async {
    await _compassSub?.cancel();
    await _controller.close();
  }
}
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `flutter test test/nav/heading_provider_test.dart`
Expected: PASS (5 tests). Then `flutter analyze lib/nav test/nav` clean.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml lib/nav/heading_provider.dart test/nav/heading_provider_test.dart
git commit -m "feat: add HeadingProvider fusing GPS course + compass (tested)"
```

---

## Task 4: Trip progress — remaining distance/ETA + arrival (pure, TDD)

**Files:**
- Create: `lib/nav/trip_progress.dart`
- Test: `test/nav/trip_progress_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nav/trip_progress_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/nav/trip_progress.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';

RoutePlan _plan() => const RoutePlan(
      geometry: [LatLng(22.000, 86.000), LatLng(22.000, 86.010), LatLng(22.000, 86.020)],
      legs: [],
      distanceMeters: 2000,
      duration: Duration(minutes: 10),
    );

void main() {
  test('remaining distance ~full at the start, ~0 at the end', () {
    final p = _plan();
    final atStart = remainingDistanceMeters(const LatLng(22.000, 86.000), p);
    final atEnd = remainingDistanceMeters(const LatLng(22.000, 86.020), p);
    expect(atStart, greaterThan(atEnd));
    expect(atEnd, lessThan(50));
  });

  test('remaining duration scales with remaining distance', () {
    final p = _plan();
    // Halfway along the geometry -> ~half the duration.
    final mid = remainingDuration(const LatLng(22.000, 86.010), p);
    expect(mid.inSeconds, closeTo((p.duration.inSeconds / 2), p.duration.inSeconds * 0.25));
  });

  test('hasArrived true within threshold of the destination', () {
    final p = _plan();
    expect(hasArrived(const LatLng(22.0000, 86.0200), p, thresholdMeters: 30), isTrue);
    expect(hasArrived(const LatLng(22.0000, 86.0000), p, thresholdMeters: 30), isFalse);
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/nav/trip_progress_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement**

Create `lib/nav/trip_progress.dart`:
```dart
import 'dart:math' as math;
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';

/// Remaining distance (metres) along [plan.geometry] from the point on the route
/// nearest [p] to the end. Sums segment lengths after the nearest projection.
double remainingDistanceMeters(LatLng p, RoutePlan plan) {
  final g = plan.geometry;
  if (g.length < 2) return 0;
  // Find the nearest segment and the fraction along it.
  var bestSeg = 0;
  var bestT = 0.0;
  var bestDist = double.infinity;
  for (var i = 0; i < g.length - 1; i++) {
    final (d, t) = _projic(p, g[i], g[i + 1]);
    if (d < bestDist) {
      bestDist = d;
      bestSeg = i;
      bestT = t;
    }
  }
  // Remaining = rest of the current segment + all following segments.
  var rem = _hav(_lerp(g[bestSeg], g[bestSeg + 1], bestT), g[bestSeg + 1]);
  for (var i = bestSeg + 1; i < g.length - 1; i++) {
    rem += _hav(g[i], g[i + 1]);
  }
  return rem;
}

/// Remaining duration, scaled from total by the remaining/total distance ratio.
Duration remainingDuration(LatLng p, RoutePlan plan) {
  if (plan.distanceMeters <= 0) return Duration.zero;
  final frac = (remainingDistanceMeters(p, plan) / plan.distanceMeters).clamp(0.0, 1.0);
  return Duration(seconds: (plan.duration.inSeconds * frac).round());
}

/// True when [p] is within [thresholdMeters] of the route's last point.
bool hasArrived(LatLng p, RoutePlan plan, {double thresholdMeters = 30}) {
  if (plan.geometry.isEmpty) return false;
  return _hav(p, plan.geometry.last) <= thresholdMeters;
}

// --- geometry (equirectangular projection at small scales) ---
(double, double) _projic(LatLng p, LatLng a, LatLng b) {
  const earth = 6371000.0;
  final latRef = _rad(p.lat);
  double x(LatLng q) => _rad(q.lng) * math.cos(latRef) * earth;
  double y(LatLng q) => _rad(q.lat) * earth;
  final px = x(p), py = y(p), ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return (math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay)), 0);
  var t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return (math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)), t);
}

LatLng _lerp(LatLng a, LatLng b, double t) =>
    LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);

double _hav(LatLng a, LatLng b) {
  const earth = 6371000.0;
  final dLat = _rad(b.lat - a.lat), dLon = _rad(b.lng - a.lng);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  return earth * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _rad(double d) => d * math.pi / 180.0;
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/nav/trip_progress_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/nav/trip_progress.dart test/nav/trip_progress_test.dart
git commit -m "feat: add trip-progress (remaining distance/ETA + arrival, tested)"
```

---

## Task 5: NavigationOverlay widget (maneuver banner + status + End)

**Files:**
- Create: `lib/nav/navigation_overlay.dart`
- Test: `test/nav/navigation_overlay_test.dart`

- [ ] **Step 1: Implement the overlay**

Create `lib/nav/navigation_overlay.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:offline_navigator/routing/route_format.dart';
import 'package:offline_navigator/routing/route_plan.dart';

/// Drive-mode overlay: a top maneuver banner and a bottom status bar with End.
/// Pure presentation — given the active plan, the current maneuver index, the
/// remaining distance/duration, and a status string; reports End via [onEnd].
class NavigationOverlay extends StatelessWidget {
  const NavigationOverlay({
    super.key,
    required this.plan,
    required this.currentManeuverIndex,
    required this.remainingMeters,
    required this.remaining,
    required this.statusText,
    required this.onEnd,
    required this.onRecenter,
  });

  final RoutePlan plan;
  final int currentManeuverIndex;
  final double remainingMeters;
  final Duration remaining;
  final String? statusText; // e.g. "Recalculating…", "You have arrived"
  final VoidCallback onEnd;
  final VoidCallback onRecenter;

  Maneuver? get _current =>
      (currentManeuverIndex >= 0 && currentManeuverIndex < plan.maneuvers.length)
          ? plan.maneuvers[currentManeuverIndex]
          : null;
  Maneuver? get _next =>
      (currentManeuverIndex + 1 < plan.maneuvers.length)
          ? plan.maneuvers[currentManeuverIndex + 1]
          : null;

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    return Stack(
      children: [
        // Top maneuver banner.
        Positioned(
          left: 8, right: 8, top: 8,
          child: Material(
            key: const Key('maneuverBanner'),
            color: const Color(0xFF1B2540),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(_iconFor(cur?.type), color: Colors.white, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cur?.instruction ?? statusText ?? 'Proceed',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      if (_next != null)
                        Text('then ${_next!.instruction}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                Text(formatDistance(cur?.distanceMeters ?? 0),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        // Bottom status bar.
        Positioned(
          left: 8, right: 8, bottom: 8,
          child: Material(
            key: const Key('navStatusBar'),
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Text('${formatDuration(remaining)} · ${formatDistance(remainingMeters)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  key: const Key('navRecenter'),
                  icon: const Icon(Icons.my_location),
                  onPressed: onRecenter,
                ),
                FilledButton(
                  key: const Key('navEnd'),
                  onPressed: onEnd,
                  child: const Text('End'),
                ),
              ]),
            ),
          ),
        ),
        if (statusText != null && _current != null)
          Positioned(
            left: 8, right: 8, top: 92,
            child: Material(
              key: const Key('navStatusFlash'),
              color: const Color(0xFFFDF1DC),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(statusText!),
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconFor(ManeuverType? t) => switch (t) {
        ManeuverType.start => Icons.navigation,
        ManeuverType.destination => Icons.flag,
        ManeuverType.left || ManeuverType.slightLeft || ManeuverType.sharpLeft =>
          Icons.turn_left,
        ManeuverType.right || ManeuverType.slightRight || ManeuverType.sharpRight =>
          Icons.turn_right,
        ManeuverType.roundabout => Icons.roundabout_left,
        _ => Icons.straight,
      };
}
```

- [ ] **Step 2: Write the widget test**

Create `test/nav/navigation_overlay_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/nav/navigation_overlay.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';

RoutePlan _plan() => const RoutePlan(
      geometry: [LatLng(0, 0), LatLng(0, 1)],
      legs: [],
      distanceMeters: 1000,
      duration: Duration(minutes: 5),
    );

const _maneuvers = [
  Maneuver(instruction: 'Turn left', distanceMeters: 200, duration: Duration(seconds: 60),
      location: LatLng(0, 0), type: ManeuverType.left),
  Maneuver(instruction: 'Turn right', distanceMeters: 500, duration: Duration(seconds: 90),
      location: LatLng(0, 0.5), type: ManeuverType.right),
];

void main() {
  testWidgets('shows current instruction, the "then" line, End and status',
      (tester) async {
    final plan = RoutePlan(
        geometry: _plan().geometry, legs: const [],
        distanceMeters: 1000, duration: const Duration(minutes: 5));
    // Inject maneuvers via a leg so plan.maneuvers is non-empty.
    final p = RoutePlan(
      geometry: plan.geometry,
      legs: const [RouteLeg(distanceMeters: 1000, duration: Duration(minutes: 5),
          maneuvers: _maneuvers)],
      distanceMeters: 1000, duration: const Duration(minutes: 5));
    var ended = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NavigationOverlay(
          plan: p, currentManeuverIndex: 0,
          remainingMeters: 800, remaining: const Duration(minutes: 4),
          statusText: null,
          onEnd: () => ended = true, onRecenter: () {},
        ),
      ),
    ));
    expect(find.text('Turn left'), findsOneWidget);
    expect(find.text('then Turn right'), findsOneWidget);
    expect(find.byKey(const Key('maneuverBanner')), findsOneWidget);
    expect(find.byKey(const Key('navStatusBar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('navEnd')));
    expect(ended, isTrue);
  });
}
```

- [ ] **Step 3: Run the test + analyze**

Run: `flutter test test/nav/navigation_overlay_test.dart` → PASS. Then `flutter analyze` clean.

- [ ] **Step 4: Commit**

```bash
git add lib/nav/navigation_overlay.dart test/nav/navigation_overlay_test.dart
git commit -m "feat: add NavigationOverlay drive-mode UI (banner + status + End, tested)"
```

---

## Task 6: Add a "Start" button to the trip planner

**Files:**
- Modify: `lib/trip/trip_planner_panel.dart`
- Modify: `test/trip/trip_planner_panel_test.dart`

- [ ] **Step 1: Add the onStart callback + button**

In `lib/trip/trip_planner_panel.dart`, add a required `final VoidCallback onStart;` to the constructor (and the widget fields). The panel already tracks the computed `_plan`/`_loading`/`_error` state. After the maneuver list section (when `_plan != null`), add a Start button:
```dart
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('startNavButton'),
                    onPressed: widget.onStart,
                    icon: const Icon(Icons.navigation),
                    label: const Text('Start'),
                  ),
                ),
```
(Place it inside the `else if (_plan != null) ...[ ... ]` block, after the maneuver `ListView`.)

- [ ] **Step 2: Update the existing widget test to pass onStart + assert the button**

In `test/trip/trip_planner_panel_test.dart`, every `TripPlannerPanel(...)` construction now needs `onStart: () {}`. Add it to each. Then add a test:
```dart
  testWidgets('shows Start button once a route is computed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TripPlannerPanel(
          service: FakeRoutingService(),
          trip: _routable(),
          onModeChanged: (_) {}, onRemoveStop: (_) {},
          onClear: () {}, onPlanChanged: (_) {}, onStart: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('startNavButton')), findsOneWidget);
  });
```

- [ ] **Step 3: Run tests + analyze**

Run: `flutter test test/trip/trip_planner_panel_test.dart` → PASS (existing + new). Then whole-project `flutter analyze` (clean) + `flutter test` (all pass). NOTE: `map_screen.dart` constructs `TripPlannerPanel` and will now fail to compile until Task 7 passes `onStart` — so for THIS task, also add a temporary `onStart: () {}` to the `TripPlannerPanel(...)` call in `map_screen.dart` (Task 7 replaces it with the real handler). This keeps the project compiling + green.

- [ ] **Step 4: Commit**

```bash
git add lib/trip/trip_planner_panel.dart test/trip/trip_planner_panel_test.dart lib/map/map_screen.dart
git commit -m "feat: add Start button to the trip planner (enters navigation)"
```

---

## Task 7: Wire drive mode into MapScreen (state, camera, nav loop, FAB hide)

**Files:**
- Modify: `lib/map/map_screen.dart`
- Modify: `test/map/map_screen_test.dart`

- [ ] **Step 1: Add nav fields + heading provider**

In `lib/map/map_screen.dart` add imports for `nav/nav_state.dart`, `nav/heading_provider.dart`, `nav/trip_progress.dart`, `nav/navigation_overlay.dart`, `routing/live_progress.dart`. Add fields:
```dart
  final _nav = NavController();
  HeadingProvider? _heading;
  double _bearing = 0;
  String? _navStatus;     // "Recalculating…" / "You have arrived" / off-route msg
  bool _rerouting = false;
  int _offRouteHits = 0;
```
In `initState`, `_nav.addListener(() { if (mounted) setState(() {}); });`. In `dispose`, `_nav.dispose(); _heading?.dispose();`.

- [ ] **Step 2: Replace the `_planning` bool with the NavController**

The screen currently uses `bool _planning`. Replace its uses: `_startTrip()` sets `_nav.planning()` (instead of `_planning=true`); the `if (_planning) TripPlannerPanel(...)` becomes `if (_nav.state == NavState.planning) TripPlannerPanel(...)`; the long-press guard `if (_planning)` becomes `if (_nav.state == NavState.planning)`; `onClear` calls `_nav.clear()` (and clears `_plan`/route source). Remove the `bool _planning` field. Keep `_plan`/`_onPlanChanged` as-is (they draw the route line).

- [ ] **Step 3: Implement Start → navigating + the drive loop**

Add the Start handler and pass it to the panel (`onStart: _startNavigation`):
```dart
  void _startNavigation() {
    final plan = _plan;
    if (plan == null) return;
    _nav.startNavigation(plan);
    _heading?.dispose();
    _heading = HeadingProvider()..start();
    _heading!.headings.listen((h) {
      _bearing = h;
      _driveCamera();
    });
    // Hide the right-side FABs; show the overlay (build() reacts to nav.state).
    setState(() {});
  }

  void _driveCamera() {
    final loc = _lastLoc;
    final controller = _controller;
    if (loc == null || controller == null || _nav.state != NavState.navigating) {
      return;
    }
    controller.animateCamera(
      center: Geographic(lon: loc.lng, lat: loc.lat),
      zoom: 17,
      pitch: 60,
      bearing: _bearing,
      nativeDuration: const Duration(milliseconds: 700),
    );
  }
```
Extend `_onLocation` (the existing GPS handler): after it updates `_lastLoc`/pointer, when navigating, feed the nav loop. Add at the end of `_onLocation`:
```dart
    if (_nav.state == NavState.navigating) {
      _heading?.onPosition(_lastRawPosition!); // see note
      _onNavTick(LatLng(loc.lng == loc.lng ? loc.lat : loc.lat, loc.lng));
    }
```
NOTE on the raw Position: `_onLocation` receives a smoothed `UserLocation`, but `HeadingProvider.onPosition` needs a geolocator `Position` (for `.heading`/`.speed`). Simplest: store the latest raw `Position` from `LocationService`. Since `LocationService` currently emits `UserLocation` (which already has `headingDeg` + `speedMps`), instead add an overload: give `HeadingProvider` a method `onUserLocation(double courseDeg, double speedMps)` and call `_heading?.onUserLocation(loc.headingDeg, loc.speedMps)`. UPDATE the HeadingProvider (Task 3) is already pure via `fuseHeading`; add this thin method to it:
```dart
  // add to HeadingProvider:
  void onUserLocation(double courseDeg, double speedMps) {
    _last = fuseHeading(
      gpsCourseDeg: courseDeg, speedMps: speedMps,
      compassDeg: _lastCompass, lastDeg: _last);
    _controller.add(_last);
  }
```
(Then in `_onLocation` use `_heading?.onUserLocation(loc.headingDeg, loc.speedMps);` and drop the raw-Position note.)

Add the nav tick:
```dart
  void _onNavTick(LatLng pos) {
    final plan = _nav.activePlan;
    if (plan == null) return;
    _nav.advanceTo(pos);
    // Arrival.
    if (hasArrived(pos, plan)) {
      setState(() => _navStatus = 'You have arrived');
      return;
    }
    // Off-route → debounced auto re-route.
    if (isOffRoute(pos, plan.geometry, thresholdMeters: 40)) {
      _offRouteHits++;
      if (_offRouteHits >= 3 && !_rerouting) _reroute(pos);
    } else {
      _offRouteHits = 0;
      if (_navStatus != 'You have arrived') {
        setState(() => _navStatus = null);
      }
    }
    setState(() {}); // refresh remaining distance/ETA in the overlay
  }

  Future<void> _reroute(LatLng from) async {
    final plan = _nav.activePlan;
    if (plan == null) return;
    _rerouting = true;
    setState(() => _navStatus = 'Recalculating…');
    try {
      final dest = plan.geometry.last;
      final newPlan = await _routing.route(
          [from, LatLng(dest.lat, dest.lng)], _trip.mode);
      _nav.replacePlan(newPlan);
      _plan = newPlan;
      _offRouteHits = 0;
      if (_routeReady) {
        _style?.updateGeoJsonSource(
            id: RouteLayer.sourceId, data: RouteLayer.lineJson(newPlan.geometry));
      }
      setState(() => _navStatus = null);
    } on RoutingException catch (e) {
      setState(() => _navStatus = 'Off route — ${e.message}');
    } finally {
      _rerouting = false;
    }
  }
```

- [ ] **Step 4: Build the nav overlay + hide FABs when navigating**

In `build()`, wrap the right-side FAB `Positioned` so it only shows when NOT navigating: `if (_nav.state != NavState.navigating) Positioned( ...the FAB column... )`. Then add the overlay:
```dart
          if (_nav.state == NavState.navigating && _nav.activePlan != null)
            Positioned.fill(
              child: NavigationOverlay(
                plan: _nav.activePlan!,
                currentManeuverIndex: _nav.currentManeuverIndex,
                remainingMeters: _lastLoc == null
                    ? _nav.activePlan!.distanceMeters
                    : remainingDistanceMeters(
                        LatLng(_lastLoc!.lat, _lastLoc!.lng), _nav.activePlan!),
                remaining: _lastLoc == null
                    ? _nav.activePlan!.duration
                    : remainingDuration(
                        LatLng(_lastLoc!.lat, _lastLoc!.lng), _nav.activePlan!),
                statusText: _navStatus,
                onRecenter: _driveCamera,
                onEnd: () {
                  _heading?.dispose();
                  _heading = null;
                  setState(() {
                    _navStatus = null;
                    _offRouteHits = 0;
                  });
                  _nav.exit();
                  // Relax the camera back to a normal top-down follow.
                  _controller?.animateCamera(pitch: 0, zoom: 15, bearing: 0);
                },
              ),
            ),
```

- [ ] **Step 5: Keep the existing map_screen widget test green + add a nav-state test**

The existing `MapScreen(autoStart:false)` tests don't enter nav, so they pass. Add a small test that the trip panel's Start path exists is covered by Task 6. For map_screen, just ensure the suite stays green. (Driving visuals are device-only.)

- [ ] **Step 6: Whole-project analyze + test**

Run: `flutter analyze` → clean; `flutter test` → all pass. Fix anything red (watch: the `_planning`→`_nav.state` replacement is complete; `Geographic` camera params; `LatLng` is the domain type; `_routing` is the no-fallback Valhalla service from Task 1).

- [ ] **Step 7: Commit**

```bash
git add lib/map/map_screen.dart lib/nav/heading_provider.dart test/map/map_screen_test.dart
git commit -m "feat: wire drive mode into the map (Start/End, heading-up camera, nav loop, FAB hide)"
```

---

## Task 8: Verify + README + push

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full verification**

Run: `flutter analyze` (clean) + `flutter test` (record the real `+N` line). If red, fix before continuing.

- [ ] **Step 2: README**

Add a "Turn-by-turn drive mode (Milestone 4)" section: the asset-path + no-silent-fallback fixes; the Start→drive-mode flow (heading-up camera, compass when stopped, maneuver banner, auto re-route, End); the new `flutter_compass` dep. Manual acceptance steps: rebuild → confirm a Ghatshila route **follows roads**; **Start** → map enters drive mode and **rotates with your heading** (walk a few metres; stop and rotate the phone to confirm the compass reorients the map); the banner advances; go off-route and confirm "Recalculating…"; **End** exits. Update the verification-status table (new test count; "Drive-mode logic + UI" PASS via unit/widget tests; "On-device drive experience" NOT YET VERIFIED).

- [ ] **Step 3: Commit + push**

```bash
git add README.md
git commit -m "docs: document turn-by-turn drive mode + routing fixes"
git push origin main
```
(Remote `origin` = `git@github-tb-vms:Drake0306/offline-navigator.git`. Confirm with `git remote -v` before pushing.)

---

## Self-review (completed at plan-writing time)

**Spec coverage:** asset path (already committed) + no silent fallback + clearer errors → Task 1; NavState machine → Task 2; HeadingProvider GPS+compass fusion → Task 3; remaining ETA/distance + arrival → Task 4; maneuver banner + status + End UI → Task 5; Start button → Task 6; drive-mode camera (zoom/pitch/bearing) + nav loop + off-route auto-reroute + FAB hide + overlay → Task 7; verify + README + push → Task 8. ✓ Reuses `nearestManeuverIndex`/`isOffRoute` (live_progress), `RoutePlan`/`Maneuver`, `formatDistance/Duration`. ✓

**Placeholder scan:** No TBD/TODO. Task 7 Step 3 contains a "NOTE" that resolves an interface mismatch (raw Position vs UserLocation) by adding a concrete `onUserLocation(courseDeg, speedMps)` method to HeadingProvider and using `loc.headingDeg`/`loc.speedMps` — a concrete instruction with the exact code, not a blank. (Implementers should add that method when doing Task 3 OR Task 7; it's shown in full.)

**Type consistency:** `NavController.{state, activePlan, currentManeuverIndex, planning, startNavigation, advanceTo, replacePlan, exit, clear}` consistent Tasks 2,7. `fuseHeading({gpsCourseDeg, speedMps, compassDeg, lastDeg})` + `HeadingProvider.{headings, start, onUserLocation, dispose}` consistent Tasks 3,7. `remainingDistanceMeters/remainingDuration/hasArrived(LatLng, RoutePlan)` consistent Tasks 4,7. `NavigationOverlay({plan, currentManeuverIndex, remainingMeters, remaining, statusText, onEnd, onRecenter})` consistent Tasks 5,7. `TripPlannerPanel(..., onStart)` consistent Tasks 6,7. `LatLng` (domain), `Geographic(lon,lat)` (maplibre camera) used in the right places.

**Device-only:** the live camera rotation, compass reorientation, and the real road-following route are verified by the user on Android (Task 8). All logic + widgets are `flutter test`-green here.
