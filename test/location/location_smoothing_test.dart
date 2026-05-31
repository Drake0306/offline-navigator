import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/location/user_location.dart';

void main() {
  test('EMA smoothing pulls toward the new point but not all the way', () {
    final a = UserLocation(lat: 22.50, lng: 86.40, headingDeg: 0, speedMps: 0, accuracyM: 5, timestamp: DateTime(2026));
    final b = UserLocation(lat: 22.60, lng: 86.50, headingDeg: 90, speedMps: 3, accuracyM: 5, timestamp: DateTime(2026));
    final s = a.smoothedTowards(b, 0.5);
    expect(s.lat, closeTo(22.55, 1e-9));
    expect(s.lng, closeTo(86.45, 1e-9));
  });

  test('heading interpolation wraps across 360/0 correctly', () {
    final a = UserLocation(lat: 0, lng: 0, headingDeg: 350, speedMps: 0, accuracyM: 5, timestamp: DateTime(2026));
    final b = UserLocation(lat: 0, lng: 0, headingDeg: 10, speedMps: 0, accuracyM: 5, timestamp: DateTime(2026));
    final s = a.smoothedTowards(b, 0.5);
    // Halfway from 350 to 10 (going forward through 0) is 0, not 180.
    expect(s.headingDeg, closeTo(0, 1e-6));
  });
}
