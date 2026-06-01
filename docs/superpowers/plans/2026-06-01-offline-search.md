# Offline Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fully-offline destination search — a build-time pipeline extracts named places/POIs/roads/water for the Ghatshila bbox from raw OpenStreetMap into a bundled SQLite DB (normalized, indexed `search` column); on-device a full-screen search page does search-as-you-type ranked nearest-first; selecting a result centers the map and drops a destination marker + info card.

**Architecture:** A build-time script (`tool/generate_search_index`) clips a Jharkhand `.osm.pbf` to the bbox with `osmium`, extracts named features with `pyosmium`, and writes `assets/search/ghatshila.sqlite` (a `features` table with a normalized `search` column + index). At runtime, `SearchService` copies the DB to storage (version-stamped, like tiles), opens it via `sqflite`, and runs `LIKE 'term%'` prefix queries ranked by haversine distance from the user (text relevance as tiebreak). `SearchScreen` (full-screen) drives search-as-you-type with a 200ms debounce; `MapScreen` gets a search icon and, on a returned result, animates the camera and drops a `destination` GeoJSON marker reusing the user-pointer's source/layer + ready-guard pattern.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `sqflite` (runtime SQLite) + `sqflite_common_ffi` (dev — temp DB in unit tests on the VM/macOS), `geolocator` (origin for ranking), existing MapLibre/shelf stack. Build-time: `osmium-tool` + `pyosmium` (Python) + the local `sqlite3`. Package name: `offline_navigator`.

---

## Conventions & ground rules

- **TDD for pure logic** (`normalize`, `SearchResult` distance, `SearchService` ranking against a seeded temp DB). Widget pieces get widget tests; on-device behavior is manual.
- **Verify before claiming green:** run `flutter analyze` and `flutter test` and read the ACTUAL final output line before saying a task passes or committing. Never commit with analyzer issues or failing tests.
- **Commit after each task** with the message in its final step. Run commands from repo root `/Users/roy/Developer/Github/offline_map`.
- **No device** in the build env (only macOS/Chrome). Per-task acceptance = analyze clean + tests pass; the user runs on-device.

### Verified facts (from the installed toolchain / pub.dev)
- `sqflite` `openDatabase(String path, {bool? readOnly, int? version, OnDatabaseCreateFn? onCreate, ...})`; `db.rawQuery(String sql, [List<Object?>? args]) → Future<List<Map<String,Object?>>>`; `getDatabasesPath() → Future<String>`. We open the copied DB with `readOnly: true`.
- `sqflite_common_ffi`: `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` then `openDatabase(path)` works on the Dart VM / macOS — used ONLY in unit tests.
- Local `sqlite3` CLI is 3.45 (build-time DB creation); `brew` is available to install `osmium-tool`; `pyosmium` installs via `pip`. Disk has ~17 GB free (a Jharkhand pbf is ~50–150 MB).
- `MapLibreMap`/`StyleController` from maplibre 0.3.5: `addImage(id, Uint8List)`, `addSource(GeoJsonSource(id:, data:))`, `addLayer(SymbolStyleLayer(id:, sourceId:, layout:{...}))`, `updateGeoJsonSource(id:, data:)`; camera `animateCamera(center: Geographic(lon:, lat:), zoom:)`. `onStyleLoaded` re-fires on `setStyle` and clears added layers — so any marker source/layer must be re-added and guarded by a `…SourceReady` flag (same pattern as the user pointer).

### name_en policy
Use OSM `name:en` when the feature has it; otherwise leave `name_en` empty. We do NOT transliterate Devanagari→Latin (fragile). The normalized `search` column always includes the local-script `name`, and `name_en` when present — so English queries match features that carry `name:en`, and local-script queries match everything.

---

## File structure

```
tool/generate_search_index.sh         NEW  orchestrates: download/clip pbf → run extractor → build sqlite
tool/extract_features.py               NEW  pyosmium handler → emits rows (name,name_en,kind,lat,lon)
assets/search/ghatshila.sqlite         NEW  bundled search DB (generator output, committed)
lib/search/search_result.dart          NEW  SearchResult model + haversine
lib/search/text_normalize.dart         NEW  normalize() shared by build-time intent & runtime queries
lib/search/search_service.dart         NEW  copy+open DB, query+rank
lib/map/destination_marker.dart        NEW  GeoJSON helpers for the destination pin (mirror user_pointer)
lib/search/search_screen.dart          NEW  full-screen search UI (debounced, live results)
lib/map/map_screen.dart                MOD  search icon → SearchScreen; drop destination marker + info card
pubspec.yaml                           MOD  add sqflite, sqflite_common_ffi (dev), register assets/search/
test/search/text_normalize_test.dart   NEW
test/search/search_result_test.dart    NEW
test/search/search_service_test.dart   NEW  (seeds a temp DB via ffi)
test/search/search_screen_test.dart    NEW  (mocked service)
test/map/map_screen_test.dart          MOD  (search icon present + navigates)
README.md                              MOD  manual checklist + regenerate-search-index docs
```

---

## Task 0: Install build-time OSM tooling

**Why:** the search index is built from raw OSM; `osmium-tool` and `pyosmium` aren't installed. (Build-time only — not app deps.)

**Files:** none (environment).

- [ ] **Step 1: Install osmium-tool**

Run: `brew install osmium-tool` then `osmium --version`.
Expected: prints a version (≥ 1.14).

- [ ] **Step 2: Install pyosmium**

Run: `python3 -m pip install --user osmium` then `python3 -c "import osmium; print(osmium.version.pyosmium_release)"`.
Expected: prints a version (e.g. 3.x/4.x). If `pip` is restricted, use `pipx`/a venv; record what worked.

- [ ] **Step 3: Confirm sqlite3 + FTS-free build works**

Run: `sqlite3 --version`.
Expected: ≥ 3.x. (We only use plain tables + an index + `LIKE`, so no extension needed.)

No commit (environment only).

---

## Task 1: Build the Ghatshila search index

**Files:**
- Create: `tool/extract_features.py`
- Create: `tool/generate_search_index.sh`
- Create (output, committed): `assets/search/ghatshila.sqlite`
- Modify: `pubspec.yaml` (register `assets/search/`)

- [ ] **Step 1: Write the pyosmium extractor**

Create `tool/extract_features.py`:
```python
#!/usr/bin/env python3
"""Extract named features (places/POIs/roads/water) from an OSM .pbf within a
bbox into a SQLite DB with a normalized, indexed `search` column.

Usage: python3 tool/extract_features.py <input.osm.pbf> <output.sqlite>
"""
import sys, sqlite3, unicodedata, re
import osmium

# OSM tag → our coarse `kind`. We keep only features that have a name.
def classify(tags):
    if 'place' in tags:
        return 'place'
    if 'highway' in tags and tags.get('highway') not in ('footway', 'path', 'steps'):
        return 'road'
    if tags.get('natural') in ('water',) or 'water' in tags or tags.get('waterway'):
        return 'water'
    # POIs: a broad set of "has a useful name" amenity-like tags.
    for k in ('amenity', 'shop', 'tourism', 'leisure', 'office', 'healthcare',
              'aeroway', 'railway', 'public_transport'):
        if k in tags:
            return 'poi'
    return None

def normalize(s):
    if not s:
        return ''
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    s = re.sub(r'\s+', ' ', s).strip()
    return s

class Handler(osmium.SimpleHandler):
    def __init__(self, rows):
        super().__init__()
        self.rows = rows

    def _add(self, tags, lat, lon):
        name = tags.get('name')
        if not name or lat is None or lon is None:
            return
        kind = classify(tags)
        if kind is None:
            return
        name_en = tags.get('name:en', '')
        search = (normalize(name) + ' ' + normalize(name_en)).strip()
        self.rows.append((name, name_en, kind, lat, lon, search))

    def node(self, n):
        if n.location.valid():
            self._add(dict(n.tags), n.location.lat, n.location.lon)

    def area(self, a):
        # Centroid for named areas (buildings/water/landuse polygons with names).
        try:
            # osmium provides envelope; use its center as a cheap representative point.
            env = a.envelope()
            lat = (env.bottom_left.lat + env.top_right.lat) / 2
            lon = (env.bottom_left.lon + env.top_right.lon) / 2
        except Exception:
            return
        self._add(dict(a.tags), lat, lon)

    def way(self, w):
        # Named roads: take the midpoint node of the way if locations are present.
        if 'name' not in w.tags:
            return
        try:
            nodes = [nd.location for nd in w.nodes if nd.location.valid()]
            if not nodes:
                return
            mid = nodes[len(nodes) // 2]
            self._add(dict(w.tags), mid.lat, mid.lon)
        except Exception:
            return

def main():
    src, out = sys.argv[1], sys.argv[2]
    rows = []
    # locations=True so ways/areas have node coordinates.
    Handler(rows).apply_file(src, locations=True)
    # Dedupe identical (name,kind,rounded-coord) rows.
    seen = set()
    deduped = []
    for r in rows:
        key = (r[5], r[2], round(r[3], 5), round(r[4], 5))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(r)
    db = sqlite3.connect(out)
    db.execute('DROP TABLE IF EXISTS features')
    db.execute('''CREATE TABLE features(
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_en TEXT,
        kind TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
        search TEXT NOT NULL)''')
    db.executemany(
        'INSERT INTO features(name,name_en,kind,lat,lon,search) VALUES (?,?,?,?,?,?)',
        deduped)
    db.execute('CREATE INDEX idx_features_search ON features(search)')
    db.commit()
    n = db.execute('SELECT count(*) FROM features').fetchone()[0]
    db.close()
    print(f'wrote {out}: {n} features')

if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Write the orchestration script**

Create `tool/generate_search_index.sh`:
```bash
#!/usr/bin/env bash
# Build assets/search/ghatshila.sqlite from a Jharkhand OSM extract clipped to
# the Ghatshila bbox. Requires: osmium (brew install osmium-tool),
# pyosmium (pip install osmium), python3.
#
# Usage: tool/generate_search_index.sh
set -euo pipefail

BBOX="86.35,22.45,86.65,22.75"   # lon_min,lat_min,lon_max,lat_max — matches the tile pack
WORK="$(mktemp -d)"
SRC_URL="https://download.geofabrik.de/asia/india/jharkhand-latest.osm.pbf"
RAW="$WORK/jharkhand.osm.pbf"
CLIP="$WORK/ghatshila.osm.pbf"
OUT="assets/search/ghatshila.sqlite"

mkdir -p assets/search
echo "Downloading Jharkhand extract..."
curl -fL "$SRC_URL" -o "$RAW"
echo "Clipping to bbox $BBOX ..."
osmium extract --bbox "$BBOX" --set-bounds -o "$CLIP" "$RAW"
echo "Extracting named features into $OUT ..."
python3 tool/extract_features.py "$CLIP" "$OUT"
rm -rf "$WORK"
echo "Done. Feature count:"
sqlite3 "$OUT" "SELECT kind, count(*) FROM features GROUP BY kind;"
```

- [ ] **Step 3: Run it**

Run: `chmod +x tool/generate_search_index.sh && tool/generate_search_index.sh`
Expected: downloads the pbf, clips, and prints a per-kind feature count (place/poi/road/water) and a total > 0. `assets/search/ghatshila.sqlite` exists (a few hundred KB to a few MB). If Geofabrik's URL/path changed, update `SRC_URL` to the current Jharkhand extract URL and rerun.

- [ ] **Step 4: Sanity-check the DB**

Run:
```bash
sqlite3 assets/search/ghatshila.sqlite \
  "SELECT name, kind, round(lat,4), round(lon,4) FROM features WHERE search LIKE 'ghat%' LIMIT 5;"
```
Expected: returns Ghatshila (and similar) rows — confirms the normalized `search` column + `LIKE` works and the area is covered. If zero rows for `ghat%`, widen the check (`LIKE '%ghat%'`) and confirm the bbox actually contains Ghatshila.

- [ ] **Step 5: Register the asset**

In `pubspec.yaml`, under `flutter: assets:`, add `- assets/search/`. Run `flutter pub get` → clean resolve.

- [ ] **Step 6: Commit**

```bash
git add tool/extract_features.py tool/generate_search_index.sh assets/search/ghatshila.sqlite pubspec.yaml
git commit -m "feat: build bundled Ghatshila offline search index (osmium + pyosmium → sqlite)"
```

---

## Task 2: text normalize() (pure, TDD)

**Files:**
- Create: `lib/search/text_normalize.dart`
- Test: `test/search/text_normalize_test.dart`

The runtime `normalize()` MUST match the Python build-time `normalize()` so query patterns match stored values: NFKD decompose, drop combining marks, lowercase, collapse whitespace, trim.

- [ ] **Step 1: Write the failing test**

Create `test/search/text_normalize_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/search/text_normalize.dart';

void main() {
  test('lowercases and trims/collapses whitespace', () {
    expect(normalizeSearch('  Ghatshila  Town '), 'ghatshila town');
  });

  test('strips diacritics', () {
    expect(normalizeSearch('Galudīh'), 'galudih');
    expect(normalizeSearch('Café'), 'cafe');
  });

  test('empty/whitespace → empty', () {
    expect(normalizeSearch(''), '');
    expect(normalizeSearch('   '), '');
  });

  test('non-latin script is preserved (lowercased/trimmed only)', () {
    // Devanagari has no case; normalization should keep the characters.
    expect(normalizeSearch(' घाटशिला '), 'घाटशिला');
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/search/text_normalize_test.dart`
Expected: FAIL — `normalizeSearch` undefined.

- [ ] **Step 3: Implement**

Create `lib/search/text_normalize.dart`:
```dart
import 'dart:core';

/// Normalizes text for offline search matching. MUST stay in sync with the
/// build-time `normalize()` in tool/extract_features.py: NFKD-decompose, drop
/// combining marks (diacritics), lowercase, collapse whitespace, trim.
///
/// Dart's String has no built-in NFKD, so we strip the common Latin combining
/// diacritical marks (U+0300–U+036F) after lowercasing. Scripts without case
/// or combining marks (e.g. Devanagari) pass through unchanged except for
/// whitespace/casing — matching the Python side for the names we index.
String normalizeSearch(String input) {
  if (input.trim().isEmpty) return '';
  final lowered = input.toLowerCase();
  // Remove combining diacritical marks.
  final stripped = lowered.replaceAll(RegExp(r'[̀-ͯ]'), '');
  // Also fold the most common precomposed Latin accents that don't decompose
  // via the regex above (é, ï, etc. are single code points in Dart strings).
  final folded = _foldLatin(stripped);
  return folded.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _latinFolds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ō': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'ñ': 'n', 'ç': 'c',
};

String _foldLatin(String s) {
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    sb.write(_latinFolds[ch] ?? ch);
  }
  return sb.toString();
}
```
Note: the precomposed-accent fold (`Galudīh`→`galudih`, `Café`→`cafe`) covers the common cases the test asserts. The Python side uses full NFKD; for ASCII/Latin names the two agree, which is what matters for matching English queries.

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/search/text_normalize_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/search/text_normalize.dart test/search/text_normalize_test.dart
git commit -m "feat: add normalizeSearch() shared text normalization (tested)"
```

---

## Task 3: SearchResult model + haversine (pure, TDD)

**Files:**
- Create: `lib/search/search_result.dart`
- Test: `test/search/search_result_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/search/search_result_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/search/search_result.dart';

void main() {
  test('haversine distance between two known points (~1.11 km per 0.01° lat)', () {
    // 0.01 degrees of latitude ≈ 1.111 km anywhere.
    final d = SearchResult.distanceMeters(22.586, 86.476, 22.596, 86.476);
    expect(d, closeTo(1111, 30));
  });

  test('zero distance for identical points', () {
    final d = SearchResult.distanceMeters(22.586, 86.476, 22.586, 86.476);
    expect(d, closeTo(0, 1e-6));
  });

  test('withDistanceFrom fills distanceM', () {
    const r = SearchResult(name: 'X', kind: 'place', lat: 22.596, lng: 86.476);
    final r2 = r.withDistanceFrom(22.586, 86.476);
    expect(r2.distanceM, closeTo(1111, 30));
    expect(r2.name, 'X');
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/search/search_result_test.dart`
Expected: FAIL — `SearchResult` undefined.

- [ ] **Step 3: Implement**

Create `lib/search/search_result.dart`:
```dart
import 'dart:math' as math;

/// A single offline-search hit. Immutable. [distanceM] is filled once an origin
/// is known (GPS fix or map center).
class SearchResult {
  const SearchResult({
    required this.name,
    required this.kind,
    required this.lat,
    required this.lng,
    this.nameEn,
    this.distanceM,
  });

  final String name;
  final String? nameEn;
  final String kind; // 'place' | 'poi' | 'road' | 'water'
  final double lat;
  final double lng;
  final double? distanceM;

  SearchResult withDistanceFrom(double originLat, double originLng) =>
      SearchResult(
        name: name,
        nameEn: nameEn,
        kind: kind,
        lat: lat,
        lng: lng,
        distanceM: distanceMeters(originLat, originLng, lat, lng),
      );

  /// Great-circle distance in metres (haversine).
  static double distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earth = 6371000.0; // metres
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/search/search_result_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/search/search_result.dart test/search/search_result_test.dart
git commit -m "feat: add SearchResult model with haversine distance (tested)"
```

---

## Task 4: SearchService — query + rank (TDD via ffi temp DB)

**Files:**
- Modify: `pubspec.yaml` (add `sqflite`, dev `sqflite_common_ffi`)
- Create: `lib/search/search_service.dart`
- Test: `test/search/search_service_test.dart`

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml` dependencies add `sqflite: ^2.4.1`. In dev_dependencies add `sqflite_common_ffi: ^2.3.3`. Run `flutter pub get` → clean resolve.

- [ ] **Step 2: Write the failing test (seeds a temp DB via ffi)**

Create `test/search/search_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_navigator/search/search_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<SearchService> seeded() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE features(
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_en TEXT,
      kind TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
      search TEXT NOT NULL)''');
    await db.execute('CREATE INDEX idx_features_search ON features(search)');
    Future<void> ins(String name, String? en, String kind, double lat,
            double lon, String search) =>
        db.insert('features', {
          'name': name, 'name_en': en, 'kind': kind,
          'lat': lat, 'lon': lon, 'search': search,
        });
    // Two "ghatshila"-ish rows at different distances + an unrelated row.
    await ins('Ghatshila', 'Ghatshila', 'place', 22.586, 86.476, 'ghatshila ghatshila');
    await ins('Ghatshila Station', 'Ghatshila Station', 'poi', 22.600, 86.470,
        'ghatshila station ghatshila station');
    await ins('Galudih', 'Galudih', 'place', 22.560, 86.700, 'galudih galudih');
    // A Devanagari-named row with name_en empty (matches only local script).
    await ins('घाटशिला', '', 'place', 22.590, 86.480, 'घाटशिला');
    return SearchService.forTesting(db);
  }

  test('prefix LIKE matches and ranks nearest-first from origin', () async {
    final s = await seeded();
    final res = await s.query('ghat', originLat: 22.586, originLng: 86.476);
    expect(res.length, 2);
    // Ghatshila (0 km) before Ghatshila Station (~1.8 km).
    expect(res.first.name, 'Ghatshila');
    expect(res[1].name, 'Ghatshila Station');
    expect(res.first.distanceM, lessThan(res[1].distanceM!));
  });

  test('non-matching query returns empty', () async {
    final s = await seeded();
    expect((await s.query('zzz', originLat: 22.586, originLng: 86.476)), isEmpty);
  });

  test('empty query returns empty without hitting the db', () async {
    final s = await seeded();
    expect((await s.query('   ', originLat: 22.586, originLng: 86.476)), isEmpty);
  });

  test('local-script query matches the Devanagari row', () async {
    final s = await seeded();
    final res = await s.query('घाट', originLat: 22.586, originLng: 86.476);
    expect(res.map((r) => r.name), contains('घाटशिला'));
  });

  test('respects the limit', () async {
    final s = await seeded();
    final res = await s.query('ghat', originLat: 22.586, originLng: 86.476, limit: 1);
    expect(res.length, 1);
  });
}
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `flutter test test/search/search_service_test.dart`
Expected: FAIL — `SearchService` undefined.

- [ ] **Step 4: Implement**

Create `lib/search/search_service.dart`:
```dart
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:offline_navigator/search/search_result.dart';
import 'package:offline_navigator/search/text_normalize.dart';

/// Bump when the bundled search DB changes so storage is refreshed.
const String kSearchDbVersion = '1';
const String _kAsset = 'assets/search/ghatshila.sqlite';

/// Offline place search over a bundled SQLite DB (normalized `search` column,
/// queried with LIKE — no FTS5, so it works on every Android/SQLite version).
class SearchService {
  SearchService._(this._db);

  /// Production constructor: copy the bundled DB to storage, open read-only.
  static Future<SearchService> open() async {
    final dir = await getApplicationSupportDirectory();
    final dest = p.join(dir.path, 'search', 'ghatshila.sqlite');
    final stamp = File(p.join(dir.path, 'search', '.db_version'));
    final needsCopy = !await File(dest).exists() ||
        !await stamp.exists() ||
        (await stamp.readAsString()).trim() != kSearchDbVersion;
    if (needsCopy) {
      final bytes = await rootBundle.load(_kAsset);
      final f = File(dest);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await stamp.writeAsString(kSearchDbVersion);
    }
    final db = await openDatabase(dest, readOnly: true);
    return SearchService._(db);
  }

  /// Test constructor: use an already-open database.
  @visibleForTesting
  factory SearchService.forTesting(Database db) = SearchService._;

  final Database _db;

  /// Returns up to [limit] results whose normalized name starts with, or
  /// contains a word starting with, the normalized [text]; ranked by distance
  /// from (originLat, originLng) ascending, then by match quality (prefix
  /// before mid-word).
  Future<List<SearchResult>> query(
    String text, {
    required double originLat,
    required double originLng,
    int limit = 30,
  }) async {
    final norm = normalizeSearch(text);
    if (norm.isEmpty) return const [];
    final prefix = '$norm%';
    final word = '% $norm%';
    final rows = await _db.rawQuery(
      'SELECT name, name_en, kind, lat, lon, search FROM features '
      'WHERE search LIKE ? OR search LIKE ? LIMIT ?',
      [prefix, word, limit * 4], // over-fetch, then distance-rank + trim
    );
    final results = rows.map((r) {
      final res = SearchResult(
        name: r['name'] as String,
        nameEn: (r['name_en'] as String?)?.isEmpty ?? true
            ? null
            : r['name_en'] as String,
        kind: r['kind'] as String,
        lat: (r['lat'] as num).toDouble(),
        lng: (r['lon'] as num).toDouble(),
      ).withDistanceFrom(originLat, originLng);
      final isPrefix = (r['search'] as String).startsWith(norm);
      return (res: res, isPrefix: isPrefix);
    }).toList();
    // Sort: nearest first; tiebreak prefix-matches above mid-word matches.
    results.sort((a, b) {
      final d = a.res.distanceM!.compareTo(b.res.distanceM!);
      if (d != 0) return d;
      if (a.isPrefix != b.isPrefix) return a.isPrefix ? -1 : 1;
      return 0;
    });
    return results.take(limit).map((e) => e.res).toList();
  }

  Future<void> dispose() => _db.close();
}
```
Add the missing import for `@visibleForTesting`: at the top add `import 'package:flutter/foundation.dart' show visibleForTesting;` (or `import 'package:meta/meta.dart';`). Use whichever resolves cleanly under `flutter analyze`.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `flutter test test/search/search_service_test.dart`
Expected: PASS (5 tests). If the distance ordering assertion is off, double-check the seeded coordinates produce the intended ordering.

- [ ] **Step 6: Whole-project analyze + test**

Run: `flutter analyze` → "No issues found!"; `flutter test` → all pass.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml lib/search/search_service.dart test/search/search_service_test.dart
git commit -m "feat: add SearchService (LIKE query + distance ranking, tested via ffi)"
```

---

## Task 5: Destination marker helpers (pure, TDD)

**Files:**
- Create: `lib/map/destination_marker.dart`
- Test: `test/map/destination_marker_test.dart`

Mirrors `UserPointer` but for the search destination pin.

- [ ] **Step 1: Write the failing test**

Create `test/map/destination_marker_test.dart`:
```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/map/destination_marker.dart';

void main() {
  test('featureJson encodes [lng,lat] point', () {
    final fc = jsonDecode(DestinationMarker.featureJson(22.5, 86.4));
    final f = fc['features'][0];
    expect(f['geometry']['coordinates'], [86.4, 22.5]);
  });

  test('emptyJson has no features', () {
    final fc = jsonDecode(DestinationMarker.emptyJson());
    expect(fc['features'], isEmpty);
  });

  test('stable ids', () {
    expect(DestinationMarker.sourceId, 'destination');
    expect(DestinationMarker.layerId, 'destination-pin');
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/map/destination_marker_test.dart`
Expected: FAIL — `DestinationMarker` undefined.

- [ ] **Step 3: Implement**

Create `lib/map/destination_marker.dart`:
```dart
import 'dart:convert';

/// GeoJSON + style ids for the search destination pin. Mirrors UserPointer so
/// the marker is re-added across style swaps with the same ready-guard pattern.
class DestinationMarker {
  static const sourceId = 'destination';
  static const layerId = 'destination-pin';

  static String featureJson(double lat, double lng) => jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': const <String, dynamic>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [lng, lat],
            },
          }
        ],
      });

  static String emptyJson() =>
      jsonEncode({'type': 'FeatureCollection', 'features': <dynamic>[]});
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/map/destination_marker_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/map/destination_marker.dart test/map/destination_marker_test.dart
git commit -m "feat: add DestinationMarker GeoJSON helpers (tested)"
```

---

## Task 6: SearchScreen — full-screen search UI

**Files:**
- Create: `lib/search/search_screen.dart`
- Test: `test/search/search_screen_test.dart`

- [ ] **Step 1: Implement the screen**

Create `lib/search/search_screen.dart`:
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:offline_navigator/search/search_result.dart';

/// Abstraction so the screen can be tested without a real DB.
abstract class SearchQuerier {
  Future<List<SearchResult>> query(String text,
      {required double originLat, required double originLng, int limit});
}

/// Full-screen offline search. Debounces input, shows live results, and pops
/// the chosen [SearchResult] (or null if cancelled).
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.querier,
    required this.originLat,
    required this.originLng,
  });

  final SearchQuerier querier;
  final double originLat;
  final double originLng;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _seq = 0; // drop stale in-flight results
  List<SearchResult> _results = const [];
  bool _error = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(text));
  }

  Future<void> _run(String text) async {
    final seq = ++_seq;
    try {
      final r = await widget.querier.query(
        text,
        originLat: widget.originLat,
        originLng: widget.originLng,
        limit: 30,
      );
      if (!mounted || seq != _seq) return; // a newer query superseded this one
      setState(() {
        _results = r;
        _error = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = true);
    }
  }

  String _distanceLabel(double? m) {
    if (m == null) return '';
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('searchField'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search places, POIs, roads…',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _error
          ? const Center(
              key: Key('searchError'),
              child: Text('Search unavailable.'),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final r = _results[i];
                return ListTile(
                  key: Key('result-$i'),
                  leading: Icon(_iconFor(r.kind)),
                  title: Text(r.name),
                  subtitle: Text(r.kind),
                  trailing: Text(_distanceLabel(r.distanceM)),
                  onTap: () => Navigator.pop<SearchResult>(context, r),
                );
              },
            ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
        'place' => Icons.location_city,
        'poi' => Icons.place,
        'road' => Icons.alt_route,
        'water' => Icons.water,
        _ => Icons.location_on,
      };
}
```

- [ ] **Step 2: Write a widget test (mocked querier)**

Create `test/search/search_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/search/search_result.dart';
import 'package:offline_navigator/search/search_screen.dart';

class _FakeQuerier implements SearchQuerier {
  _FakeQuerier(this.results, {this.fail = false});
  final List<SearchResult> results;
  final bool fail;
  @override
  Future<List<SearchResult>> query(String text,
      {required double originLat, required double originLng, int limit = 30}) async {
    if (fail) throw Exception('boom');
    if (text.trim().isEmpty) return const [];
    return results;
  }
}

void main() {
  testWidgets('typing shows results and tapping pops the chosen one',
      (tester) async {
    const hit = SearchResult(
        name: 'Ghatshila', kind: 'place', lat: 22.586, lng: 86.476, distanceM: 0);
    SearchResult? popped;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            popped = await Navigator.push<SearchResult>(
              ctx,
              MaterialPageRoute(
                builder: (_) => SearchScreen(
                  querier: _FakeQuerier(const [hit]),
                  originLat: 22.586,
                  originLng: 86.476,
                ),
              ),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('searchField')), 'ghat');
    await tester.pump(const Duration(milliseconds: 250)); // debounce
    await tester.pump(); // rebuild with results

    expect(find.text('Ghatshila'), findsOneWidget);
    await tester.tap(find.byKey(const Key('result-0')));
    await tester.pumpAndSettle();
    expect(popped?.name, 'Ghatshila');
  });

  testWidgets('error state renders when the querier throws', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(
        querier: _FakeQuerier(const [], fail: true),
        originLat: 0,
        originLng: 0,
      ),
    ));
    await tester.enterText(find.byKey(const Key('searchField')), 'x');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byKey(const Key('searchError')), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the tests**

Run: `flutter test test/search/search_screen_test.dart`
Expected: PASS (2 tests). Then `flutter analyze` → clean.

- [ ] **Step 4: Commit**

```bash
git add lib/search/search_screen.dart test/search/search_screen_test.dart
git commit -m "feat: add full-screen SearchScreen with debounced live results (tested)"
```

---

## Task 7: Wire search into MapScreen (icon + destination marker + info card)

**Files:**
- Modify: `lib/map/map_screen.dart`
- Modify: `test/map/map_screen_test.dart`

`SearchService` implements the `SearchQuerier` interface from Task 6 (same method shape) — add `implements SearchQuerier` to `SearchService` so it can be passed directly to `SearchScreen`.

- [ ] **Step 1: Make SearchService satisfy SearchQuerier**

In `lib/search/search_service.dart` add `import 'package:offline_navigator/search/search_screen.dart' show SearchQuerier;` and change the class to `class SearchService implements SearchQuerier`. Its existing `query(text, {required originLat, required originLng, int limit})` already matches the interface signature. Run `flutter analyze lib/search` → clean.

- [ ] **Step 2: Add search state + icon to MapScreen**

In `lib/map/map_screen.dart`:
- Add imports: `import 'package:offline_navigator/search/search_screen.dart';`, `import 'package:offline_navigator/search/search_service.dart';`, `import 'package:offline_navigator/search/search_result.dart';`, `import 'package:offline_navigator/map/destination_marker.dart';`.
- Add fields: `SearchService? _search;`, `SearchResult? _destination;`, `bool _destReady = false;`.
- In `_boot()` (after `_ready` is set) initialize search without blocking the map:
  ```dart
  // Open the offline search DB (non-fatal if it fails — search just shows an error).
  SearchService.open().then((s) {
    if (mounted) _search = s;
  }).catchError((Object e) => debugPrint('Search open failed: $e'));
  ```
- In `dispose()` add `_search?.dispose();`.

- [ ] **Step 3: Add the destination marker setup to _setupPointer**

In `_setupPointer`, AFTER the user-pointer source/layer are added (and before the location block), also register the destination source+layer so it survives style swaps. Add a pin image and an empty source/layer, then reset `_destReady` accordingly:
```dart
      // Destination marker (for search results) — empty until a result is picked.
      await style.addImage(
        'destination-pin-icon',
        (await rootBundle.load('assets/icons/pointer_arrow.png'))
            .buffer
            .asUint8List(),
      );
      await style.addSource(GeoJsonSource(
          id: DestinationMarker.sourceId, data: DestinationMarker.emptyJson()));
      await style.addLayer(SymbolStyleLayer(
        id: DestinationMarker.layerId,
        sourceId: DestinationMarker.sourceId,
        layout: {
          'icon-image': 'destination-pin-icon',
          'icon-size': 0.6,
          'icon-allow-overlap': true,
        },
      ));
      _destReady = true;
      // Re-show an existing destination after a style swap.
      final dest = _destination;
      if (dest != null) {
        style.updateGeoJsonSource(
          id: DestinationMarker.sourceId,
          data: DestinationMarker.featureJson(dest.lat, dest.lng),
        );
      }
```
Note: reuse `pointer_arrow.png` for now as the pin image (a dedicated pin asset can come later — out of scope). In the `catch (e)` of `_setupPointer`, also set `_destReady = false`. At the top of `_setupPointer` where `_pointerSourceReady = false` is handled on swap, also reset `_destReady = false` in `_applyStyle` (where `_pointerSourceReady = false` is set).

- [ ] **Step 4: Add the search icon + open handler + info card**

Add an `_openSearch()` handler:
```dart
  Future<void> _openSearch() async {
    final search = _search;
    if (search == null) return; // DB not ready yet
    final origin = _lastLoc;
    final lat = origin?.lat ?? _center.lat;
    final lng = origin?.lng ?? _center.lon;
    final result = await Navigator.of(context).push<SearchResult>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
            querier: search, originLat: lat, originLng: lng),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _destination = result);
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
```
In `build()`, add a search icon as a `Positioned` top-left (away from the right-side FABs), e.g.:
```dart
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
```
And add a dismissible info card when `_destination != null` (a `Positioned` near the bottom, above the attribution):
```dart
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
```

- [ ] **Step 5: Add a widget test for the search icon**

In `test/map/map_screen_test.dart`, add:
```dart
  testWidgets('search button is present', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen(autoStart: false)));
    await tester.pump();
    expect(find.byKey(const Key('searchButton')), findsOneWidget);
  });
```
(Keep all existing tests. With `autoStart:false`, `_search` is null so tapping is a safe no-op; we only assert presence.)

- [ ] **Step 6: Whole-project analyze + test**

Run: `flutter analyze` → "No issues found!"; `flutter test` → all pass. Fix anything red before committing (watch for the `_destReady` reset in `_applyStyle`, and that `_center.lon`/`.lat` are valid `Geographic` getters).

- [ ] **Step 7: Commit**

```bash
git add lib/map/map_screen.dart lib/search/search_service.dart test/map/map_screen_test.dart
git commit -m "feat: wire offline search into the map (icon, destination marker, info card)"
```

---

## Task 8: Full verification + README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full clean verification**

Run: `flutter analyze` (expect "No issues found!") and `flutter test` (record the `+N: All tests passed!` line). If red, fix before continuing.

- [ ] **Step 2: Update the README**

In `README.md`:
- Top description: mention offline destination search (places/POIs/roads/water) with nearest-first results and a destination marker.
- "Regenerate offline data" section: add `tool/generate_search_index.sh` (requires `osmium-tool` + `pyosmium`) and what it produces.
- Manual acceptance checklist: add steps —
  - Tap the **search icon** (top-left); type a known name (e.g. "Ghatshila", "Galudih"); confirm live nearest-first results with distance labels.
  - Tap a result; confirm the map centers/zooms there, a destination marker drops, and an info card shows; close the card; switch map style and confirm the marker persists.
  - Confirm search works in **airplane mode**.
- Verification status table: bump the test count to the real number; add a "Offline search (on-device)" NOT-YET-VERIFIED row (DB query path is unit-tested via ffi; on-device DB-copy + UI is manual).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document offline search (build pipeline + manual checklist)"
```

---

## Self-review (completed at plan-writing time)

**Spec coverage:**
- Build-time OSM→SQLite index (places/POIs/roads/water, normalized `search` col) → Tasks 0,1. ✓
- `normalize()` shared build/runtime → Task 2 (runtime) + Task 1 (Python build-time twin; sync noted). ✓
- `SearchResult` + haversine → Task 3. ✓
- `SearchService` copy+open+LIKE query+distance-rank, no FTS5 → Task 4. ✓
- Full-screen search, debounced, search-as-you-type, error state → Task 6. ✓
- Search icon → screen; center + destination marker (style-swap-safe) + info card → Tasks 5,7. ✓
- Ranking distance-then-text; map-center fallback when no GPS → Task 4 (logic) + Task 7 (origin selection). ✓
- Offline guarantee (local DB, local sqflite) → Tasks 1,4. ✓
- Testing (normalize, SearchResult, SearchService via ffi, SearchScreen widget, MapScreen icon) → Tasks 2,3,4,6,7. ✓

**Placeholder scan:** No TBD/TODO/"implement later". Every code step has complete code. Task 4 Step 4 notes a choice between two valid imports for `@visibleForTesting` (pick the one that analyzes clean) — a concrete instruction, not a placeholder.

**Type consistency:** `SearchResult{name,nameEn?,kind,lat,lng,distanceM?}` + `distanceMeters`/`withDistanceFrom` consistent across Tasks 3,4,6,7. `SearchQuerier.query(text,{originLat,originLng,limit})` matches `SearchService.query` exactly (Task 4 ↔ 6 ↔ 7). `DestinationMarker.{sourceId,layerId,featureJson,emptyJson}` consistent across Tasks 5,7. `normalizeSearch` consistent Tasks 2,4. `SearchService.open()`/`forTesting(db)`/`dispose()` consistent Tasks 4,7.

**Known on-device-only items (not blockers):** the DB-copy-on-first-launch path and all on-device search UX are verified manually (the query/rank logic is unit-tested via `sqflite_common_ffi`). The build pipeline depends on Geofabrik's current Jharkhand URL and the OSM data having names for the area — both validated in Task 1 Steps 3–4 before committing the DB.
