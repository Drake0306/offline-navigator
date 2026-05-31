import 'dart:convert';
import 'package:offline_navigator/location/user_location.dart';

/// Builds the GeoJSON FeatureCollection for the user pointer.
///
/// The `heading` property drives the symbol layer's icon-rotate.
/// Negative headings (e.g. -1 reported by some platforms when unavailable)
/// are clamped to 0 so the arrow stays north-pointing rather than rotating
/// to a garbage angle.
class UserPointer {
  static const sourceId = 'user-location';
  static const layerId = 'user-location-arrow';
  static const iconId = 'pointer-arrow';

  static String featureJson(UserLocation loc) {
    final heading = loc.headingDeg < 0 ? 0.0 : loc.headingDeg;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'heading': heading},
          'geometry': {
            'type': 'Point',
            'coordinates': [loc.lng, loc.lat],
          },
        },
      ],
    });
  }

  static String emptyJson() => jsonEncode({
        'type': 'FeatureCollection',
        'features': <dynamic>[],
      });
}
