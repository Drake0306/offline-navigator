import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/polyline.dart';

void main() {
  test('decodes a known polyline6 string', () {
    // Verified polyline6 encoding of [(38.5,-120.2),(40.7,-120.95),(43.252,-126.453)]
    // (precision 1e6). Computed + round-trip-checked against the decoder below.
    const encoded = '_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI';
    final pts = decodePolyline6(encoded);
    expect(pts.length, 3);
    expect(pts[0].lat, closeTo(38.5, 1e-5));
    expect(pts[0].lng, closeTo(-120.2, 1e-5));
    expect(pts[2].lat, closeTo(43.252, 1e-5));
    expect(pts[2].lng, closeTo(-126.453, 1e-5));
  });

  test('empty string decodes to empty list', () {
    expect(decodePolyline6(''), isEmpty);
  });

  test('LatLng equality + props', () {
    expect(const LatLng(1.0, 2.0), const LatLng(1.0, 2.0));
    expect(const LatLng(1.0, 2.0).lat, 1.0);
    expect(const LatLng(1.0, 2.0).lng, 2.0);
  });
}
