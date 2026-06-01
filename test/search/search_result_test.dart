import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/search/search_result.dart';

void main() {
  test('haversine distance between two known points (~1.11 km per 0.01° lat)', () {
    // 0.01 degrees of latitude ≈ 1.111 km anywhere.
    final d = SearchResult.distanceMeters(22.586, 86.476, 22.596, 86.476);
    expect(d, closeTo(1111, 30));
  });

  test('zero distance for identical points', () {
    final d = SearchResult.distanceMeters(22.586, 86.476, 22.586, 86.476);
    expect(d, closeTo(0, 1e-6));
  });

  test('withDistanceFrom fills distanceM', () {
    const r = SearchResult(name: 'X', kind: 'place', lat: 22.596, lng: 86.476);
    final r2 = r.withDistanceFrom(22.586, 86.476);
    expect(r2.distanceM, closeTo(1111, 30));
    expect(r2.name, 'X');
  });
}
