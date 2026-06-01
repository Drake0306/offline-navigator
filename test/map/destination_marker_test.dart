import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/map/destination_marker.dart';

void main() {
  test('featureJson encodes [lng,lat] point', () {
    final fc = jsonDecode(DestinationMarker.featureJson(22.5, 86.4));
    final f = fc['features'][0];
    expect(f['geometry']['coordinates'], [86.4, 22.5]);
  });

  test('emptyJson has no features', () {
    final fc = jsonDecode(DestinationMarker.emptyJson());
    expect(fc['features'], isEmpty);
  });

  test('stable ids', () {
    expect(DestinationMarker.sourceId, 'destination');
    expect(DestinationMarker.layerId, 'destination-pin');
  });
}
