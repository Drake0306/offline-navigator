import 'dart:convert';

/// GeoJSON + style ids for the search destination pin. Mirrors UserPointer so
/// the marker is re-added across style swaps with the same ready-guard pattern.
class DestinationMarker {
  static const sourceId = 'destination';
  static const layerId = 'destination-pin';

  static String featureJson(double lat, double lng) => jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': const <String, dynamic>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [lng, lat],
            },
          }
        ],
      });

  static String emptyJson() =>
      jsonEncode({'type': 'FeatureCollection', 'features': <dynamic>[]});
}
