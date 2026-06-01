import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/routing_service.dart';
import 'package:offline_navigator/routing/fake_routing_service.dart';

void main() {
  test('returns a straight-line RoutePlan through the given points', () async {
    final svc = FakeRoutingService();
    await svc.ensureReady();
    final plan = await svc.route(
      const [LatLng(22.58, 86.47), LatLng(22.60, 86.49)],
      TravelMode.car,
    );
    expect(plan.geometry.first, const LatLng(22.58, 86.47));
    expect(plan.geometry.last, const LatLng(22.60, 86.49));
    expect(plan.distanceMeters, greaterThan(0));
    expect(plan.maneuvers, isNotEmpty);
  });

  test('throws RoutingException with fewer than 2 points', () async {
    final svc = FakeRoutingService();
    expect(
      () => svc.route(const [LatLng(22.58, 86.47)], TravelMode.car),
      throwsA(isA<RoutingException>()),
    );
  });

  test('can be configured to throw (simulating engine failure)', () async {
    final svc = FakeRoutingService(failWith: 'no tiles');
    expect(
      () => svc.route(const [LatLng(0, 0), LatLng(1, 1)], TravelMode.car),
      throwsA(isA<RoutingException>()),
    );
  });
}
