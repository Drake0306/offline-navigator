import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/routing_service.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/valhalla_routing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('offline_navigator/valhalla');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  // A minimal real-shaped Valhalla success response.
  const okResponse =
      '{"trip":{"legs":[{"summary":{"length":1.2,"time":180},"shape":"_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI","maneuvers":[{"type":1,"instruction":"Head north.","length":1.2,"time":180,"begin_shape_index":0,"end_shape_index":1}]}],"summary":{"length":1.2,"time":180},"units":"kilometers"}}';

  test('route() parses a Valhalla success response into a RoutePlan', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ensureReady') return null;
      if (call.method == 'route') return okResponse;
      return null;
    });
    final svc = ValhallaRoutingService();
    await svc.ensureReady();
    final plan = await svc.route(
        const [LatLng(22.586, 86.476), LatLng(22.593, 86.515)], TravelMode.car);
    expect(plan.distanceMeters, closeTo(1200, 0.001));
    expect(plan.maneuvers, isNotEmpty);
    expect(plan.geometry, isNotEmpty);
  });

  test('route() maps a Valhalla {code,message} error to RoutingException',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ensureReady') return null;
      if (call.method == 'route') {
        return '{"code":171,"message":"No suitable edges near location"}';
      }
      return null;
    });
    final svc = ValhallaRoutingService();
    expect(
      () => svc.route(const [LatLng(0, 0), LatLng(1, 1)], TravelMode.car),
      throwsA(isA<RoutingException>()),
    );
  });

  test('falls back to straight-line routing when the channel throws (flag on)',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'UNAVAILABLE', message: 'no native lib');
    });
    final svc = ValhallaRoutingService(fallbackToFake: true);
    final plan = await svc.route(
        const [LatLng(22.58, 86.47), LatLng(22.60, 86.49)], TravelMode.car);
    // Fake returns a straight line through the two points.
    expect(plan.geometry.first, const LatLng(22.58, 86.47));
    expect(plan.geometry.last, const LatLng(22.60, 86.49));
  });

  test('rethrows as RoutingException when the channel throws and fallback off',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'UNAVAILABLE');
    });
    final svc = ValhallaRoutingService(fallbackToFake: false);
    expect(
      () => svc.route(const [LatLng(0, 0), LatLng(1, 1)], TravelMode.car),
      throwsA(isA<RoutingException>()),
    );
  });
}
