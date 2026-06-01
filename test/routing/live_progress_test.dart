import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/live_progress.dart';

void main() {
  // A straight east-west route along the equator-ish for easy reasoning.
  const route = [
    LatLng(22.000, 86.000),
    LatLng(22.000, 86.010),
    LatLng(22.000, 86.020),
  ];

  test('distanceToRoute is ~0 for a point on the line, large when far', () {
    expect(distanceToRouteMeters(const LatLng(22.000, 86.005), route),
        lessThan(20));
    expect(distanceToRouteMeters(const LatLng(22.050, 86.005), route),
        greaterThan(1000));
  });

  test('isOffRoute respects the threshold', () {
    expect(isOffRoute(const LatLng(22.000, 86.005), route, thresholdMeters: 30),
        isFalse);
    expect(isOffRoute(const LatLng(22.050, 86.005), route, thresholdMeters: 30),
        isTrue);
  });

  test('nearestManeuverIndex picks the upcoming maneuver by position', () {
    final maneuverLocs = [
      const LatLng(22.000, 86.000),
      const LatLng(22.000, 86.010),
      const LatLng(22.000, 86.020),
    ];
    // Standing near the 2nd maneuver location.
    expect(nearestManeuverIndex(const LatLng(22.000, 86.0102), maneuverLocs), 1);
  });
}
