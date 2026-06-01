import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre/maplibre.dart';
import 'package:offline_navigator/location/location_service.dart';
import 'package:offline_navigator/location/user_location.dart';
import 'package:offline_navigator/map/user_pointer.dart';
import 'package:offline_navigator/tiles/tile_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.autoStart = true});

  /// When false (tests), skip tile-server startup so tests need no platform
  /// channels. The control buttons still render unconditionally.
  final bool autoStart;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _tiles = TileService();
  final _location = LocationService();
  MapController? _controller;
  StyleController? _style;
  StreamSubscription<UserLocation>? _locSub;
  String? _styleUrl;
  String? _bootError;
  UserLocation? _lastLoc;
  bool _pointerReady = false;
  bool _tilted = false;

  /// How long the follow-camera takes to glide to each new GPS fix. Short
  /// enough to keep up with ~1 fix/sec without the 2s default piling up and
  /// making the map float; long enough to stay smooth alongside EMA smoothing.
  static const _followDuration = Duration(milliseconds: 700);
  // v1: follow stays on until recenter is re-tapped; maplibre 0.3.5 has no
  // reliable user-gesture signal to auto-disable follow on manual pan.
  bool _follow = true;

  // Stored if location permission is not granted; drives the permission banner.
  LocationPermissionState? _permIssue;

  // Ghatshila center — Geographic uses named params (lon, lat).
  static const _center = Geographic(lon: 86.476, lat: 22.586);

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      _boot();
      _initLocation();
    }
  }

  Future<void> _boot() async {
    try {
      final ready = await _tiles.ensureReady();
      if (!mounted) return;
      setState(() {
        _styleUrl = ready.styleUrl;
        _bootError = null;
      });
    } catch (e) {
      // Asset copy / disk full / port bind / corrupt tile pack — surface a
      // clear error with a retry instead of spinning forever (spec §8).
      if (!mounted) return;
      setState(() => _bootError = 'Could not load the offline map.\n$e');
    }
  }

  /// Requests location permission at startup, independent of map-style
  /// loading. This is the fix for the prompt not appearing: previously the
  /// request was buried in _setupPointer (only reached via onStyleLoaded).
  Future<void> _initLocation() async {
    try {
      final state = await _location.ensurePermission();
      if (!mounted) return;
      if (state == LocationPermissionState.granted) {
        await _startLocationStream();
      } else {
        setState(() => _permIssue = state);
      }
    } catch (e) {
      debugPrint('Location init failed: $e');
    }
  }

  Future<void> _startLocationStream() async {
    await _location.start();
    await _locSub?.cancel();
    _locSub = _location.positions.listen(_onLocation);
  }

  void _retryBoot() {
    setState(() => _bootError = null);
    _boot();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _location.dispose();
    _tiles.dispose();
    super.dispose();
  }

  void _toggleTilt() {
    final nowTilted = !_tilted;
    setState(() => _tilted = nowTilted);
    _controller?.animateCamera(pitch: nowTilted ? 50 : 0);
  }

  void _recenter() {
    setState(() => _follow = true);
    // Recenter on the user if we have a fix; otherwise fall back to the
    // bundled region's center. The next GPS tick keeps it glued to the user.
    final loc = _lastLoc;
    final target =
        loc != null ? Geographic(lon: loc.lng, lat: loc.lat) : _center;
    _controller?.animateCamera(center: target, zoom: 14);
  }

  Future<void> _setupPointer(StyleController style) async {
    // onStyleLoaded can fire more than once (e.g. a style reload). Adding the
    // same image/source/layer twice throws on duplicate ids, so guard it.
    if (_pointerReady) return;
    _pointerReady = true;
    try {
      // 1. Register the arrow PNG as a named style image.
      final data = await rootBundle.load('assets/icons/pointer_arrow.png');
      await style.addImage(UserPointer.iconId, data.buffer.asUint8List());

      // 2. Add an empty GeoJSON source.
      await style.addSource(
        GeoJsonSource(
          id: UserPointer.sourceId,
          data: UserPointer.emptyJson(),
        ),
      );

      // 3. Add a symbol layer using the icon, rotated by the feature `heading`
      //    property. icon-rotation-alignment: 'map' ensures the arrow rotates
      //    relative to the map's north, not the screen. icon-size scales the
      //    96px source PNG to a sensible on-screen size.
      await style.addLayer(
        SymbolStyleLayer(
          id: UserPointer.layerId,
          sourceId: UserPointer.sourceId,
          layout: {
            'icon-image': UserPointer.iconId,
            'icon-rotate': ['get', 'heading'],
            'icon-rotation-alignment': 'map',
            'icon-allow-overlap': true,
            'icon-size': 0.5,
          },
        ),
      );
    } catch (e) {
      // Pointer layer setup failed (e.g. duplicate ids on a style reload).
      // Allow a later attempt and keep the basemap usable rather than crashing.
      _pointerReady = false;
      debugPrint('Pointer setup failed: $e');
      return;
    }
  }

  void _onLocation(UserLocation loc) {
    _lastLoc = loc;
    final style = _style;
    if (style == null) return;
    // Update the GeoJSON source with new position and heading.
    style.updateGeoJsonSource(
      id: UserPointer.sourceId,
      data: UserPointer.featureJson(loc),
    );
    if (_follow) {
      _controller?.animateCamera(
        center: Geographic(lon: loc.lng, lat: loc.lat),
        nativeDuration: _followDuration,
      );
    }
  }

  Widget? _permBanner() {
    final issue = _permIssue;
    if (issue == null) return null;
    final (msg, action) = switch (issue) {
      LocationPermissionState.serviceOff => (
        'Location services are off.',
        'Open settings',
      ),
      LocationPermissionState.deniedForever => (
        'Location permission is blocked.',
        'Open settings',
      ),
      _ => (
        'Location permission needed to show your position.',
        'Grant',
      ),
    };
    return Positioned(
      left: 12,
      right: 12,
      top: 48,
      child: Material(
        color: const Color(0xFFFDF1DC),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text(msg)),
              TextButton(
                key: const Key('permActionButton'),
                onPressed: () async {
                  if (action == 'Open settings') {
                    await Geolocator.openAppSettings();
                  } else {
                    final s = await _location.ensurePermission();
                    if (!mounted) return;
                    if (s == LocationPermissionState.granted) {
                      setState(() => _permIssue = null);
                      await _startLocationStream();
                    }
                  }
                },
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Exposed for widget tests only — sets _permIssue and triggers a rebuild.
  @visibleForTesting
  void showPermissionIssueForTest(LocationPermissionState s) =>
      setState(() => _permIssue = s);

  /// Exposed for widget tests only — simulates a boot failure.
  @visibleForTesting
  void showBootErrorForTest(String message) =>
      setState(() => _bootError = message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_styleUrl != null)
            MapLibreMap(
              options: MapOptions(
                initStyle: _styleUrl!,
                initCenter: _center,
                initZoom: 14,
                initPitch: _tilted ? 50 : 0,
                initBearing: 0,
              ),
              onMapCreated: (MapController c) {
                _controller = c;
              },
              onStyleLoaded: (StyleController style) {
                _style = style;
                unawaited(_setupPointer(style));
              },
            )
          else if (_bootError != null)
            _BootError(message: _bootError!, onRetry: _retryBoot)
          else
            const Center(child: CircularProgressIndicator()),
          // Permission banner — overlays the map but does not block pan/zoom.
          if (_permBanner() != null) _permBanner()!,
          // OSM/ODbL attribution — required when displaying OpenStreetMap data.
          if (_styleUrl != null)
            const Positioned(left: 8, bottom: 6, child: _Attribution()),
          // Control buttons render regardless of map state so tests can find them.
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  key: const Key('tiltButton'),
                  heroTag: 'tilt',
                  onPressed: _toggleTilt,
                  child: const Icon(Icons.threed_rotation),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  key: const Key('recenterButton'),
                  heroTag: 'recenter',
                  onPressed: _recenter,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Map data attribution required by OpenStreetMap's ODbL license.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '© OpenStreetMap',
        style: TextStyle(fontSize: 10, color: Color(0xFF3B3B3B)),
      ),
    );
  }
}

/// Full-screen error state shown when the offline map fails to load, with a
/// retry affordance so the user isn't stuck on an indefinite spinner.
class _BootError extends StatelessWidget {
  const _BootError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 48, color: Color(0xFF8A93A6)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('retryBootButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
