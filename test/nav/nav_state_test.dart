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
