import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_navigator/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OfflineNavigatorApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
