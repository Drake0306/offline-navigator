import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/location/user_location.dart';
import 'package:offline_navigator/map/user_pointer.dart';

void main() {
  test('featureJson encodes coordinates [lng,lat] and heading', () {
    final loc = UserLocation(
      lat: 22.5,
      lng: 86.4,
      headingDeg: 42,
      speedMps: 1,
      accuracyM: 5,
      timestamp: DateTime(2026),
    );
    final fc = jsonDecode(UserPointer.featureJson(loc)) as Map<String, dynamic>;
    final f = (fc['features'] as List<dynamic>)[0] as Map<String, dynamic>;
    final coords =
        (f['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>;
    expect(coords, [86.4, 22.5]);
    expect((f['properties'] as Map<String, dynamic>)['heading'], 42);
  });

  test('featureJson clamps negative heading to 0', () {
    final loc = UserLocation(
      lat: 10.0,
      lng: 50.0,
      headingDeg: -1,
      speedMps: 0,
      accuracyM: 5,
      timestamp: DateTime(2026),
    );
    final fc = jsonDecode(UserPointer.featureJson(loc)) as Map<String, dynamic>;
    final f = (fc['features'] as List<dynamic>)[0] as Map<String, dynamic>;
    expect((f['properties'] as Map<String, dynamic>)['heading'], 0);
  });

  test('emptyJson returns a FeatureCollection with no features', () {
    final fc = jsonDecode(UserPointer.emptyJson()) as Map<String, dynamic>;
    expect(fc['type'], 'FeatureCollection');
    expect((fc['features'] as List<dynamic>).isEmpty, isTrue);
  });
}
