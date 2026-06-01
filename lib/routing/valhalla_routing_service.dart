import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:offline_navigator/routing/fake_routing_service.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/route_plan.dart';
import 'package:offline_navigator/routing/routing_service.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/valhalla_parser.dart';
import 'package:offline_navigator/routing/valhalla_request.dart';

/// Real on-device routing via the native Valhalla engine (Android), reached
/// through the `offline_navigator/valhalla` MethodChannel. Reuses the Part 1
/// [parseValhallaRoute]. When [fallbackToFake] is true (default), native
/// failures transparently degrade to straight-line routing so the app stays
/// usable while debugging the native integration.
class ValhallaRoutingService implements RoutingService {
  ValhallaRoutingService({this.fallbackToFake = true, this.regionDir});

  final bool fallbackToFake;

  /// Directory of the active region's routing files (`valhalla_tiles.tar` +
  /// `admins.sqlite`); the native side writes a `valhalla.json` there and caches
  /// an actor per dir. Null routes over the legacy bundled tiles in app files
  /// storage. Mutable so switching the active region doesn't require a new
  /// service instance (re-`ensureReady`s on change).
  String? regionDir;

  static const _channel = MethodChannel('offline_navigator/valhalla');
  final _fake = FakeRoutingService();

  bool _ready = false;
  String? _readyDir;

  /// Channel args: [extra] merged with `regionDir` when one is set.
  Map<String, Object?> _args([Map<String, Object?> extra = const {}]) => {
        ...extra,
        if (regionDir != null) 'regionDir': regionDir,
      };

  @override
  Future<void> ensureReady() async {
    if (_ready && _readyDir == regionDir) return;
    try {
      await _channel.invokeMethod<void>('ensureReady', _args());
      _ready = true;
      _readyDir = regionDir;
    } on PlatformException catch (e) {
      if (fallbackToFake) return; // fake needs no setup
      throw RoutingException('Routing engine unavailable: ${e.message}');
    }
  }

  @override
  Future<RoutePlan> route(List<LatLng> points, TravelMode mode) async {
    if (points.length < 2) {
      throw const RoutingException('Need at least a start and a destination');
    }
    final String responseJson;
    try {
      await ensureReady();
      final req = buildValhallaRequest(points, mode);
      final res =
          await _channel.invokeMethod<String>('route', _args({'request': req}));
      if (res == null) throw const RoutingException('Empty routing response');
      responseJson = res;
    } on PlatformException catch (e) {
      if (fallbackToFake) return _fake.route(points, mode);
      throw RoutingException('Routing failed: ${e.message}');
    }

    // Valhalla returns {"code","message"} on error, {"trip":{...}} on success.
    final decoded = jsonDecode(responseJson);
    if (decoded is Map && decoded.containsKey('code') &&
        !decoded.containsKey('trip')) {
      final code = (decoded['code'] as num?)?.toInt();
      final msg = (decoded['message'] as String?) ?? 'No route found';
      // 171 = no suitable edges near a location (point off the road network or
      // outside the downloaded tiles).
      if (code == 171) {
        throw const RoutingException(
            'No route found near here — the point may be outside the downloaded map area.');
      }
      throw RoutingException(msg);
    }
    try {
      return parseValhallaRoute(decoded as Map<String, Object?>);
    } on FormatException catch (e) {
      throw RoutingException('Bad routing response: ${e.message}');
    }
  }
}
