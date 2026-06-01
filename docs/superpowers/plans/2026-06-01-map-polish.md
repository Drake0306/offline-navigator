# Map Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the location-permission prompt (it never fired because it was buried in the map's style-load callback), add auto dark mode that follows the phone, and add a 4-style switcher (Standard / Light / Dark / Roads) — all fully offline over the existing OSM tiles.

**Architecture:** Generate four `style.json` variants from one shared generator into `assets/style/`. `TileService` loads all four from the bundle, rewrites their `__BASE__` token to the loopback origin, and the in-app `LocalTileServer` serves each at `/style/<id>.json`. A pure-Dart `MapStyleResolver` maps (OS brightness, optional manual pick) → active style. `MapScreen` requests location permission at boot (decoupled from style loading), watches OS brightness via `WidgetsBindingObserver`, and swaps styles with `MapController.setStyle(url)` — which re-fires `onStyleLoaded`, so the user pointer is re-added automatically.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `maplibre` ^0.3.5 (`MapController.setStyle`, `StyleController.addLayer/addImage/addSource/updateGeoJsonSource`, `MapOptions.initStyle`), `geolocator` ^14, `shelf`/`shelf_router`, `path_provider`. Package name: `offline_navigator`.

---

## Conventions & ground rules

- **TDD for pure logic** (`MapStyleResolver`, server routes, `TileService` URL helpers). Widget pieces get widget tests; the on-device visual behavior is manual.
- **Verify before claiming green:** run `flutter analyze` and `flutter test` and read the ACTUAL final output line before saying a task passes or committing. Do not commit with analyzer issues.
- **Commit after each task** with the message in its final step. Run commands from repo root `/Users/roy/Developer/Github/offline_map`.
- **No device available** in the build environment (only macOS/Chrome). Acceptance per task = analyze clean + tests pass. The user runs it on their Android device.

### Verified `maplibre` 0.3.5 facts (from the installed package — build against these)
- `MapController.setStyle(String style)` swaps the style. On Android it **re-invokes `onStyleLoaded(StyleController)`** with a fresh controller. **All layers added via `StyleController.addLayer` are cleared** by a style change, so the pointer image/source/layer MUST be re-added in the re-fired `onStyleLoaded`.
- The `MapLibreMap` widget reads `options.initStyle` only at creation — it does NOT react to a changed `initStyle`. So switch styles via `controller.setStyle(url)`, and give each style a **distinct URL** so MapLibre actually reloads.
- `MapOptions(initStyle:, initCenter: Geographic(lon:,lat:), initZoom:, initPitch:, initBearing:)`. Camera coord type is `Geographic` (lon, lat).
- `StyleController`: `addImage(String id, Uint8List)`, `addSource(Source)`, `addLayer(StyleLayer)`, `updateGeoJsonSource({required String id, required String data})`, `removeLayer(String id)`, `removeSource(String id)`.
- `onStyleLoaded` type: `void Function(StyleController style)`.

---

## File structure

```
tool/generate_styles.dart              NEW  dev-time generator → 4 style files
assets/style/standard.json             NEW  (replaces style.json; current look)
assets/style/light.json                NEW
assets/style/dark.json                 NEW
assets/style/roads.json                NEW
assets/style/style.json                DELETE (replaced by standard.json)
lib/map/map_style.dart                 NEW  MapStyleId enum + MapStyleResolver
lib/map/style_sheet.dart               NEW  bottom-sheet picker
lib/tiles/local_tile_server.dart       MOD  serve /style/<id>.json (multi-style)
lib/tiles/tile_service.dart            MOD  load+serve 4 styles; styleUrlFor(id)
lib/map/map_screen.dart                MOD  boot permission; brightness watch; setStyle; layers FAB
pubspec.yaml                           MOD  register assets/style/ directory
integration_test/offline_smoke_test.dart  MOD  base-URL derivation for new route
test/map/map_style_test.dart           NEW
test/tiles/local_tile_server_test.dart MOD
test/tiles/tile_service_test.dart      MOD (add styleUrlFor test)
test/map/map_screen_test.dart          MOD (layers button + sheet)
README.md                              MOD (manual checklist for new features)
```

---

## Task 1: Generate the four style files

**Files:**
- Create: `tool/generate_styles.dart`
- Create: `assets/style/standard.json`, `light.json`, `dark.json`, `roads.json` (generator output)
- Delete: `assets/style/style.json`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Write the generator**

Create `tool/generate_styles.dart`:
```dart
// Generates the four MapLibre style variants into assets/style/.
// Run: dart run tool/generate_styles.dart
// All styles share one layer structure (same offline OSM source-layers) and
// differ only by a per-style profile (palette + which layers show). The
// literal __BASE__ token is rewritten to the local tile-server origin at
// runtime by TileService.
import 'dart:convert';
import 'dart:io';

class StyleProfile {
  const StyleProfile({
    required this.id,
    required this.background,
    required this.earth,
    required this.landuse,
    required this.water,
    required this.roadCasing,
    required this.road,
    required this.building,
    required this.text,
    required this.halo,
    required this.showLanduse,
    required this.showBuildings,
    required this.showLabels,
    required this.roadScale,
  });
  final String id;
  final String background, earth, landuse, water, roadCasing, road, building;
  final String text, halo;
  final bool showLanduse, showBuildings, showLabels;
  final double roadScale;
}

const profiles = <StyleProfile>[
  StyleProfile(
    id: 'standard',
    background: '#f3efe6', earth: '#e8e3d6', landuse: '#e2ecd6',
    water: '#a9cce3', roadCasing: '#d9c9a0', road: '#ffffff',
    building: '#d8d0c0', text: '#3b3b3b', halo: '#ffffff',
    showLanduse: true, showBuildings: true, showLabels: true, roadScale: 1.0,
  ),
  StyleProfile(
    id: 'light',
    background: '#fafafa', earth: '#f0f0f0', landuse: '#eef2ec',
    water: '#cfe0ea', roadCasing: '#e0e0e0', road: '#ffffff',
    building: '#ececec', text: '#6b6b6b', halo: '#ffffff',
    showLanduse: true, showBuildings: true, showLabels: true, roadScale: 1.0,
  ),
  StyleProfile(
    id: 'dark',
    background: '#1b1f24', earth: '#23282e', landuse: '#283028',
    water: '#1b3a4b', roadCasing: '#3a3f46', road: '#5a626c',
    building: '#2b3036', text: '#d8dde3', halo: '#14171b',
    showLanduse: true, showBuildings: true, showLabels: true, roadScale: 1.0,
  ),
  StyleProfile(
    id: 'roads',
    background: '#eef1f5', earth: '#e7ebf0', landuse: '#000000',
    water: '#b9d3e6', roadCasing: '#9aa3b0', road: '#ffffff',
    building: '#000000', text: '#2a2f36', halo: '#ffffff',
    showLanduse: false, showBuildings: false, showLabels: true, roadScale: 1.6,
  ),
];

List<Object> _w(double s) => <Object>[
      'interpolate', <Object>['linear'], <Object>['zoom'],
      8, 0.5 * s, 14, 3 * s, 18, 8 * s,
    ];

Map<String, Object> buildStyle(StyleProfile p) {
  final layers = <Map<String, Object>>[
    {'id': 'background', 'type': 'background',
      'paint': {'background-color': p.background}},
    {'id': 'earth', 'type': 'fill', 'source': 'protomaps',
      'source-layer': 'earth', 'paint': {'fill-color': p.earth}},
    if (p.showLanduse)
      {'id': 'landuse', 'type': 'fill', 'source': 'protomaps',
        'source-layer': 'landuse',
        'paint': {'fill-color': p.landuse, 'fill-opacity': 0.6}},
    {'id': 'water', 'type': 'fill', 'source': 'protomaps',
      'source-layer': 'water', 'paint': {'fill-color': p.water}},
    {'id': 'roads-casing', 'type': 'line', 'source': 'protomaps',
      'source-layer': 'roads', 'minzoom': 13,
      'paint': {
        'line-color': p.roadCasing,
        'line-gap-width': <Object>[
          'interpolate', <Object>['linear'], <Object>['zoom'], 13, 1, 18, 8],
        'line-width': 1,
      }},
    {'id': 'roads', 'type': 'line', 'source': 'protomaps',
      'source-layer': 'roads',
      'paint': {'line-color': p.road, 'line-width': _w(p.roadScale)}},
    if (p.showBuildings)
      {'id': 'buildings', 'type': 'fill', 'source': 'protomaps',
        'source-layer': 'buildings', 'minzoom': 14,
        'paint': {'fill-color': p.building}},
    if (p.showLabels)
      {'id': 'places', 'type': 'symbol', 'source': 'protomaps',
        'source-layer': 'places',
        'layout': {
          'text-field': <Object>['coalesce', <Object>['get', 'name:en'],
            <Object>['get', 'name']],
          'text-font': <Object>['Noto Sans Regular'],
          'text-size': 12,
        },
        'paint': {
          'text-color': p.text, 'text-halo-color': p.halo,
          'text-halo-width': 1.2,
        }},
  ];
  return {
    'version': 8,
    'name': 'Ghatshila ${p.id}',
    'glyphs': '__BASE__/fonts/{fontstack}/{range}.pbf',
    'sources': {
      'protomaps': {
        'type': 'vector',
        'tiles': <Object>['__BASE__/tiles/{z}/{x}/{y}.mvt'],
        'minzoom': 0,
        'maxzoom': 15,
      }
    },
    'layers': layers,
  };
}

void main() {
  final dir = Directory('assets/style');
  dir.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  for (final p in profiles) {
    final file = File('${dir.path}/${p.id}.json');
    file.writeAsStringSync('${encoder.convert(buildStyle(p))}\n');
    stdout.writeln('wrote ${file.path}');
  }
}
```

- [ ] **Step 2: Run the generator**

Run: `dart run tool/generate_styles.dart`
Expected: prints `wrote assets/style/standard.json` … `roads.json` (4 lines). Four files created.

- [ ] **Step 3: Validate the generated JSON**

Run:
```bash
for f in standard light dark roads; do python3 -c "import json;json.load(open('assets/style/$f.json'));print('$f ok')"; done
```
Expected: `standard ok` / `light ok` / `dark ok` / `roads ok`. Also confirm each still contains the literal `__BASE__` (run `grep -c __BASE__ assets/style/standard.json` → expect `2`).

- [ ] **Step 4: Remove the old single style and register the directory**

Run: `git rm assets/style/style.json` (or `rm` if not tracked separately).
In `pubspec.yaml`, under `flutter: assets:`, replace the line `- assets/style/style.json` with `- assets/style/` (registers all four). Leave the tiles/icons/glyphs lines unchanged.
Run: `flutter pub get` → expect clean resolve. Run `flutter analyze` → expect no new issues from this (style files aren't analyzed).

- [ ] **Step 5: Commit**

```bash
git add tool/generate_styles.dart assets/style/ pubspec.yaml
git commit -m "feat: generate four offline map styles (standard/light/dark/roads)"
```

---

## Task 2: MapStyleId + MapStyleResolver (pure, TDD)

**Files:**
- Create: `lib/map/map_style.dart`
- Test: `test/map/map_style_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/map/map_style_test.dart`:
```dart
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/map/map_style.dart';

void main() {
  test('auto: light brightness resolves to standard', () {
    expect(MapStyleResolver.resolve(Brightness.light, null), MapStyleId.standard);
  });

  test('auto: dark brightness resolves to dark', () {
    expect(MapStyleResolver.resolve(Brightness.dark, null), MapStyleId.dark);
  });

  test('manual pick overrides brightness', () {
    expect(MapStyleResolver.resolve(Brightness.dark, MapStyleId.roads),
        MapStyleId.roads);
    expect(MapStyleResolver.resolve(Brightness.light, MapStyleId.dark),
        MapStyleId.dark);
  });

  test('id maps to asset name and server route', () {
    expect(MapStyleId.standard.name, 'standard');
    expect(MapStyleId.roads.route, '/style/roads.json');
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/map/map_style_test.dart`
Expected: FAIL — `MapStyleId`/`MapStyleResolver` not defined.

- [ ] **Step 3: Implement**

Create `lib/map/map_style.dart`:
```dart
import 'dart:ui' show Brightness;

/// The available offline map styles. The enum [name] is also the asset
/// filename stem (`<name>.json`) and the server route stem (`/style/<name>.json`).
enum MapStyleId { standard, light, dark, roads }

extension MapStyleIdRoutes on MapStyleId {
  /// Server route this style is served at, e.g. `/style/dark.json`.
  String get route => '/style/$name.json';

  /// Asset path of the bundled style file.
  String get assetPath => 'assets/style/$name.json';

  /// Human label for the picker UI.
  String get label => switch (this) {
        MapStyleId.standard => 'Standard',
        MapStyleId.light => 'Light',
        MapStyleId.dark => 'Dark',
        MapStyleId.roads => 'Roads',
      };
}

/// Resolves which style is active from the OS brightness and an optional
/// manual pick. A manual pick always wins; otherwise we follow the OS
/// (dark → Dark, light → Standard).
class MapStyleResolver {
  static MapStyleId resolve(Brightness osBrightness, MapStyleId? manualPick) {
    if (manualPick != null) return manualPick;
    return osBrightness == Brightness.dark
        ? MapStyleId.dark
        : MapStyleId.standard;
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/map/map_style_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/map/map_style.dart test/map/map_style_test.dart
git commit -m "feat: add MapStyleId and MapStyleResolver (auto/manual resolution, tested)"
```

---

## Task 3: LocalTileServer serves multiple styles (TDD)

**Files:**
- Modify: `lib/tiles/local_tile_server.dart`
- Modify: `test/tiles/local_tile_server_test.dart`

The server currently serves one style at `/style.json`. Change it to hold a map of style-name → json and serve each at `/style/<name>.json`.

- [ ] **Step 1: Update the test to the multi-style route**

Replace the `/style.json` test in `test/tiles/local_tile_server_test.dart`. Change the `setUp` construction and the style test. The constructor now takes `styles` (a `Map<String,String>`); the server serves `/style/<name>.json`. Update `setUp`:
```dart
    server = LocalTileServer(
      reader: reader,
      glyphsDir: glyphs.path,
      styles: {'standard': '{"version":8,"name":"std"}'},
    );
    await server.start();
```
Replace the `serves style.json` test with:
```dart
  test('serves a named style', () async {
    final res = await _get('${server.baseUrl}/style/standard.json');
    expect(res.statusCode, 200);
    expect(res.body, contains('"name":"std"'));
  });

  test('404 for an unknown style', () async {
    final res = await _get('${server.baseUrl}/style/nope.json');
    expect(res.statusCode, 404);
  });

  test('updateStyles replaces served content', () async {
    server.updateStyles({'standard': '{"version":8,"name":"updated"}'});
    final res = await _get('${server.baseUrl}/style/standard.json');
    expect(res.body, contains('updated'));
  });
```
Keep the existing glyph-serving, tile-404, path-traversal, and bad-coords tests as-is.

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/tiles/local_tile_server_test.dart`
Expected: FAIL — named constructor param `styles` / route `/style/<name>.json` not present.

- [ ] **Step 3: Implement the multi-style server**

In `lib/tiles/local_tile_server.dart`, change the constructor and the style route. Replace the constructor block and `_styleJson` field:
```dart
  LocalTileServer({
    required this.reader,
    required this.glyphsDir,
    required Map<String, String> styles,
  }) : _styles = Map<String, String>.from(styles);

  final PmTilesReader reader;
  final String glyphsDir;
  Map<String, String> _styles;

  /// Replaces all served styles (called after [start] once the baseUrl —
  /// and therefore the rewritten `__BASE__` — is known).
  void updateStyles(Map<String, String> styles) =>
      _styles = Map<String, String>.from(styles);
```
Replace the old `/style.json` route with a parameterized one (place it where the old route was, inside `start()`):
```dart
    // --- /style/<name>.json ---
    router.get('/style/<name>.json', (Request req, String name) {
      final json = _styles[name];
      if (json == null) return Response.notFound('no style');
      return Response.ok(json, headers: {'content-type': 'application/json'});
    });
```
Remove the old single `updateStyle(String)` method and the `_styleJson` field (replaced by `_styles`/`updateStyles`).

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/tiles/local_tile_server_test.dart`
Expected: PASS (all: named style, unknown 404, updateStyles, glyph, tile-404, traversal, bad-coords).

- [ ] **Step 5: Commit**

```bash
git add lib/tiles/local_tile_server.dart test/tiles/local_tile_server_test.dart
git commit -m "feat: serve multiple named styles from the local tile server (tested)"
```

---

## Task 4: TileService loads & serves four styles; styleUrlFor (TDD)

**Files:**
- Modify: `lib/tiles/tile_service.dart`
- Modify: `test/tiles/tile_service_test.dart`
- Modify: `integration_test/offline_smoke_test.dart`

- [ ] **Step 1: Update the unit test**

In `test/tiles/tile_service_test.dart`, keep the existing `rewriteStyle` test and add a styleUrlFor-format test. Add:
```dart
import 'package:offline_navigator/map/map_style.dart';
// ...
  test('MapReady.styleUrlFor builds the per-style URL', () {
    final ready = MapReady('http://127.0.0.1:5599');
    expect(ready.styleUrlFor(MapStyleId.standard),
        'http://127.0.0.1:5599/style/standard.json');
    expect(ready.styleUrlFor(MapStyleId.dark),
        'http://127.0.0.1:5599/style/dark.json');
    expect(ready.styleUrl, 'http://127.0.0.1:5599/style/standard.json');
  });
```
(Note: this changes `MapReady`'s constructor to take the base origin and a `server`; see Step 3. Update the test's import list if needed.)

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/tiles/tile_service_test.dart`
Expected: FAIL — `MapReady` constructor/`styleUrlFor` mismatch.

- [ ] **Step 3: Implement**

In `lib/tiles/tile_service.dart`:

Add the import: `import 'package:offline_navigator/map/map_style.dart';`

Replace the `MapReady` class:
```dart
/// Returned by [TileService.ensureReady]. Carries the server base origin and
/// the running server. Build a per-style URL with [styleUrlFor].
class MapReady {
  MapReady(this.base, [this.server]);

  /// The server origin, e.g. `http://127.0.0.1:54321`.
  final String base;
  final LocalTileServer? server;

  String styleUrlFor(MapStyleId id) => '$base${id.route}';

  /// Convenience: the default (Standard) style URL.
  String get styleUrl => styleUrlFor(MapStyleId.standard);
}
```

Replace `ensureReady()` to load all four styles and serve them:
```dart
  Future<MapReady> ensureReady() async {
    final supportDir = await getApplicationSupportDirectory();
    final paths = AppPaths(root: supportDir.path);

    if (await paths.needsRefresh(kAssetVersion)) {
      await _copyAsset('assets/tiles/ghatshila.pmtiles', paths.tilesPath);
      await _copyGlyphs(paths.glyphsDir);
      await paths.writeStamp(kAssetVersion);
    }

    // Load all four style templates from the bundle (keyed by id name).
    final templates = <String, String>{};
    for (final id in MapStyleId.values) {
      templates[id.name] = await rootBundle.loadString(id.assetPath);
    }

    final reader = await PmTilesReader.open(paths.tilesPath);
    final server = LocalTileServer(
      reader: reader,
      glyphsDir: paths.glyphsDir,
      styles: const {}, // placeholder; filled after baseUrl is known
    );
    await server.start();

    // Rewrite __BASE__ in each style to the loopback origin and install them.
    final base = server.baseUrl;
    final styles = <String, String>{
      for (final e in templates.entries) e.key: rewriteStyle(e.value, base),
    };
    server.updateStyles(styles);

    _server = server;
    return MapReady(base, server);
  }
```

(`rewriteStyle`, `_copyAsset`, `_copyGlyphs`, `dispose`, `kAssetVersion`, `kFontStack` stay unchanged.)

- [ ] **Step 4: Fix the integration test's base-URL derivation**

In `integration_test/offline_smoke_test.dart`, the style route changed from `/style.json` to `/style/standard.json`. Update the assertions and base derivation:
```dart
      // style.json → now /style/standard.json
      final styleRes = await _get(ready.styleUrl);
      expect(styleRes.statusCode, 200);
      expect(styleRes.body, contains('127.0.0.1'));
      expect(styleRes.body, contains('version'));

      // Derive base from MapReady.base (no string surgery needed).
      final base = ready.base;
      final tileUrl = '$base/tiles/$z/$tileX/$tileY.mvt';
```
Replace the old `final base = ready.styleUrl.replaceAll('/style.json', '');` line with `final base = ready.base;`. Leave the z14 tile computation and the rest unchanged.

- [ ] **Step 5: Run tests**

Run: `flutter test test/tiles/`
Expected: PASS (tile_service rewriteStyle + styleUrlFor; local_tile_server suite; pmtiles_reader suite).
Run: `flutter analyze` → expect "No issues found!".

- [ ] **Step 6: Commit**

```bash
git add lib/tiles/tile_service.dart test/tiles/tile_service_test.dart integration_test/offline_smoke_test.dart
git commit -m "feat: TileService loads and serves four styles; MapReady.styleUrlFor (tested)"
```

---

## Task 5: Decouple location permission from style loading (the prompt bug fix)

**Files:**
- Modify: `lib/map/map_screen.dart`
- Modify: `test/map/map_screen_test.dart`

The prompt never appeared because `ensurePermission()` only ran inside `_setupPointer` (called from `onStyleLoaded`). Move the permission request to boot, independent of the map.

- [ ] **Step 1: Move permission to boot; remove it from _setupPointer**

In `lib/map/map_screen.dart`:

In `initState`, request location regardless of `autoStart` of the map style (still skip in tests):
```dart
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      _boot();
      _initLocation();
    }
  }
```

Add `_initLocation()` (new) and a stream-start helper:
```dart
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
```

In `_setupPointer`, DELETE the entire "// 4. Request permission and start the location stream." block (the `try { final permState = await _location.ensurePermission(); ... }` section). `_setupPointer` now only adds the image/source/layer for the pointer. The stream is owned by `_initLocation`/`_startLocationStream`. The pointer source updates safely once it exists because `_onLocation` already guards `if (style == null) return;` and `updateGeoJsonSource` is a no-op target until the layer is present.

In the permission banner's Grant handler, replace the inline start with the helper:
```dart
                    if (s == LocationPermissionState.granted) {
                      setState(() => _permIssue = null);
                      await _startLocationStream();
                    }
```

- [ ] **Step 2: Add a widget test that permission is requested at boot independent of style**

This is hard to assert without mocking geolocator platform channels. Instead assert the structural fix: with `autoStart:false` the screen builds and the controls render (already covered), and add a focused test that `_initLocation` is wired by checking the method exists via a boot flag is overkill. Keep it simple — add a test that the existing behavior is preserved and the banner still works:
```dart
  testWidgets('permission banner Grant button present when denied', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    final dynamic state = tester.state(find.byType(MapScreen));
    // ignore: invalid_use_of_visible_for_testing_member
    state.showPermissionIssueForTest(LocationPermissionState.deniedForever);
    await tester.pump();
    expect(find.byKey(const Key('permActionButton')), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });
```
(The real "prompt fires at boot" behavior is verified on-device per the manual checklist — it depends on platform channels not available in widget tests.)

- [ ] **Step 3: Run tests**

Run: `flutter test test/map/map_screen_test.dart`
Expected: PASS (existing controls test, permission banner tests, retry test, the new deniedForever test).
Run: `flutter analyze` → "No issues found!" (watch for an unused-import or unreachable-code warning from the deleted block; fix if any).

- [ ] **Step 4: Commit**

```bash
git add lib/map/map_screen.dart test/map/map_screen_test.dart
git commit -m "fix: request location permission at boot, decoupled from style loading"
```

---

## Task 6: Brightness watch + active style + setStyle + pointer re-add

**Files:**
- Modify: `lib/map/map_screen.dart`

- [ ] **Step 1: Make the state observe platform brightness**

In `lib/map/map_screen.dart`, add imports:
```dart
import 'dart:ui' show PlatformDispatcher;
import 'package:offline_navigator/map/map_style.dart';
```
Change the state declaration to mix in the observer:
```dart
class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
```
Add fields near the other state fields:
```dart
  MapReady? _ready;
  MapStyleId? _manualStyle; // null = follow OS brightness (Auto)
  MapStyleId _activeStyle = MapStyleId.standard;
```

- [ ] **Step 2: Register/unregister the observer and compute the initial style**

Update `initState` and `dispose`:
```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      _boot();
      _initLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locSub?.cancel();
    _location.dispose();
    _tiles.dispose();
    super.dispose();
  }
```
Update `_boot()` to store `_ready` and pick the initial style from current brightness:
```dart
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _bootError = 'Could not load the offline map.\n$e');
    }
  }
```

- [ ] **Step 3: React to OS brightness changes**

Add:
```dart
  @override
  void didChangePlatformBrightness() {
    // Only auto-follow when the user hasn't manually picked a style.
    if (_manualStyle != null) return;
    final os = PlatformDispatcher.instance.platformBrightness;
    _applyStyle(MapStyleResolver.resolve(os, null));
  }
```

- [ ] **Step 4: Implement the style swap (re-adds the pointer)**

Add:
```dart
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
    _pointerReady = false; // setStyle clears added layers; allow re-add
    controller.setStyle(ready.styleUrlFor(id));
  }

  /// Called by the style picker. A null pick means "reset to Auto".
  void _onStylePicked(MapStyleId? manual) {
    _manualStyle = manual;
    final os = PlatformDispatcher.instance.platformBrightness;
    _applyStyle(MapStyleResolver.resolve(os, manual));
  }
```

- [ ] **Step 5: Analyze (no test step — behavior is covered by Task 7 + manual)**

Run: `flutter analyze`
Expected: "No issues found!". (If `_onStylePicked`/`_applyStyle` are reported unused, that's expected until Task 7 wires the button — proceed; Task 7 resolves it. If you prefer zero interim warnings, combine Step 5 here with Task 7 before committing. Otherwise commit now.)

- [ ] **Step 6: Commit**

```bash
git add lib/map/map_screen.dart
git commit -m "feat: watch OS brightness and swap map style via setStyle (re-adds pointer)"
```

---

## Task 7: Style picker sheet + layers FAB

**Files:**
- Create: `lib/map/style_sheet.dart`
- Modify: `lib/map/map_screen.dart`
- Modify: `test/map/map_screen_test.dart`

- [ ] **Step 1: Implement the picker sheet**

Create `lib/map/style_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:offline_navigator/map/map_style.dart';

/// Result of the style picker. [auto] true means "follow OS brightness";
/// otherwise [id] is the manual pick.
typedef StyleChoice = ({bool auto, MapStyleId? id});

/// Shows the style picker as a bottom sheet. Returns null if dismissed.
Future<StyleChoice?> showStyleSheet(
  BuildContext context, {
  required MapStyleId active,
  required bool isAuto,
}) {
  return showModalBottomSheet<StyleChoice>(
    context: context,
    builder: (ctx) => StyleSheet(active: active, isAuto: isAuto),
  );
}

class StyleSheet extends StatelessWidget {
  const StyleSheet({super.key, required this.active, required this.isAuto});

  final MapStyleId active;
  final bool isAuto;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Map style', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final id in MapStyleId.values)
            ListTile(
              key: Key('style-${id.name}'),
              leading: Icon(id == active ? Icons.check_circle
                  : Icons.circle_outlined),
              title: Text(id.label),
              onTap: () => Navigator.pop<StyleChoice>(
                  context, (auto: false, id: id)),
            ),
          const Divider(height: 1),
          ListTile(
            key: const Key('style-auto'),
            leading: Icon(isAuto ? Icons.brightness_auto
                : Icons.brightness_auto_outlined),
            title: const Text('Auto (follow system)'),
            subtitle: isAuto ? const Text('Active') : null,
            onTap: () => Navigator.pop<StyleChoice>(
                context, (auto: true, id: null)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add the layers FAB and wire it**

In `lib/map/map_screen.dart`, add the import:
```dart
import 'package:offline_navigator/map/style_sheet.dart';
```
Add a handler:
```dart
  Future<void> _openStyleSheet() async {
    final choice = await showStyleSheet(
      context,
      active: _activeStyle,
      isAuto: _manualStyle == null,
    );
    if (choice == null) return;
    _onStylePicked(choice.auto ? null : choice.id);
  }
```
In `build`, add a layers FAB ABOVE the tilt button in the existing FAB `Column` (as the first child, before `tiltButton`):
```dart
                FloatingActionButton.small(
                  key: const Key('layersButton'),
                  heroTag: 'layers',
                  onPressed: _openStyleSheet,
                  child: const Icon(Icons.layers),
                ),
                const SizedBox(height: 12),
```

- [ ] **Step 3: Add a widget test for the layers button + sheet**

In `test/map/map_screen_test.dart`, add:
```dart
  testWidgets('layers button opens the style sheet', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    expect(find.byKey(const Key('layersButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('layersButton')));
    await tester.pumpAndSettle();

    // Sheet shows all four styles + Auto.
    expect(find.byKey(const Key('style-standard')), findsOneWidget);
    expect(find.byKey(const Key('style-dark')), findsOneWidget);
    expect(find.byKey(const Key('style-roads')), findsOneWidget);
    expect(find.byKey(const Key('style-auto')), findsOneWidget);
  });
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/map/map_screen_test.dart`
Expected: PASS (controls, permission banner ×, retry, layers-opens-sheet).
Run: `flutter analyze` → "No issues found!" (the `_onStylePicked`/`_applyStyle` unused warnings from Task 6 are now resolved).

- [ ] **Step 5: Commit**

```bash
git add lib/map/style_sheet.dart lib/map/map_screen.dart test/map/map_screen_test.dart
git commit -m "feat: add layers button + style picker sheet (Standard/Light/Dark/Roads + Auto)"
```

---

## Task 8: Full verification + README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full clean verification**

Run:
```bash
flutter analyze
flutter test
```
Expected: analyzer "No issues found!"; all tests pass (read the final `+N: All tests passed!` line and record N). If anything fails, fix it before continuing — do not proceed on red.

- [ ] **Step 2: Update the README manual checklist**

In `README.md`, under the manual acceptance checklist, add steps for the new features (insert after the existing tilt step):
```markdown
8. Tap the **layers button** (bottom-right, top FAB) — confirm the style sheet
   opens with Standard / Light / Dark / Roads + Auto.
9. Pick each style — confirm the map restyles and the GPS arrow re-appears.
10. Pick **Auto**, then toggle the phone's system dark mode — confirm the map
    switches between the Standard (light) and Dark styles automatically.
11. Confirm the **location-permission prompt appears on a fresh install** at
    launch (uninstall + reinstall to retest), independent of the map loading.
```
Also update the "Verification status" table's test count to the number from Step 1.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add manual checklist for styles, dark mode, and permission prompt"
```

---

## Self-review (completed at plan-writing time)

**Spec coverage:**
- Location prompt fix (decouple from style load) → Task 5. ✓
- Auto dark mode (light→Standard, dark→Dark, live switch) → Task 2 (resolver) + Task 6 (`didChangePlatformBrightness`). ✓
- Manual override sticks for session; Reset to Auto → Task 6 (`_manualStyle`, `_onStylePicked`) + Task 7 (sheet). ✓
- Four styles over same offline tiles → Task 1 (generator) + Task 4 (serve all four). ✓
- Layers FAB + bottom-sheet picker → Task 7. ✓
- Pointer re-added after style swap → Task 6 (`_applyStyle` resets `_pointerReady`; `onStyleLoaded` re-fires per verified API). ✓
- Offline guarantee (only `__BASE__`/local URLs) → Task 1 styles keep `__BASE__`; Task 4 rewrites to loopback. ✓
- Session-only persistence (no disk) → `_manualStyle` is in-memory; no storage added. ✓
- Testing (resolver unit, server routes, tile_service URL, widget sheet/banner) → Tasks 2,3,4,5,7. ✓
- Out of scope (search, routing, terrain, street view, cross-restart persistence) → not present. ✓

**Placeholder scan:** No TBD/TODO/"implement later". Every code step has complete code. Task 6 Step 5 notes an expected *interim* unused-symbol warning that Task 7 resolves, with the option to defer the commit — this is a sequencing note, not a placeholder.

**Type consistency:** `MapStyleId` (enum, `.name`/`.route`/`.assetPath`/`.label`) consistent across Tasks 1,2,3,4,6,7. `MapReady(base, [server])` + `styleUrlFor(MapStyleId)`/`styleUrl` consistent across Tasks 4 (def), 6 (use), and the integration test. `LocalTileServer({reader, glyphsDir, styles})` + `updateStyles(Map)` + route `/style/<name>.json` consistent across Tasks 3,4. `MapStyleResolver.resolve(Brightness, MapStyleId?)` consistent across Tasks 2,6. `_applyStyle`/`_onStylePicked`/`_manualStyle`/`_activeStyle`/`_ready` consistent across Tasks 6,7. `StyleChoice = ({bool auto, MapStyleId? id})` consistent across Task 7 (sheet) and `_openStyleSheet`.

**Known on-device-only items (not blockers):** the permission prompt firing at boot and the live brightness switch depend on platform channels and are verified via the manual checklist, not widget tests. The exact style colors are tunable after a first visual look on-device.
