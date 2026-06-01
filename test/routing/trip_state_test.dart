import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/trip_state.dart';

void main() {
  const start = TripPoint(LatLng(22.58, 86.47), 'Start');
  const a = TripPoint(LatLng(22.60, 86.49), 'A');
  const b = TripPoint(LatLng(22.62, 86.51), 'B');

  test('orderedPoints is start, stops in order, then destination', () {
    final t = TripState(start: start, destination: b, stops: const [a], mode: TravelMode.car);
    expect(t.orderedPoints.map((p) => p.label), ['Start', 'A', 'B']);
    expect(t.latLngs.length, 3);
  });

  test('isRoutable only when start and destination are set', () {
    expect(const TripState(mode: TravelMode.car).isRoutable, isFalse);
    expect(TripState(start: start, mode: TravelMode.car).isRoutable, isFalse);
    expect(TripState(start: start, destination: b, mode: TravelMode.car).isRoutable, isTrue);
  });

  test('addStop/removeStop/reorderStops are immutable updates', () {
    var t = TripState(start: start, destination: b, mode: TravelMode.car);
    t = t.addStop(a);
    expect(t.stops.map((p) => p.label), ['A']);
    final c = const TripPoint(LatLng(22.63, 86.52), 'C');
    t = t.addStop(c); // [A, C]
    t = t.reorderStops(0, 2); // move A to end → [C, A]
    expect(t.stops.map((p) => p.label), ['C', 'A']);
    t = t.removeStopAt(0); // remove C → [A]
    expect(t.stops.map((p) => p.label), ['A']);
  });

  test('withMode changes the mode immutably', () {
    final t = TripState(start: start, mode: TravelMode.car).withMode(TravelMode.walk);
    expect(t.mode, TravelMode.walk);
  });
}
