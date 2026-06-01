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
