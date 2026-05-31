import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _tilted = false;
  bool _follow = true;

  // Stored if location permission is not granted (used in Task 12 banner).
  // ignore: unused_field
  LocationPermissionState? _permIssue;

  // Ghatshila center — Geographic uses named params (lon, lat).
  static const _center = Geographic(lon: 86.476, lat: 22.586);

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _boot();
  }

  Future<void> _boot() async {
    final ready = await _tiles.ensureReady();
    if (!mounted) return;
    setState(() => _styleUrl = ready.styleUrl);
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
    _controller?.animateCamera(center: _center, zoom: 14);
  }

  Future<void> _setupPointer(StyleController style) async {
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
    //    relative to the map's north, not the screen.
    await style.addLayer(
      SymbolStyleLayer(
        id: UserPointer.layerId,
        sourceId: UserPointer.sourceId,
        layout: {
          'icon-image': UserPointer.iconId,
          'icon-rotate': ['get', 'heading'],
          'icon-rotation-alignment': 'map',
          'icon-allow-overlap': true,
        },
      ),
    );

    // 4. Request permission and start the location stream.
    final permState = await _location.ensurePermission();
    if (permState == LocationPermissionState.granted) {
      await _location.start();
      _locSub = _location.positions.listen(_onLocation);
    } else {
      // Store for Task 12's permission banner; no UI built here.
      if (mounted) setState(() => _permIssue = permState);
    }
  }

  void _onLocation(UserLocation loc) {
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
      );
    }
  }

  void _onMapEvent(MapEvent event) {
    // Disable follow-mode when the user manually drags the map.
    if (event is MapEventStartMoveCamera &&
        event.reason == CameraChangeReason.apiGesture) {
      if (_follow) setState(() => _follow = false);
    }
  }

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
                _setupPointer(style);
              },
              onEvent: _onMapEvent,
            )
          else
            const Center(child: CircularProgressIndicator()),
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
