import 'package:offline_navigator/routing/lat_lng.dart';

/// A coarse classification of a maneuver, mapped from Valhalla's type codes.
enum ManeuverType {
  start,
  destination,
  continueStraight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  roundabout,
  other,
}

/// One turn-by-turn step.
class Maneuver {
  const Maneuver({
    required this.instruction,
    required this.distanceMeters,
    required this.duration,
    required this.location,
    required this.type,
  });
  final String instruction;
  final double distanceMeters;
  final Duration duration;
  final LatLng location; // where the maneuver begins (for live-progress)
  final ManeuverType type;
}

/// One leg = start→stop, stop→stop, or stop→destination.
class RouteLeg {
  const RouteLeg({
    required this.distanceMeters,
    required this.duration,
    required this.maneuvers,
  });
  final double distanceMeters;
  final Duration duration;
  final List<Maneuver> maneuvers;
}

/// A full computed route through all requested points.
class RoutePlan {
  const RoutePlan({
    required this.geometry,
    required this.legs,
    required this.distanceMeters,
    required this.duration,
  });

  /// The full decoded route line (all legs concatenated).
  final List<LatLng> geometry;
  final List<RouteLeg> legs;
  final double distanceMeters;
  final Duration duration;

  /// All maneuvers across all legs, in order.
  List<Maneuver> get maneuvers =>
      [for (final leg in legs) ...leg.maneuvers];
}
