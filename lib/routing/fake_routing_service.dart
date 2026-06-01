import 'dart:math' as math;
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';
import 'package:offline_navigator/routing/routing_service.dart';
import 'package:offline_navigator/routing/travel_mode.dart';

/// A deterministic stand-in for the native engine: returns a straight-line
/// route through the requested points with synthetic distance/ETA/maneuvers.
/// Used by all tests and by the app until the native Valhalla engine lands.
class FakeRoutingService implements RoutingService {
  FakeRoutingService({this.failWith});

  /// If set, [route] throws a RoutingException with this message.
  final String? failWith;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<RoutePlan> route(List<LatLng> points, TravelMode mode) async {
    if (failWith != null) throw RoutingException(failWith!);
    if (points.length < 2) {
      throw const RoutingException('Need at least a start and a destination');
    }
    final legs = <RouteLeg>[];
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final dist = _haversine(a, b);
      total += dist;
      final speed = _speedMps(mode);
      legs.add(RouteLeg(
        distanceMeters: dist,
        duration: Duration(seconds: (dist / speed).round()),
        maneuvers: [
          Maneuver(
            instruction: i == 0 ? 'Head toward destination' : 'Continue to stop ${i + 1}',
            distanceMeters: dist,
            duration: Duration(seconds: (dist / speed).round()),
            location: a,
            type: i == 0 ? ManeuverType.start : ManeuverType.continueStraight,
          ),
          if (i == points.length - 2)
            Maneuver(
              instruction: 'You have arrived',
              distanceMeters: 0,
              duration: Duration.zero,
              location: b,
              type: ManeuverType.destination,
            ),
        ],
      ));
    }
    final speed = _speedMps(mode);
    return RoutePlan(
      geometry: List<LatLng>.from(points),
      legs: legs,
      distanceMeters: total,
      duration: Duration(seconds: (total / speed).round()),
    );
  }

  double _speedMps(TravelMode mode) => switch (mode) {
        TravelMode.car => 13.9, // ~50 km/h
        TravelMode.motorbike => 11.1, // ~40 km/h
        TravelMode.bike => 4.2, // ~15 km/h
        TravelMode.walk => 1.4, // ~5 km/h
      };

  double _haversine(LatLng a, LatLng b) {
    const earth = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(b.lat - a.lat), dLon = rad(b.lng - a.lng);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(a.lat)) * math.cos(rad(b.lat)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}
