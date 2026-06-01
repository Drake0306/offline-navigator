import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/fake_routing_service.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/trip_state.dart';
import 'package:offline_navigator/trip/trip_planner_panel.dart';

TripState _routable() => const TripState(
      start: TripPoint(LatLng(22.58, 86.47), 'Start'),
      destination: TripPoint(LatLng(22.62, 86.51), 'Dest'),
      mode: TravelMode.car,
    );

void main() {
  testWidgets('computes and shows summary + maneuvers for a routable trip',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TripPlannerPanel(
          service: FakeRoutingService(),
          trip: _routable(),
          onModeChanged: (_) {},
          onRemoveStop: (_) {},
          onClear: () {},
          onPlanChanged: (_) {},
          onStart: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tripSummary')), findsOneWidget);
    expect(find.byKey(const Key('maneuver-0')), findsWidgets);
  });

  testWidgets('shows error state when the service fails', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TripPlannerPanel(
          service: FakeRoutingService(failWith: 'no tiles'),
          trip: _routable(),
          onModeChanged: (_) {},
          onRemoveStop: (_) {},
          onClear: () {},
          onPlanChanged: (_) {},
          onStart: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tripError')), findsOneWidget);
  });

  testWidgets('mode chips present', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TripPlannerPanel(
          service: FakeRoutingService(),
          trip: _routable(),
          onModeChanged: (_) {},
          onRemoveStop: (_) {},
          onClear: () {},
          onPlanChanged: (_) {},
          onStart: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('mode-car')), findsOneWidget);
    expect(find.byKey(const Key('mode-walk')), findsOneWidget);
  });

  testWidgets('shows Start button once a route is computed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TripPlannerPanel(
          service: FakeRoutingService(),
          trip: _routable(),
          onModeChanged: (_) {},
          onRemoveStop: (_) {},
          onClear: () {},
          onPlanChanged: (_) {},
          onStart: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('startNavButton')), findsOneWidget);
  });
}
