# Region Download Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use
> checkbox (`- [ ]`) syntax. Large milestone — built and executed **part by part**; Part 1 is fully
> detailed here, Parts 2–4 are specified at task level and expanded into bite-sized steps when their
> part begins (controller hands each implementer the full spec at dispatch).

**Goal:** Download per-district regions (map + routing + search) on demand to device storage, switch
the active region, and have the whole app render/route/search over it — fully offline after download.

**Architecture:** A pure-Dart region domain (`lib/regions/`) — models, catalog, on-device store,
downloader, and a `RegionController` — drives three now-**region-aware** consumers (tiles, routing,
search). Ghatshila stays bundled as the default region. Data is generated via Docker from a Geofabrik
extract and hosted on GitHub Releases.

**Tech Stack:** Dart 3.12 / Flutter 3.44; `http` (download), `crypto` (sha256), `path_provider`,
`sqflite`; existing `PmTilesReader`/`LocalTileServer`; `valhalla-mobile` 0.3.0 via MethodChannel;
Docker + Geofabrik + `pmtiles` for data.

---

## Part 1 — Region core (`lib/regions/`, pure Dart)

### Task 1: Region domain models

**Files:**
- Create: `lib/regions/region.dart`
- Test: `test/regions/region_test.dart`

- [ ] **Step 1: Failing test** (`test/regions/region_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/regions/region.dart';

void main() {
  const json = '''
  {"id":"in-jh-east-singhbhum","name":"East Singhbhum (Jamshedpur)","state":"Jharkhand",
   "bbox":[86.0,22.2,86.9,23.1],"version":1,
   "files":{"tiles":{"url":"https://x/t.pmtiles","bytes":10,"sha256":"aa"},
            "valhalla":{"url":"https://x/v.tar","bytes":20,"sha256":"bb"},
            "admins":{"url":"https://x/a.sqlite","bytes":30,"sha256":"cc"},
            "search":{"url":"https://x/s.sqlite","bytes":40,"sha256":"dd"}}}''';

  test('parses a region entry', () {
    final r = Region.fromJson(jsonDecodeMap(json));
    expect(r.id, 'in-jh-east-singhbhum');
    expect(r.name, contains('Jamshedpur'));
    expect(r.bbox.minLon, 86.0);
    expect(r.bbox.center.lat, closeTo(22.65, 1e-9));
    expect(r.files['tiles']!.sha256, 'aa');
    expect(r.version, 1);
  });

  test('missing files throws FormatException', () {
    expect(() => Region.fromJson({'id': 'x', 'name': 'y', 'bbox': [0,0,1,1], 'version': 1}),
        throwsFormatException);
  });
}
```
(Provide a tiny `jsonDecodeMap` helper in the test, or use `dart:convert` `jsonDecode` cast.)

- [ ] **Step 2: Run → fails** (`flutter test test/regions/region_test.dart`) — undefined `Region`.

- [ ] **Step 3: Implement** (`lib/regions/region.dart`)

```dart
import 'dart:convert';
import 'package:offline_navigator/routing/lat_lng.dart';

Map<String, Object?> jsonDecodeMap(String s) => jsonDecode(s) as Map<String, Object?>;

/// A region's geographic extent: [minLon, minLat, maxLon, maxLat].
class RegionBounds {
  const RegionBounds(this.minLon, this.minLat, this.maxLon, this.maxLat);
  final double minLon, minLat, maxLon, maxLat;
  LatLng get center => LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  static RegionBounds fromList(List<Object?> b) =>
      RegionBounds((b[0] as num).toDouble(), (b[1] as num).toDouble(),
                   (b[2] as num).toDouble(), (b[3] as num).toDouble());
}

/// One downloadable file in a region package.
class RegionFile {
  const RegionFile({required this.url, required this.bytes, required this.sha256});
  final String url; final int bytes; final String sha256;
  factory RegionFile.fromJson(Map<String, Object?> j) => RegionFile(
      url: j['url'] as String, bytes: (j['bytes'] as num).toInt(),
      sha256: j['sha256'] as String);
}

/// A downloadable district region (map + routing + search).
class Region {
  const Region({required this.id, required this.name, required this.state,
      required this.bbox, required this.version, required this.files,
      this.installedAt});
  final String id, name, state;
  final RegionBounds bbox;
  final int version;
  final Map<String, RegionFile> files; // keys: tiles, valhalla, admins, search
  final DateTime? installedAt;

  static const requiredFiles = ['tiles', 'valhalla', 'admins', 'search'];

  factory Region.fromJson(Map<String, Object?> j) {
    final filesJson = j['files'];
    if (filesJson is! Map) throw const FormatException('region: missing files');
    final files = <String, RegionFile>{
      for (final e in filesJson.entries)
        e.key as String: RegionFile.fromJson(e.value as Map<String, Object?>),
    };
    for (final k in requiredFiles) {
      if (!files.containsKey(k)) throw FormatException('region: missing file "$k"');
    }
    return Region(
      id: j['id'] as String, name: j['name'] as String,
      state: (j['state'] as String?) ?? '',
      bbox: RegionBounds.fromList(j['bbox'] as List<Object?>),
      version: (j['version'] as num).toInt(), files: files,
      installedAt: (j['installedAt'] as String?) != null
          ? DateTime.parse(j['installedAt'] as String) : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id, 'name': name, 'state': state,
    'bbox': [bbox.minLon, bbox.minLat, bbox.maxLon, bbox.maxLat],
    'version': version,
    'files': {for (final e in files.entries) e.key:
      {'url': e.value.url, 'bytes': e.value.bytes, 'sha256': e.value.sha256}},
    if (installedAt != null) 'installedAt': installedAt!.toIso8601String(),
  };

  Region copyWith({DateTime? installedAt}) => Region(id: id, name: name,
      state: state, bbox: bbox, version: version, files: files,
      installedAt: installedAt ?? this.installedAt);
}
```

- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(regions): Region/RegionBounds/RegionFile models + JSON`.

### Task 2: Region catalog (parse + fetch)

**Files:** Create `lib/regions/region_catalog.dart`; Test `test/regions/region_catalog_test.dart`.

- [ ] Test: `RegionCatalog.parse(jsonString)` returns the list for a valid `{"schemaVersion":1,"regions":[...]}`; throws `FormatException` on a wrong/absent `schemaVersion` or non-list `regions`. Then a fetch test with an injected `http.Client` (package `http`'s `MockClient`) returning the JSON → `fetchCatalog(client, uri)` yields the parsed regions; a 404/non-200 throws a `RegionCatalogException`.
- [ ] Implement:
```dart
// lib/regions/region_catalog.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:offline_navigator/regions/region.dart';

class RegionCatalogException implements Exception {
  const RegionCatalogException(this.message); final String message;
  @override String toString() => 'RegionCatalogException: $message';
}

class RegionCatalog {
  static List<Region> parse(String body) {
    final j = jsonDecode(body);
    if (j is! Map || j['schemaVersion'] != 1) {
      throw const RegionCatalogException('unsupported catalog schema');
    }
    final regions = j['regions'];
    if (regions is! List) throw const RegionCatalogException('catalog: regions not a list');
    return [for (final r in regions) Region.fromJson(r as Map<String, Object?>)];
  }

  static Future<List<Region>> fetch(http.Client client, Uri url) async {
    final res = await client.get(url);
    if (res.statusCode != 200) {
      throw RegionCatalogException('catalog fetch failed (${res.statusCode})');
    }
    return parse(res.body);
  }
}
```
- [ ] Add `http` to `pubspec.yaml` if not present; `crypto` too (Task 4). Run `flutter pub get`.
- [ ] Commit — `feat(regions): catalog parse + fetch`.

### Task 3: Region store (on-device layout, active persistence)

**Files:** Create `lib/regions/region_store.dart`; Test `test/regions/region_store_test.dart`.

- [ ] Test over a temp dir (inject the root path; do NOT call `path_provider` in tests):
  install a region (write `regions/<id>/manifest.json` + dummy files), `installedRegions()` lists it;
  `filesFor(id)` returns the 5 paths (tiles/valhalla/admins/config/search) under `regions/<id>/`;
  `setActive(id)`/`activeRegionId` persists across a new `RegionStore` instance (writes `active.txt`);
  `delete(id)` removes the dir; deleting the active region clears active.
- [ ] Implement: `RegionStore({required String rootPath})` (root = app support dir, injected). A
  production factory `RegionStore.open()` resolves `getApplicationSupportDirectory()`. Methods:
  `Directory regionDir(String id)` → `<root>/regions/<id>`; `RegionFiles filesFor(String id)`
  (a value type with `tiles/valhalla/admins/config/search` absolute paths); `Future<List<Region>>
  installedRegions()` (read each `manifest.json`); `Future<void> install(Region, {required moveFrom})`;
  `Future<void> delete(String id)`; `String? get activeRegionId` / `Future<void> setActive(String?)`
  (persist to `<root>/regions/active.txt`); `Future<Region?> manifest(String id)`.
- [ ] Commit — `feat(regions): on-device store + active-region persistence`.

### Task 4: Region downloader (stream + sha256 + cancel + atomic promote)

**Files:** Create `lib/regions/region_downloader.dart`; Test `test/regions/region_downloader_test.dart`.

- [ ] Test with `http`'s `MockClient`/a fake streamed client returning known bytes:
  download a region whose manifest sha256 matches → files land in `regions/<id>/`, manifest written,
  `onProgress` reports monotonically increasing fractions ending at 1.0; a sha256 mismatch → throws
  `RegionDownloadException` and leaves NO `regions/<id>/` (only a cleaned `.part`); a cancel token
  flips mid-download → throws `RegionDownloadCancelled` and cleans `.part`.
- [ ] Implement: `RegionDownloader(http.Client)`. `Future<void> download(Region r, RegionStore store,
  {void Function(double frac)? onProgress, CancelToken? cancel})`: stream each `RegionFile` to
  `<root>/regions/.part-<id>/<key>`, hashing with `crypto`'s `sha256`; verify each against
  `file.sha256`; sum progress across files by `bytes`; after ALL verify, `store.install(r.copyWith(
  installedAt: now), moveFrom: partDir)` (atomic rename); on any error/cancel delete the `.part` dir.
  `CancelToken` = a tiny `{bool isCancelled; void cancel();}`.
- [ ] Commit — `feat(regions): downloader with progress, sha256 verify, cancel`.

### Task 5: RegionController (orchestration state machine)

**Files:** Create `lib/regions/region_controller.dart`; Test `test/regions/region_controller_test.dart`.

- [ ] Test with fakes (fake store/downloader/catalog injected): `loadInstalled()` populates `installed`
  + `activeRegionId`; `refreshCatalog()` populates `available`; `download(id)` moves it from available→
  installed and emits progress via `notifyListeners`; `setActive(id)` updates active + notifies;
  `delete(activeId)` falls back to the default (`ghatshila`).
- [ ] Implement: `RegionController extends ChangeNotifier` taking `RegionStore`, `RegionDownloader`,
  `RegionCatalog` source (a function returning the catalog), and a `defaultRegionId` (`'ghatshila'`).
  State getters: `List<Region> available`, `List<Region> installed`, `String? activeRegionId`,
  `Map<String,double> progress`, `String? error`. Methods as in the test. Guards: ignore double
  downloads of the same id.
- [ ] Commit — `feat(regions): RegionController state machine`.

---

## Part 2 — Region-aware consumers (expand at execution)

> Each task is expanded into TDD steps at dispatch. Read the current consumer before editing.

- **Task 6 — `TileService` region-aware.** Add `TileService({String? pmtilesPathOverride})` or
  `TileService.forRegion(RegionFiles)`; open `PmTilesReader` from the active region's `tiles.pmtiles`.
  Keep the bundled-asset copy as the **seed of the default `ghatshila` region** (move the asset copy
  into a `seedDefaultRegion()` that writes into `regions/ghatshila/`). Add `restartForRegion(RegionFiles)`
  that stops the server and reopens on the new pmtiles. Tests: server serves a region pmtiles from a
  temp path; switching reopens. Existing tile tests stay green via the default seed.
- **Task 7 — `SearchService` region-aware.** `SearchService.openForRegion(String dbPath)`; default seeds
  `regions/ghatshila/search.sqlite` from the bundled asset. Existing search tests use `forTesting(db)`,
  unaffected. Test open-from-path.
- **Task 8 — Routing region-aware.** `ValhallaRoutingService` learns the active region dir; the
  MethodChannel `ensureReady`/`route` accept a `regionDir` (the plugin constructs/swaps a per-dir
  `ValhallaActor`, keyed by dir, re-init on change). Default = `regions/ghatshila/`. `ValhallaPlugin.kt`:
  `ensureReady(regionDir)` copies/extracts there if needed (downloaded regions already have the files,
  so only write `valhalla.json` from the template with `__APPDIR__`→regionDir); cache actors per dir.
  Dart tests: request/parse unchanged; region-dir selection unit-tested.
- **Task 9 — `MapScreen` + default seeding.** Own a `RegionController`; on first run seed the default
  Ghatshila region from bundled assets; on `setActive`, rebuild tile server + search + routing for the
  new region and `animateCamera` to `region.bbox.center` (+ a fit zoom). A Settings entry point
  (top-left, near search FAB). Keep existing widget tests green (`autoStart:false` path unchanged).

---

## Part 3 — Settings + Download UI (expand at execution)

- **Task 10 — `RegionManagerScreen`** (`lib/regions/region_manager_screen.dart`). A list from
  `RegionController.available`+`installed`: each row shows name, size (sum of `files.bytes`), and a
  trailing control — Download (→ progress bar via `progress[id]`), or Installed (Active badge + switch +
  Delete). Pull-to-refresh calls `refreshCatalog()`; an error banner on `controller.error`. Widget test
  with a fake controller: renders available + installed, tapping Download calls `controller.download`,
  progress shows, Activate/Delete wired. Keys: `regionRow-<id>`, `downloadRegion-<id>`,
  `activateRegion-<id>`, `deleteRegion-<id>`, `regionProgress-<id>`.
- **Task 11 — Settings screen + entry point.** `SettingsScreen` (`lib/settings/settings_screen.dart`)
  with a "Download regions" tile → `RegionManagerScreen`, plus app version (reuse `package_info_plus`).
  Add a `settingsButton` FAB/icon on the map (top-left cluster). Widget test: button opens settings;
  settings shows the regions tile.

---

## Part 4 — Data generation + hosting (Docker, here)

- **Task 12 — `tool/generate_region.sh <id> <S> <W> <N> <E>`.** Generalize the existing scripts to any
  bbox, sourcing OSM from a **Geofabrik Jharkhand `.osm.pbf`** (download once, cache; `osmium extract`
  the bbox) instead of Overpass. Produce `<id>.pmtiles` (pmtiles extract — install `pmtiles` first or
  run via Docker), `<id>.valhalla.tar` + `<id>.admins.sqlite` (Valhalla Docker over the bbox pbf),
  `<id>.search.sqlite` (osmium tags → `build_search_index.py`). Print per-file size + sha256. Verify a
  Docker test route INSIDE the district returns status 0 with a road-following polyline.
- **Task 13 — Catalog + publish.** `tool/build_region_catalog.py` assembles `regions.json` from the
  generated files' sizes/sha256 + the GitHub Release asset URLs. Generate **East Singhbhum** first
  (bbox covering Ghatshila), `gh release create regions-v1` (or reuse), upload assets + `regions.json`
  to `Drake0306/offline-navigator`. Wire the app's catalog URL to the released `regions.json`. Then
  device-verify the full loop; batch the remaining districts as disk allows.

---

## Self-review

**Spec coverage:** models/catalog/store/downloader/controller → Part 1 (Tasks 1–5); region-aware
tiles/routing/search + map switch + default seed → Part 2 (Tasks 6–9); Settings + download UI → Part 3
(Tasks 10–11); Geofabrik+Docker generation, catalog, GitHub Releases publish → Part 4 (Tasks 12–13). ✓
**Type consistency:** `Region{id,name,state,bbox(RegionBounds),version,files(Map<String,RegionFile>),
installedAt}`, `RegionFiles{tiles,valhalla,admins,config,search}`, `RegionStore{regionDir,filesFor,
installedRegions,install,delete,activeRegionId,setActive,manifest}`, `RegionDownloader.download(Region,
RegionStore,{onProgress,cancel})`, `RegionController{available,installed,activeRegionId,progress,error,
loadInstalled,refreshCatalog,download,cancel,delete,setActive}` — used consistently across parts.
**Deps:** add `http` + `crypto` (Part 1); `pmtiles` CLI (Part 4, dev-only).
**Device-only:** live render/route/search per region + the download UX → user verifies (Part 4 close-out).
