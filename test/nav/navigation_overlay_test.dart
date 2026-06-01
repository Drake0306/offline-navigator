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
