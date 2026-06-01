import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/nav/heading_provider.dart';

void main() {
  test('moving fast -> uses GPS course', () {
    // speed above threshold: trust GPS course (120), ignore compass (10).
    expect(fuseHeading(gpsCourseDeg: 120, speedMps: 5, compassDeg: 10, lastDeg: 0),
        closeTo(120, 1e-6));
  });

  test('slow/stopped -> uses compass', () {
    expect(fuseHeading(gpsCourseDeg: 120, speedMps: 0.2, compassDeg: 10, lastDeg: 0),
        closeTo(10, 1e-6));
  });

  test('stopped with no compass -> holds last heading', () {
    expect(fuseHeading(gpsCourseDeg: 120, speedMps: 0.2, compassDeg: null, lastDeg: 47),
        closeTo(47, 1e-6));
  });

  test('moving but GPS course invalid (negative) -> holds last', () {
    expect(fuseHeading(gpsCourseDeg: -1, speedMps: 5, compassDeg: null, lastDeg: 33),
        closeTo(33, 1e-6));
  });

  test('result is always normalized to [0,360)', () {
    final h = fuseHeading(gpsCourseDeg: 370, speedMps: 5, compassDeg: null, lastDeg: 0);
    expect(h, greaterThanOrEqualTo(0));
    expect(h, lessThan(360));
    expect(h, closeTo(10, 1e-6));
  });
}
