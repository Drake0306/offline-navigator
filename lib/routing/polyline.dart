import 'package:offline_navigator/routing/lat_lng.dart';

/// Decodes an encoded polyline with 6-digit precision (Valhalla's format) into
/// a list of [LatLng]. Returns an empty list for an empty input.
List<LatLng> decodePolyline6(String encoded) => _decode(encoded, 1e6);

List<LatLng> _decode(String encoded, double precision) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int result = 1, shift = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63 - 1;
      result += b << shift;
      shift += 5;
    } while (b >= 0x1f);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    result = 1;
    shift = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63 - 1;
      result += b << shift;
      shift += 5;
    } while (b >= 0x1f);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / precision, lng / precision));
  }
  return points;
}
