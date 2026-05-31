/// Immutable snapshot of the user's location and heading.
class UserLocation {
  const UserLocation({
    required this.lat,
    required this.lng,
    required this.headingDeg,
    required this.speedMps,
    required this.accuracyM,
    required this.timestamp,
  });

  final double lat;
  final double lng;
  final double headingDeg; // 0..360, 0 = north
  final double speedMps;
  final double accuracyM;
  final DateTime timestamp;

  /// Exponential-moving-average step toward [next] by factor [t] (0..1).
  /// Heading is interpolated along the shortest angular path.
  UserLocation smoothedTowards(UserLocation next, double t) {
    return UserLocation(
      lat: lat + (next.lat - lat) * t,
      lng: lng + (next.lng - lng) * t,
      headingDeg: _lerpAngle(headingDeg, next.headingDeg, t),
      speedMps: speedMps + (next.speedMps - speedMps) * t,
      accuracyM: next.accuracyM,
      timestamp: next.timestamp,
    );
  }

  static double _lerpAngle(double a, double b, double t) {
    final diff = ((b - a + 540) % 360) - 180; // shortest signed delta
    final result = (a + diff * t) % 360;
    return result < 0 ? result + 360 : result;
  }

  // `const` cannot reference `_epoch` (a non-const static field), so `unknown`
  // is `static final` rather than `static const`.
  static final UserLocation unknown = UserLocation(
    lat: 0,
    lng: 0,
    headingDeg: 0,
    speedMps: 0,
    accuracyM: double.infinity,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  );

}
