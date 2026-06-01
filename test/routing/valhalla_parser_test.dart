import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/valhalla_parser.dart';
import 'package:offline_navigator/routing/route_plan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a Valhalla trip into a RoutePlan', () async {
    final jsonStr = await rootBundle.loadString('assets/routing/sample_route.json');
    final plan = parseValhallaRoute(jsonDecode(jsonStr) as Map<String, Object?>);

    // Totals: length 2.0 km → 2000 m; time 300 s → 5 min.
    expect(plan.distanceMeters, closeTo(2000, 0.001));
    expect(plan.duration.inSeconds, 300);
    expect(plan.legs.length, 2);
    expect(plan.geometry, isNotEmpty);

    // Maneuvers flattened across legs (2 + 2).
    expect(plan.maneuvers.length, 4);
    expect(plan.maneuvers.first.instruction, 'Head north.');
    expect(plan.maneuvers.first.type, ManeuverType.start);
    expect(plan.maneuvers[1].type, ManeuverType.left);
    expect(plan.maneuvers.last.type, ManeuverType.destination);
    // Leg length 1.2 km → 1200 m.
    expect(plan.legs.first.distanceMeters, closeTo(1200, 0.001));
  });
}
