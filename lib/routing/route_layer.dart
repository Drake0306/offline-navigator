import 'dart:convert';
import 'package:offline_navigator/routing/lat_lng.dart';

/// GeoJSON + style ids for the drawn route line. Re-added across style swaps by
/// the map screen using a `_routeReady` guard (same pattern as the pointer).
class RouteLayer {
  static const sourceId = 'route-line';
  static const layerId = 'route-line-layer';

  static String lineJson(List<LatLng> points) => jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': const <String, dynamic>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': [for (final p in points) [p.lng, p.lat]],
            },
          }
        ],
      });

  static String emptyJson() =>
      jsonEncode({'type': 'FeatureCollection', 'features': <dynamic>[]});
}
