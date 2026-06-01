import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/valhalla_request.dart';

void main() {
  test('builds locations + costing + units per mode', () {
    final json = buildValhallaRequest(
      const [LatLng(22.586, 86.476), LatLng(22.593, 86.515)],
      TravelMode.car,
    );
    final m = jsonDecode(json) as Map<String, Object?>;
    expect(m['costing'], 'auto');
    expect(m['units'], 'kilometers');
    final locs = m['locations'] as List;
    expect(locs.length, 2);
    expect((locs.first as Map)['lat'], 22.586);
    expect((locs.first as Map)['lon'], 86.476);
  });

  test('maps each travel mode to the right Valhalla costing', () {
    String costing(TravelMode mode) => (jsonDecode(buildValhallaRequest(
            const [LatLng(0, 0), LatLng(1, 1)], mode)) as Map)['costing'] as String;
    expect(costing(TravelMode.car), 'auto');
    expect(costing(TravelMode.motorbike), 'motorcycle');
    expect(costing(TravelMode.bike), 'bicycle');
    expect(costing(TravelMode.walk), 'pedestrian');
  });
}
