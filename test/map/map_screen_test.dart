import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/location/location_service.dart';
import 'package:offline_navigator/map/map_screen.dart';

void main() {
  testWidgets('MapScreen shows tilt and recenter controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    expect(find.byKey(const Key('tiltButton')), findsOneWidget);
    expect(find.byKey(const Key('recenterButton')), findsOneWidget);
  });

  testWidgets('shows permission banner action when issue set', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MapScreen(autoStart: false)),
    );
    await tester.pump();

    // Obtain the state and call the @visibleForTesting helper to set the issue.
    final state = tester.state(find.byType(MapScreen));
    // ignore: invalid_use_of_visible_for_testing_member
    (state as dynamic).showPermissionIssueForTest(LocationPermissionState.denied);
    await tester.pump();

    expect(find.byKey(const Key('permActionButton')), findsOneWidget);
    expect(
      find.text('Location permission needed to show your position.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a retry button when the map fails to load',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MapScreen(autoStart: false)),
    );
    await tester.pump();

    final state = tester.state(find.byType(MapScreen));
    // ignore: invalid_use_of_visible_for_testing_member
    (state as dynamic).showBootErrorForTest('Could not load the offline map.');
    await tester.pump();

    expect(find.byKey(const Key('retryBootButton')), findsOneWidget);
    expect(find.text('Could not load the offline map.'), findsOneWidget);
  });
}
