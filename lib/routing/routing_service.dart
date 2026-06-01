import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';
import 'package:offline_navigator/routing/travel_mode.dart';

/// Thrown when a route cannot be produced (no route, tiles missing, engine
/// error, too few points).
class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;
  @override
  String toString() => 'RoutingException: $message';
}

/// Computes routes offline. Implemented by FakeRoutingService (tests/dev) and,
/// in a later milestone, ValhallaRoutingService (native engine). The UI depends
/// only on this interface.
abstract class RoutingService {
  /// Prepare the engine (e.g. extract bundled tiles). Safe to call repeatedly.
  Future<void> ensureReady();

  /// Route through [points] (start, …stops, destination) for [mode].
  /// Throws [RoutingException] on failure.
  Future<RoutePlan> route(List<LatLng> points, TravelMode mode);
}
