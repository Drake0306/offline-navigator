import 'dart:convert';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';

/// Builds a Valhalla `/route` request JSON string from ordered [points] and a
/// [mode]. Valhalla locations use {lat, lon}; costing is the mode's costing
/// model; units kilometres (matching the parser's km→metres conversion).
String buildValhallaRequest(List<LatLng> points, TravelMode mode) {
  return jsonEncode({
    'locations': [
      for (final p in points) {'lat': p.lat, 'lon': p.lng},
    ],
    'costing': mode.costing,
    'units': 'kilometers',
  });
}
