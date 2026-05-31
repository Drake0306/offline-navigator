import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
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
  MapController? _controller;
  String? _styleUrl;
  bool _tilted = false;

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
    _tiles.dispose();
    super.dispose();
  }

  void _toggleTilt() {
    final nowTilted = !_tilted;
    setState(() => _tilted = nowTilted);
    _controller?.animateCamera(pitch: nowTilted ? 50 : 0);
  }

  void _recenter() {
    _controller?.animateCamera(center: _center, zoom: 14);
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
              onStyleLoaded: (StyleController style) {},
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
