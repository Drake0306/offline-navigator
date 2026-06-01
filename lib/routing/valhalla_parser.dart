import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/polyline.dart';
import 'package:offline_navigator/routing/route_plan.dart';

/// Parses a Valhalla `/route` response (already JSON-decoded) into a RoutePlan.
/// Lengths are kilometres and times seconds in the Valhalla response.
RoutePlan parseValhallaRoute(Map<String, Object?> json) {
  final trip = json['trip'] as Map<String, Object?>?;
  if (trip == null) {
    throw const FormatException('Valhalla response has no trip');
  }
  final legsJson = (trip['legs'] as List<Object?>? ?? const []);
  final geometry = <LatLng>[];
  final legs = <RouteLeg>[];
  for (final legObj in legsJson) {
    final leg = legObj as Map<String, Object?>;
    final shape = leg['shape'] as String? ?? '';
    geometry.addAll(decodePolyline6(shape));
    final summary = leg['summary'] as Map<String, Object?>? ?? const {};
    final maneuvers = <Maneuver>[];
    final shapePts = decodePolyline6(shape);
    for (final mObj in (leg['maneuvers'] as List<Object?>? ?? const [])) {
      final m = mObj as Map<String, Object?>;
      final beginIdx = (m['begin_shape_index'] as num?)?.toInt() ?? 0;
      final loc = shapePts.isEmpty
          ? const LatLng(0, 0)
          : shapePts[beginIdx.clamp(0, shapePts.length - 1)];
      maneuvers.add(Maneuver(
        instruction: m['instruction'] as String? ?? '',
        distanceMeters: ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
        duration: Duration(seconds: ((m['time'] as num?)?.toDouble() ?? 0).round()),
        location: loc,
        type: _mapType((m['type'] as num?)?.toInt() ?? -1),
      ));
    }
    legs.add(RouteLeg(
      distanceMeters: ((summary['length'] as num?)?.toDouble() ?? 0) * 1000,
      duration: Duration(seconds: ((summary['time'] as num?)?.toDouble() ?? 0).round()),
      maneuvers: maneuvers,
    ));
  }
  final tripSummary = trip['summary'] as Map<String, Object?>? ?? const {};
  return RoutePlan(
    geometry: geometry,
    legs: legs,
    distanceMeters: ((tripSummary['length'] as num?)?.toDouble() ?? 0) * 1000,
    duration: Duration(seconds: ((tripSummary['time'] as num?)?.toDouble() ?? 0).round()),
  );
}

ManeuverType _mapType(int code) => switch (code) {
      1 => ManeuverType.start,
      4 => ManeuverType.destination,
      8 => ManeuverType.continueStraight,
      9 => ManeuverType.slightRight,
      10 || 11 => ManeuverType.right,
      12 || 13 => ManeuverType.sharpRight,
      14 => ManeuverType.slightLeft,
      15 || 16 => ManeuverType.left,
      17 || 18 => ManeuverType.sharpLeft,
      26 || 27 => ManeuverType.roundabout,
      _ => ManeuverType.other,
    };
