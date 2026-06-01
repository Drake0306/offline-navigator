import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_layer.dart';

void main() {
  test('lineJson encodes a LineString of [lng,lat] pairs', () {
    final fc = jsonDecode(RouteLayer.lineJson(
        const [LatLng(22.0, 86.0), LatLng(22.1, 86.1)]));
    final geom = fc['features'][0]['geometry'];
    expect(geom['type'], 'LineString');
    expect(geom['coordinates'], [[86.0, 22.0], [86.1, 22.1]]);
  });

  test('emptyJson has no features', () {
    expect(jsonDecode(RouteLayer.emptyJson())['features'], isEmpty);
  });

  test('stable ids', () {
    expect(RouteLayer.sourceId, 'route-line');
    expect(RouteLayer.layerId, 'route-line-layer');
  });
}
