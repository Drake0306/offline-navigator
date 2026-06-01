import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/route_format.dart';

void main() {
  test('formats distance in m below 1km, km above', () {
    expect(formatDistance(450), '450 m');
    expect(formatDistance(1200), '1.2 km');
    expect(formatDistance(0), '0 m');
  });

  test('formats duration as min, and h+min above an hour', () {
    expect(formatDuration(const Duration(minutes: 12)), '12 min');
    expect(formatDuration(const Duration(seconds: 90)), '2 min'); // rounds up
    expect(formatDuration(const Duration(hours: 1, minutes: 5)), '1 h 5 min');
  });
}
