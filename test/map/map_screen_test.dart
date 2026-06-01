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

  testWidgets('permission banner Grant button present when denied', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    final dynamic state = tester.state(find.byType(MapScreen));
    // ignore: invalid_use_of_visible_for_testing_member
    state.showPermissionIssueForTest(LocationPermissionState.deniedForever);
    await tester.pump();
    expect(find.byKey(const Key('permActionButton')), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('search button is present', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    expect(find.byKey(const Key('searchButton')), findsOneWidget);
  });

  testWidgets('layers button opens the style sheet', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    expect(find.byKey(const Key('layersButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('layersButton')));
    await tester.pump(); // start sheet animation
    await tester.pump(const Duration(milliseconds: 500)); // let it complete

    // Sheet shows all four styles + Auto.
    expect(find.byKey(const Key('style-standard')), findsOneWidget);
    expect(find.byKey(const Key('style-dark')), findsOneWidget);
    expect(find.byKey(const Key('style-roads')), findsOneWidget);
    expect(find.byKey(const Key('style-auto')), findsOneWidget);
  });
}
