import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/map/map_screen.dart';

void main() {
  testWidgets('MapScreen shows tilt and recenter controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    expect(find.byKey(const Key('tiltButton')), findsOneWidget);
    expect(find.byKey(const Key('recenterButton')), findsOneWidget);
  });
}
