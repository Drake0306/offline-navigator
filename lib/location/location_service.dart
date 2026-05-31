import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:offline_navigator/location/user_location.dart';

enum LocationPermissionState { granted, denied, deniedForever, serviceOff }

/// Streams smoothed user locations and manages permission.
class LocationService {
  StreamSubscription<Position>? _sub;
  final _controller = StreamController<UserLocation>.broadcast();
  UserLocation? _last;

  Stream<UserLocation> get positions => _controller.stream;

  Future<LocationPermissionState> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceOff;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }

  Future<void> start() async {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition);
  }

  void _onPosition(Position p) {
    final incoming = UserLocation(
      lat: p.latitude,
      lng: p.longitude,
      // Use GPS course when moving; keep last heading if speed is ~0.
      headingDeg: p.speed > 0.5 ? p.heading : (_last?.headingDeg ?? p.heading),
      speedMps: p.speed,
      accuracyM: p.accuracy,
      timestamp: p.timestamp,
    );
    final smoothed =
        _last == null ? incoming : _last!.smoothedTowards(incoming, 0.35);
    _last = smoothed;
    _controller.add(smoothed);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
