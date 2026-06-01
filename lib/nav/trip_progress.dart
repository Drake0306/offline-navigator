import 'dart:math' as math;
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';

/// Remaining distance (metres) along [plan.geometry] from the point on the route
/// nearest [p] to the end. Sums segment lengths after the nearest projection.
double remainingDistanceMeters(LatLng p, RoutePlan plan) {
  final g = plan.geometry;
  if (g.length < 2) return 0;
  // Find the nearest segment and the fraction along it.
  var bestSeg = 0;
  var bestT = 0.0;
  var bestDist = double.infinity;
  for (var i = 0; i < g.length - 1; i++) {
    final (d, t) = _projic(p, g[i], g[i + 1]);
    if (d < bestDist) {
      bestDist = d;
      bestSeg = i;
      bestT = t;
    }
  }
  // Remaining = rest of the current segment + all following segments.
  var rem = _hav(_lerp(g[bestSeg], g[bestSeg + 1], bestT), g[bestSeg + 1]);
  for (var i = bestSeg + 1; i < g.length - 1; i++) {
    rem += _hav(g[i], g[i + 1]);
  }
  return rem;
}

/// Remaining duration, scaled from total by the remaining/total distance ratio.
Duration remainingDuration(LatLng p, RoutePlan plan) {
  if (plan.distanceMeters <= 0) return Duration.zero;
  final frac = (remainingDistanceMeters(p, plan) / plan.distanceMeters).clamp(0.0, 1.0);
  return Duration(seconds: (plan.duration.inSeconds * frac).round());
}

/// True when [p] is within [thresholdMeters] of the route's last point.
bool hasArrived(LatLng p, RoutePlan plan, {double thresholdMeters = 30}) {
  if (plan.geometry.isEmpty) return false;
  return _hav(p, plan.geometry.last) <= thresholdMeters;
}

// --- geometry (equirectangular projection at small scales) ---
(double, double) _projic(LatLng p, LatLng a, LatLng b) {
  const earth = 6371000.0;
  final latRef = _rad(p.lat);
  double x(LatLng q) => _rad(q.lng) * math.cos(latRef) * earth;
  double y(LatLng q) => _rad(q.lat) * earth;
  final px = x(p), py = y(p), ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return (math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay)), 0);
  var t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return (math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)), t);
}

LatLng _lerp(LatLng a, LatLng b, double t) =>
    LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);

double _hav(LatLng a, LatLng b) {
  const earth = 6371000.0;
  final dLat = _rad(b.lat - a.lat), dLon = _rad(b.lng - a.lng);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  return earth * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _rad(double d) => d * math.pi / 180.0;
