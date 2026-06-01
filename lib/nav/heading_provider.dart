import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Speed (m/s) above which GPS course is trusted over the compass.
const double kMovingSpeedMps = 2.0;

/// Pure heading fusion: while moving with a valid GPS course, use it; otherwise
/// use the compass; if neither is available, hold [lastDeg]. Result normalized
/// to [0, 360).
double fuseHeading({
  required double gpsCourseDeg,
  required double speedMps,
  required double? compassDeg,
  required double lastDeg,
}) {
  double pick;
  final gpsValid = gpsCourseDeg >= 0; // geolocator uses negative for "unknown"
  if (speedMps >= kMovingSpeedMps && gpsValid) {
    // Moving fast with a valid GPS course — trust the GPS.
    pick = gpsCourseDeg;
  } else if (compassDeg != null) {
    // Slow/stopped (or GPS invalid) but compass available — use compass.
    pick = compassDeg;
  } else {
    // No compass and either slow/stopped or GPS invalid — hold the last heading.
    pick = lastDeg;
  }
  final n = pick % 360;
  return n < 0 ? n + 360 : n;
}

/// Streams a fused heading by combining geolocator positions (GPS course + speed)
/// with the magnetometer (flutter_compass). Holds the last good heading when
/// stationary and no compass is available.
class HeadingProvider {
  HeadingProvider({Stream<CompassEvent?>? compass})
      : _compass = compass ?? FlutterCompass.events;

  final Stream<CompassEvent?>? _compass;
  final _controller = StreamController<double>.broadcast();
  StreamSubscription<CompassEvent?>? _compassSub;
  double _last = 0;
  double? _lastCompass;

  Stream<double> get headings => _controller.stream;

  void start() {
    _compassSub = _compass?.listen((e) => _lastCompass = e?.heading);
  }

  /// Feed a position update; emits a fused heading.
  void onPosition(Position p) {
    _last = fuseHeading(
      gpsCourseDeg: p.heading,
      speedMps: p.speed,
      compassDeg: _lastCompass,
      lastDeg: _last,
    );
    _controller.add(_last);
  }

  /// Feed a heading + speed from an already-smoothed UserLocation (the app's
  /// LocationService emits UserLocation, not a raw geolocator Position).
  void onUserLocation(double courseDeg, double speedMps) {
    _last = fuseHeading(
        gpsCourseDeg: courseDeg, speedMps: speedMps,
        compassDeg: _lastCompass, lastDeg: _last);
    _controller.add(_last);
  }

  Future<void> dispose() async {
    await _compassSub?.cancel();
    await _controller.close();
  }
}
