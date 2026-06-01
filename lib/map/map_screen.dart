import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre/maplibre.dart';
import 'package:offline_navigator/location/location_service.dart';
import 'package:offline_navigator/location/user_location.dart';
import 'package:offline_navigator/map/destination_marker.dart';
import 'package:offline_navigator/map/map_style.dart';
import 'package:offline_navigator/map/style_sheet.dart';
import 'package:offline_navigator/map/user_pointer.dart';
import 'package:offline_navigator/routing/valhalla_routing_service.dart';
import 'package:offline_navigator/routing/lat_lng.dart' as domain;
import 'package:offline_navigator/routing/route_layer.dart';
import 'package:offline_navigator/routing/route_plan.dart';
import 'package:offline_navigator/routing/routing_service.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/trip_state.dart';
import 'package:offline_navigator/search/search_result.dart';
import 'package:offline_navigator/search/search_screen.dart';
import 'package:offline_navigator/search/search_service.dart';
import 'package:offline_navigator/tiles/tile_service.dart';
import 'package:offline_navigator/trip/trip_planner_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.autoStart = true});

  /// When false (tests), skip tile-server startup so tests need no platform
  /// channels. The control buttons still render unconditionally.
  final bool autoStart;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _tiles = TileService();
  final _location = LocationService();
  MapController? _controller;
  StyleController? _style;
  SearchService? _search;
  SearchResult? _destination;
  StreamSubscription<UserLocation>? _locSub;
  String? _styleUrl;
  String? _bootError;
  UserLocation? _lastLoc;
  // Re-entry guard for _setupPointer (set at the START of setup so a second
  // onStyleLoaded doesn't double-add). Distinct from _pointerSourceReady.
  bool _pointerReady = false;
  // True only AFTER the pointer source+layer are actually added, and false
  // again across a style swap until they're re-added. Gates _onLocation's
  // source update so we never touch a source that doesn't exist yet.
  bool _pointerSourceReady = false;
  // True only AFTER the destination source+layer are added. Reset to false on
  // a style swap (setStyle clears them) until _setupPointer re-adds them.
  // Guards every updateGeoJsonSource(destination...) call — same pattern as
  // _pointerSourceReady to prevent the iOS missing-source crash.
  bool _destReady = false;
  bool _tilted = false;
  MapReady? _ready;
  MapStyleId? _manualStyle; // null = follow OS brightness (Auto)
  MapStyleId _activeStyle = MapStyleId.standard;

  // Trip planner state.
  // No silent fallback: a native routing failure now surfaces a real error in
  // the trip panel instead of secretly drawing a straight line. (FakeRoutingService
  // is kept for tests only.) Routing works only within the bundled Ghatshila tiles.
  final RoutingService _routing = ValhallaRoutingService(fallbackToFake: false);
  TripState _trip = const TripState(mode: TravelMode.car);
  RoutePlan? _plan;
  // True only AFTER the route line source+layer are added. Reset to false on
  // a style swap (setStyle clears them) until _setupPointer re-adds them.
  // Guards every updateGeoJsonSource(route-line...) call — same pattern as
  // _pointerSourceReady / _destReady to prevent the iOS missing-source crash.
  bool _routeReady = false;
  bool _planning = false;

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
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      _boot();
      _initLocation();
    }
  }

  Future<void> _boot() async {
    try {
      final ready = await _tiles.ensureReady();
      if (!mounted) return;
      final os = PlatformDispatcher.instance.platformBrightness;
      final active = MapStyleResolver.resolve(os, _manualStyle);
      setState(() {
        _ready = ready;
        _activeStyle = active;
        _styleUrl = ready.styleUrlFor(active);
        _bootError = null;
      });
      // Open the offline search DB (non-fatal if it fails — search just shows
      // an error to the user rather than crashing the map).
      SearchService.open().then((s) {
        if (mounted) _search = s;
      }).catchError((Object e) {
        debugPrint('Search open failed: $e');
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
    WidgetsBinding.instance.removeObserver(this);
    _locSub?.cancel();
    _location.dispose();
    _search?.dispose();
    _tiles.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Only auto-follow when the user hasn't manually picked a style.
    if (_manualStyle != null) return;
    final os = PlatformDispatcher.instance.platformBrightness;
    _applyStyle(MapStyleResolver.resolve(os, null));
  }

  /// Switches the map to [id] via setStyle. setStyle re-fires onStyleLoaded
  /// (which re-adds the pointer), and clears runtime layers — so reset the
  /// pointer guard first. No-ops if the style is already active or the map
  /// isn't ready.
  void _applyStyle(MapStyleId id) {
    final ready = _ready;
    final controller = _controller;
    if (ready == null || controller == null) return;
    if (id == _activeStyle) return;
    setState(() => _activeStyle = id);
    // setStyle clears added layers/sources: allow re-add and stop touching
    // the (now-destroyed) sources until the new style reloads them.
    _pointerReady = false;
    _pointerSourceReady = false;
    _destReady = false;
    _routeReady = false;
    controller.setStyle(ready.styleUrlFor(id));
  }

  /// Called by the style picker. A null pick means "reset to Auto".
  void _onStylePicked(MapStyleId? manual) {
    _manualStyle = manual;
    final os = PlatformDispatcher.instance.platformBrightness;
    _applyStyle(MapStyleResolver.resolve(os, manual));
  }

  Future<void> _openStyleSheet() async {
    final choice = await showStyleSheet(
      context,
      active: _activeStyle,
      isAuto: _manualStyle == null,
    );
    if (choice == null) return;
    _onStylePicked(choice.auto ? null : choice.id);
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
      // Source + layer now exist: safe for _onLocation to update them.
      _pointerSourceReady = true;
      // Push the last known fix immediately so the pointer appears at the
      // right place after a style swap without waiting for the next GPS tick.
      final last = _lastLoc;
      if (last != null) {
        style.updateGeoJsonSource(
          id: UserPointer.sourceId,
          data: UserPointer.featureJson(last),
        );
      }

      // 4. Destination marker (for search results) — empty until a result is
      //    picked. Uses a teardrop pin icon, anchored at the bottom tip so the
      //    point of the pin sits exactly on the searched coordinate.
      //    Must be added here (inside the try, same onStyleLoaded scope) so
      //    it is re-created after every style swap, guarded by _destReady.
      await style.addImage(
        'destination-pin-icon',
        (await rootBundle.load('assets/icons/destination_pin.png'))
            .buffer
            .asUint8List(),
      );
      await style.addSource(
        GeoJsonSource(
          id: DestinationMarker.sourceId,
          data: DestinationMarker.emptyJson(),
        ),
      );
      await style.addLayer(
        SymbolStyleLayer(
          id: DestinationMarker.layerId,
          sourceId: DestinationMarker.sourceId,
          layout: {
            'icon-image': 'destination-pin-icon',
            'icon-size': 0.5,
            'icon-allow-overlap': true,
            // Anchor the bottom tip of the pin on the coordinate (not center).
            'icon-anchor': 'bottom',
          },
        ),
      );
      // Destination source + layer now exist.
      _destReady = true;
      // Re-show an existing destination after a style swap.
      final dest = _destination;
      if (dest != null) {
        style.updateGeoJsonSource(
          id: DestinationMarker.sourceId,
          data: DestinationMarker.featureJson(dest.lat, dest.lng),
        );
      }

      // 5. Route line — added after the destination marker so the line renders
      //    below the destination pin. Guarded by _routeReady so the iOS
      //    missing-source crash cannot happen (same pattern as pointer/dest).
      await style.addSource(
        GeoJsonSource(id: RouteLayer.sourceId, data: RouteLayer.emptyJson()),
      );
      await style.addLayer(
        LineStyleLayer(
          id: RouteLayer.layerId,
          sourceId: RouteLayer.sourceId,
          paint: {
            'line-color': '#2f6bff',
            'line-width': 5.0,
            'line-opacity': 0.85,
          },
        ),
      );
      _routeReady = true;
      // Re-draw an existing plan after a style swap.
      final plan = _plan;
      if (plan != null) {
        style.updateGeoJsonSource(
          id: RouteLayer.sourceId,
          data: RouteLayer.lineJson(plan.geometry),
        );
      }
    } catch (e) {
      // Pointer/destination/route layer setup failed (e.g. duplicate ids on a
      // style reload). Allow a later attempt; keep the basemap usable not crashing.
      _pointerReady = false;
      _pointerSourceReady = false;
      _destReady = false;
      _routeReady = false;
      debugPrint('Pointer setup failed: $e');
      return;
    }
  }

  void _onLocation(UserLocation loc) {
    _lastLoc = loc;
    // Only update the pointer source once it actually exists. The
    // `user-location` source is added asynchronously by _setupPointer and is
    // destroyed across a style swap (setStyle clears runtime sources/layers)
    // until the new style reloads. `_pointerReady` tracks exactly that window.
    // Android's updateGeoJsonSource no-ops on a missing source, but iOS
    // force-unwraps and throws — so this guard is required, not just tidy.
    final style = _style;
    if (style != null && _pointerSourceReady) {
      style.updateGeoJsonSource(
        id: UserPointer.sourceId,
        data: UserPointer.featureJson(loc),
      );
    }
    // The follow camera should track the user regardless of pointer readiness.
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

  Future<void> _openSearch() async {
    final search = _search;
    if (search == null) return; // DB not ready yet
    final origin = _lastLoc;
    final lat = origin?.lat ?? _center.lat;
    final lng = origin?.lng ?? _center.lon;
    final result = await Navigator.of(context).push<SearchResult>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          querier: search,
          originLat: lat,
          originLng: lng,
        ),
      ),
    );
    if (result == null || !mounted) return;
    // Stop following the user, otherwise the next GPS fix would yank the
    // camera straight back to our own position. Tapping recenter re-enables
    // follow when the user wants to return to themselves.
    setState(() {
      _destination = result;
      _follow = false;
    });
    _controller?.animateCamera(
      center: Geographic(lon: result.lng, lat: result.lat),
      zoom: 16,
    );
    if (_destReady) {
      _style?.updateGeoJsonSource(
        id: DestinationMarker.sourceId,
        data: DestinationMarker.featureJson(result.lat, result.lng),
      );
    }
  }

  void _startTrip() {
    setState(() {
      _planning = true;
      // Default start to current location if we have one.
      final loc = _lastLoc;
      _trip = _trip.withStart(loc == null
          ? null
          : TripPoint(domain.LatLng(loc.lat, loc.lng), 'Your location'));
      // Seed the destination from a prior search pin if present.
      final dest = _destination;
      if (dest != null) {
        _trip = _trip.withDestination(
            TripPoint(domain.LatLng(dest.lat, dest.lng), dest.name));
      }
    });
  }

  void _onPlanChanged(RoutePlan? plan) {
    setState(() => _plan = plan);
    if (_routeReady) {
      _style?.updateGeoJsonSource(
        id: RouteLayer.sourceId,
        data: plan == null
            ? RouteLayer.emptyJson()
            : RouteLayer.lineJson(plan.geometry),
      );
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
                unawaited(_setupPointer(style));
              },
              onEvent: (event) {
                if (event is MapEventLongClick && _planning) {
                  final p = domain.LatLng(event.point.lat, event.point.lon);
                  setState(() {
                    if (_trip.destination == null) {
                      _trip = _trip.withDestination(TripPoint(p, 'Dropped pin'));
                    } else {
                      _trip = _trip.addStop(TripPoint(p, 'Stop'));
                    }
                  });
                }
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
          // Search FAB — top-left, away from the right-side control column.
          // Renders unconditionally so tests can find it with autoStart:false.
          Positioned(
            left: 12,
            top: 48,
            child: FloatingActionButton.small(
              key: const Key('searchButton'),
              heroTag: 'search',
              onPressed: _openSearch,
              child: const Icon(Icons.search),
            ),
          ),
          // Destination info card — shown when a search result is active.
          if (_destination != null)
            Positioned(
              left: 12,
              right: 72,
              bottom: 90,
              child: Card(
                key: const Key('destinationCard'),
                child: ListTile(
                  title: Text(_destination!.name),
                  subtitle: Text(_destination!.kind),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => _destination = null);
                      if (_destReady) {
                        _style?.updateGeoJsonSource(
                          id: DestinationMarker.sourceId,
                          data: DestinationMarker.emptyJson(),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          // Control buttons render regardless of map state so tests can find them.
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  key: const Key('directionsButton'),
                  heroTag: 'directions',
                  onPressed: _startTrip,
                  child: const Icon(Icons.directions),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  key: const Key('layersButton'),
                  heroTag: 'layers',
                  onPressed: _openStyleSheet,
                  child: const Icon(Icons.layers),
                ),
                const SizedBox(height: 12),
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
          // Trip planner panel — shown at the bottom when planning is active.
          if (_planning)
            Align(
              alignment: Alignment.bottomCenter,
              child: TripPlannerPanel(
                service: _routing,
                trip: _trip,
                onModeChanged: (m) => setState(() => _trip = _trip.withMode(m)),
                onRemoveStop: (i) =>
                    setState(() => _trip = _trip.removeStopAt(i)),
                onClear: () {
                  setState(() {
                    _planning = false;
                    _trip = TripState(mode: _trip.mode);
                    _plan = null;
                  });
                  if (_routeReady) {
                    _style?.updateGeoJsonSource(
                      id: RouteLayer.sourceId,
                      data: RouteLayer.emptyJson(),
                    );
                  }
                },
                onPlanChanged: _onPlanChanged,
                onStart: () {},
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
