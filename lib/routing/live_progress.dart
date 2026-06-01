import 'dart:math' as math;
import 'package:offline_navigator/routing/lat_lng.dart';

/// Minimum distance (metres) from [p] to the polyline [route] (segment-wise).
double distanceToRouteMeters(LatLng p, List<LatLng> route) {
  if (route.isEmpty) return double.infinity;
  if (route.length == 1) return _haversine(p, route.first);
  var best = double.infinity;
  for (var i = 0; i < route.length - 1; i++) {
    final d = _pointToSegmentMeters(p, route[i], route[i + 1]);
    if (d < best) best = d;
  }
  return best;
}

/// True when [p] is farther than [thresholdMeters] from the route.
bool isOffRoute(LatLng p, List<LatLng> route, {double thresholdMeters = 40}) =>
    distanceToRouteMeters(p, route) > thresholdMeters;

/// Index of the maneuver location nearest to [p].
int nearestManeuverIndex(LatLng p, List<LatLng> maneuverLocations) {
  var best = double.infinity;
  var idx = 0;
  for (var i = 0; i < maneuverLocations.length; i++) {
    final d = _haversine(p, maneuverLocations[i]);
    if (d < best) {
      best = d;
      idx = i;
    }
  }
  return idx;
}

// --- geometry helpers (equirectangular projection around the point: fine at
// the small distances involved in navigation) ---

double _haversine(LatLng a, LatLng b) {
  const earth = 6371000.0;
  final dLat = _rad(b.lat - a.lat), dLon = _rad(b.lng - a.lng);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  return earth * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
  // Project to local metres using an equirectangular approximation centred at p.
  const earth = 6371000.0;
  final latRef = _rad(p.lat);
  double x(LatLng q) => _rad(q.lng) * math.cos(latRef) * earth;
  double y(LatLng q) => _rad(q.lat) * earth;
  final px = x(p), py = y(p);
  final ax = x(a), ay = y(a);
  final bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  var t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

double _rad(double d) => d * math.pi / 180.0;
