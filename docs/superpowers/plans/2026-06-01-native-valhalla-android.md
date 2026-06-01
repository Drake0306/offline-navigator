# Native Valhalla Routing on Android — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder `FakeRoutingService` with a real on-device `ValhallaRoutingService` on Android, routing over bundled Ghatshila Valhalla tiles via a MethodChannel to the `valhalla-mobile` AAR — proving real road-following routing runs on the phone.

**Architecture:** Build-time, Valhalla routing tiles for a padded Ghatshila bbox are generated via Docker (already verified to route here) and bundled as `assets/routing/{valhalla_tiles.tar, admins.sqlite, valhalla.json}`. At runtime a Kotlin `ValhallaPlugin` (MethodChannel `offline_navigator/valhalla`) copies the tiles into app storage, writes a `valhalla.json` pointing there, constructs a `ValhallaActor(configPath)`, and answers `route(requestJson)→responseJson`. A Dart `ValhallaRoutingService implements RoutingService` builds the request JSON, calls the channel, and feeds the response into the EXISTING `parseValhallaRoute` (from Part 1). The trip-planner UI is unchanged (it already depends on the `RoutingService` interface).

**Tech Stack:** Flutter 3.44 / Dart 3.12; Android `io.github.rallista:valhalla-mobile:0.1.0` (Kotlin, package `com.valhalla.valhalla`, class `ValhallaActor(configPath:String).route(String):String`); MethodChannel `offline_navigator/valhalla`; Docker `ghcr.io/valhalla/valhalla:latest` + `osmium` (build-time, host). Package name: `offline_navigator`.

---

## Conventions & ground rules

- **TDD for Dart logic** (request-builder, response/error mapping, fallback). The Kotlin handler + AAR is device-only; the tile data is verified in Docker here.
- **Verify before claiming green:** run `flutter analyze` and `flutter test` and read the ACTUAL final line before saying a task passes or committing. Never commit with analyzer issues or failing tests.
- **Commit after each task.** Run commands from repo root `/Users/roy/Developer/Github/offline_map`.
- **No mobile device / Java / full Xcode in the dev env.** So: Dart + tile generation are verified here; the Android Gradle build + the on-device route are the USER's step (this plan writes the Kotlin/Gradle but cannot compile it here — say so honestly).

### VERIFIED facts (generated + tested live during planning — use these exact commands/values)
- **The tile pipeline WORKS.** Running the Docker steps below for the padded Ghatshila bbox produced `valhalla_tiles.tar` (4.8 MB), `admins.sqlite` (6.7 MB), `valhalla.json` (9.4 KB), and a one-shot route **Ghatshila(22.586,86.476)→(22.593,86.515)** returned `status:0 "Found route between points"`, 5.691 km / 501 s, 1 leg / 7 maneuvers, a 943-char road-following polyline. This is the exact `trip{...}` shape `parseValhallaRoute` handles.
- **Binaries** in `ghcr.io/valhalla/valhalla:latest` (3.7.0): `valhalla_build_config`, `valhalla_build_admins`, `valhalla_build_tiles`, `valhalla_build_extract`. There is **NO `valhalla_run_route`** — verify routes with `valhalla_service <config> route <json>` (one-shot mode).
- **Config keys** the native side must rewrite to the on-device path: `mjolnir.tile_extract` (the tar), `mjolnir.admin` (admins.sqlite), `mjolnir.tile_dir`. `valhalla_build_config` writes these from its `--mjolnir-*` flags.
- **valhalla-mobile API** (read from source): `ValhallaActor(configPath: String).route(request: String): String`; request `{"locations":[{"lat","lon"}...],"costing":"auto|motorcycle|bicycle|pedestrian","units":"kilometers"}`; success → `{"trip":{...}}`, failure → `{"code":<int>,"message":"..."}`.
- **Existing Part 1 code reused:** `lib/routing/routing_service.dart` (`RoutingService`, `RoutingException`), `lib/routing/route_plan.dart` (`RoutePlan`), `lib/routing/valhalla_parser.dart` (`parseValhallaRoute`), `lib/routing/travel_mode.dart` (`TravelMode` w/ `.costing` = auto/motorcycle/bicycle/pedestrian), `lib/routing/lat_lng.dart` (`LatLng`), `lib/routing/fake_routing_service.dart`. `MapScreen` currently does `final RoutingService _routing = FakeRoutingService();`.

---

## File structure

```
tool/generate_valhalla_tiles.sh           NEW  Docker tile pipeline (host); region-agnostic (bbox arg)
assets/routing/valhalla_tiles.tar         NEW  bundled routing tiles (generator output, committed)
assets/routing/admins.sqlite              NEW  bundled admin db (committed)
assets/routing/valhalla.json              NEW  config template (tile paths are placeholders)
lib/routing/valhalla_request.dart         NEW  build the Valhalla request JSON from points+mode (pure)
lib/routing/valhalla_routing_service.dart NEW  RoutingService impl over the MethodChannel + parser + fallback
android/app/src/main/kotlin/.../ValhallaPlugin.kt   NEW  MethodChannel handler (Kotlin)
android/app/src/main/kotlin/.../MainActivity.kt     MOD  register the plugin
android/app/build.gradle.kts              MOD  add valhalla-mobile dependency
lib/map/map_screen.dart                   MOD  use ValhallaRoutingService (with fallback to fake)
pubspec.yaml                              MOD  register the new routing assets
test/routing/valhalla_request_test.dart   NEW
test/routing/valhalla_routing_service_test.dart NEW (mocked channel)
README.md                                 MOD  native routing build steps + honest scope
```

---

## Task 1: Generate + bundle the Valhalla tiles (Docker, host)

**Files:**
- Create: `tool/generate_valhalla_tiles.sh`
- Create (committed output): `assets/routing/valhalla_tiles.tar`, `assets/routing/admins.sqlite`, `assets/routing/valhalla.json`
- Modify: `pubspec.yaml`

**Prereqs (host):** Docker running, `osmium` installed, `curl`, `python3`. (All verified present in the dev env.)

- [ ] **Step 1: Write the tile pipeline script**

Create `tool/generate_valhalla_tiles.sh`:
```bash
#!/usr/bin/env bash
# Generate bundled Valhalla routing tiles for the (padded) Ghatshila bbox.
# Produces assets/routing/{valhalla_tiles.tar, admins.sqlite, valhalla.json}.
# Requires: docker, osmium, curl, python3. Region-agnostic: edit the bbox to
# retarget; the same pipeline is what a future tile-host server would run.
set -euo pipefail

# Padded ~0.1deg around the map/search bbox so edge roads connect for routing.
S=22.35; W=86.25; N=22.85; E=86.75
IMG="ghcr.io/valhalla/valhalla:latest"
WORK="$(mktemp -d)"
OUT="assets/routing"
mkdir -p "$OUT"

echo "1/4 Fetching road network (Overpass) for ($S,$W,$N,$E) ..."
cat > "$WORK/q.txt" <<OQL
[out:xml][timeout:180];
(
  way["highway"](${S},${W},${N},${E});
  >;
);
out body;
OQL
curl -fsS --max-time 240 -A "offline-navigator-build/1.0" \
  -X POST "https://overpass-api.de/api/interpreter" \
  --data-urlencode "data@$WORK/q.txt" -o "$WORK/region.osm"

echo "2/4 Converting OSM XML -> pbf ..."
osmium cat "$WORK/region.osm" -o "$WORK/region.osm.pbf" -f pbf --overwrite

echo "3/4 Building Valhalla tiles in Docker ..."
docker run --rm -v "$WORK:/work" -w /work "$IMG" bash -lc '
  set -e
  valhalla_build_config \
    --mjolnir-tile-dir /work/valhalla_tiles \
    --mjolnir-tile-extract /work/valhalla_tiles.tar \
    --mjolnir-admin /work/admins.sqlite > /work/valhalla.json
  valhalla_build_admins --config /work/valhalla.json /work/region.osm.pbf
  valhalla_build_tiles  --config /work/valhalla.json /work/region.osm.pbf
  valhalla_build_extract --config /work/valhalla.json -v
'

echo "4/4 Verifying a test route in Docker ..."
docker run --rm -v "$WORK:/work" -w /work "$IMG" bash -lc \
  'valhalla_service /work/valhalla.json route "{\"locations\":[{\"lat\":22.586,\"lon\":86.476},{\"lat\":22.593,\"lon\":86.515}],\"costing\":\"auto\",\"units\":\"kilometers\"}"' \
  > "$WORK/route.json" 2>/dev/null
python3 - "$WORK/route.json" <<'PY'
import sys, json
d = json.load(open(sys.argv[1])); t = d.get('trip', {})
assert t.get('status') == 0, f"route failed: {t.get('status_message')}"
print('  route OK:', t['summary']['length'], 'km,', t['summary']['time'], 's,',
      sum(len(l.get('maneuvers', [])) for l in t['legs']), 'maneuvers')
PY

cp "$WORK/valhalla_tiles.tar" "$WORK/admins.sqlite" "$WORK/valhalla.json" "$OUT/"
rm -rf "$WORK"
echo "Done. Bundled: $OUT/{valhalla_tiles.tar, admins.sqlite, valhalla.json}"
ls -la "$OUT"
```

- [ ] **Step 2: Run it**

Run: `chmod +x tool/generate_valhalla_tiles.sh && tool/generate_valhalla_tiles.sh`
Expected: prints "route OK: 5.69... km ... 7 maneuvers" and writes the three files to `assets/routing/`. `valhalla_tiles.tar` ≈ 4–5 MB, `admins.sqlite` ≈ 6–7 MB. If Overpass rate-limits, wait a minute and re-run.

- [ ] **Step 3: Normalize the bundled `valhalla.json` to a placeholder config**

The generated `valhalla.json` has absolute `/work/...` paths. The native side rewrites them at runtime, but make the committed template self-documenting: replace the three mjolnir paths with the literal token `__APPDIR__` so the bridge's intent is unambiguous. Run:
```bash
python3 - <<'PY'
import json
p = 'assets/routing/valhalla.json'
c = json.load(open(p))
mj = c.setdefault('mjolnir', {})
mj['tile_extract'] = '__APPDIR__/valhalla_tiles.tar'
mj['tile_dir'] = '__APPDIR__/valhalla_tiles'
mj['admin'] = '__APPDIR__/admins.sqlite'
json.dump(c, open(p, 'w'), indent=2)
print('normalized', p)
PY
```
(The Kotlin handler replaces `__APPDIR__` with the app's files dir at runtime.)

- [ ] **Step 4: Register the assets**

In `pubspec.yaml` under `flutter: assets:`, the `- assets/routing/` line already exists (added for the M3 part-1 sample_route.json). Confirm it's present (`grep "assets/routing/" pubspec.yaml`); the new files live in that dir so they're covered. Run `flutter pub get`. Confirm `flutter analyze` + `flutter test` still pass (no Dart changed).

- [ ] **Step 5: Commit**

```bash
git add tool/generate_valhalla_tiles.sh assets/routing/valhalla_tiles.tar assets/routing/admins.sqlite assets/routing/valhalla.json pubspec.yaml
git commit -m "feat: generate + bundle Ghatshila Valhalla routing tiles (verified routing in Docker)"
```

---

## Task 2: Valhalla request builder (pure Dart, TDD)

**Files:**
- Create: `lib/routing/valhalla_request.dart`
- Test: `test/routing/valhalla_request_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/routing/valhalla_request_test.dart`:
```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/valhalla_request.dart';

void main() {
  test('builds locations + costing + units per mode', () {
    final json = buildValhallaRequest(
      const [LatLng(22.586, 86.476), LatLng(22.593, 86.515)],
      TravelMode.car,
    );
    final m = jsonDecode(json) as Map<String, Object?>;
    expect(m['costing'], 'auto');
    expect(m['units'], 'kilometers');
    final locs = m['locations'] as List;
    expect(locs.length, 2);
    expect((locs.first as Map)['lat'], 22.586);
    expect((locs.first as Map)['lon'], 86.476);
  });

  test('maps each travel mode to the right Valhalla costing', () {
    String costing(TravelMode mode) => (jsonDecode(buildValhallaRequest(
            const [LatLng(0, 0), LatLng(1, 1)], mode)) as Map)['costing'] as String;
    expect(costing(TravelMode.car), 'auto');
    expect(costing(TravelMode.motorbike), 'motorcycle');
    expect(costing(TravelMode.bike), 'bicycle');
    expect(costing(TravelMode.walk), 'pedestrian');
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/routing/valhalla_request_test.dart`
Expected: FAIL — `buildValhallaRequest` undefined.

- [ ] **Step 3: Implement**

Create `lib/routing/valhalla_request.dart`:
```dart
import 'dart:convert';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';

/// Builds a Valhalla `/route` request JSON string from ordered [points] and a
/// [mode]. Valhalla locations use {lat, lon}; costing is the mode's costing
/// model; units kilometres (matching the parser's km→metres conversion).
String buildValhallaRequest(List<LatLng> points, TravelMode mode) {
  return jsonEncode({
    'locations': [
      for (final p in points) {'lat': p.lat, 'lon': p.lng},
    ],
    'costing': mode.costing,
    'units': 'kilometers',
  });
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/routing/valhalla_request_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/routing/valhalla_request.dart test/routing/valhalla_request_test.dart
git commit -m "feat: add Valhalla request builder (points+mode -> request JSON, tested)"
```

---

## Task 3: ValhallaRoutingService over the MethodChannel (TDD with a mocked channel)

**Files:**
- Create: `lib/routing/valhalla_routing_service.dart`
- Test: `test/routing/valhalla_routing_service_test.dart`

- [ ] **Step 1: Write the failing test (mocks the platform channel)**

Create `test/routing/valhalla_routing_service_test.dart`:
```dart
import 'dart:convert';
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
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/routing/valhalla_routing_service_test.dart`
Expected: FAIL — `ValhallaRoutingService` undefined.

- [ ] **Step 3: Implement**

Create `lib/routing/valhalla_routing_service.dart`:
```dart
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
  ValhallaRoutingService({this.fallbackToFake = true});

  final bool fallbackToFake;
  static const _channel = MethodChannel('offline_navigator/valhalla');
  final _fake = FakeRoutingService();

  bool _ready = false;

  @override
  Future<void> ensureReady() async {
    if (_ready) return;
    try {
      await _channel.invokeMethod<void>('ensureReady');
      _ready = true;
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
      final res = await _channel.invokeMethod<String>('route', {'request': req});
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
      throw RoutingException(
          (decoded['message'] as String?) ?? 'No route found');
    }
    try {
      return parseValhallaRoute(decoded as Map<String, Object?>);
    } on FormatException catch (e) {
      throw RoutingException('Bad routing response: ${e.message}');
    }
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/routing/valhalla_routing_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Whole-project analyze + test**

Run: `flutter analyze` → clean; `flutter test` → all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/routing/valhalla_routing_service.dart test/routing/valhalla_routing_service_test.dart
git commit -m "feat: add ValhallaRoutingService over MethodChannel with fake fallback (tested)"
```

---

## Task 4: Android native — Gradle dependency + ValhallaPlugin (device-only build)

**Files:**
- Modify: `android/app/build.gradle.kts`
- Create: `android/app/src/main/kotlin/com/talentbridge/offline_navigator/ValhallaPlugin.kt`
- Modify: `android/app/src/main/kotlin/com/talentbridge/offline_navigator/MainActivity.kt`

> **HONESTY:** this task writes Kotlin/Gradle that CANNOT be compiled in the dev env (no Java/Android SDK build here). The acceptance for THIS task is: files are correct and committed; `flutter analyze`/`flutter test` (Dart) stay green. The actual compile + on-device run is the USER's step (Task 6). Do NOT claim the native side builds.

- [ ] **Step 1: Add the Gradle dependency**

In `android/app/build.gradle.kts`, inside the top-level `dependencies { }` block (add the block if absent, after the `android { }` block):
```kotlin
dependencies {
    implementation("io.github.rallista:valhalla-mobile:0.1.0")
}
```
Also confirm `android { compileSdk = flutter.compileSdkVersion }` is ≥ 24 (valhalla-mobile needs a modern minSdk; if `flutter.minSdkVersion` resolves below 21, set `defaultConfig { minSdk = 21 }`). Note: the dependency resolves from Maven Central, which is already in the default Flutter Android repositories.

- [ ] **Step 2: Find the exact package path of MainActivity**

Run: `find android/app/src/main/kotlin -name MainActivity.kt`
Use that file's package (e.g. `com.talentbridge.offline_navigator`) for the plugin's package and path. The paths below assume `com/talentbridge/offline_navigator`; adjust to match.

- [ ] **Step 3: Create the ValhallaPlugin**

Create `android/app/src/main/kotlin/com/talentbridge/offline_navigator/ValhallaPlugin.kt` (use the real package from Step 2):
```kotlin
package com.talentbridge.offline_navigator

import android.content.Context
import com.valhalla.valhalla.ValhallaActor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MethodChannel bridge to the native Valhalla engine (valhalla-mobile).
 *
 * ensureReady: copies the bundled tiles tar + admins.sqlite from Flutter assets
 * into app files storage (once, version-stamped), writes a valhalla.json whose
 * mjolnir paths point at that storage, and constructs a ValhallaActor.
 * route: forwards a Valhalla request JSON string to ValhallaActor.route().
 */
class ValhallaPlugin(private val context: Context) {
    companion object {
        const val CHANNEL = "offline_navigator/valhalla"
        // Bump when bundled tiles change so storage is refreshed.
        const val VERSION = "1"
    }

    private var actor: ValhallaActor? = null

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureReady" -> try {
                        ensureReady(); result.success(null)
                    } catch (e: Exception) {
                        result.error("ENSURE_FAILED", e.message, null)
                    }
                    "route" -> try {
                        val req = call.argument<String>("request")
                            ?: return@setMethodCallHandler result.error(
                                "BAD_ARGS", "missing request", null)
                        result.success(route(req))
                    } catch (e: Exception) {
                        result.error("ROUTE_FAILED", e.message, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun routingDir(): File =
        File(context.filesDir, "routing").apply { mkdirs() }

    private fun ensureReady() {
        if (actor != null) return
        val dir = routingDir()
        val stamp = File(dir, ".version")
        val fresh = !stamp.exists() || stamp.readText().trim() != VERSION
        if (fresh) {
            copyAsset("assets/routing/valhalla_tiles.tar", File(dir, "valhalla_tiles.tar"))
            copyAsset("assets/routing/admins.sqlite", File(dir, "admins.sqlite"))
            // Read the bundled config template and rewrite __APPDIR__.
            val template = context.assets.open("assets/routing/valhalla.json")
                .bufferedReader().use { it.readText() }
            val config = template.replace("__APPDIR__", dir.absolutePath)
            File(dir, "valhalla.json").writeText(config)
            stamp.writeText(VERSION)
        }
        actor = ValhallaActor(File(dir, "valhalla.json").absolutePath)
    }

    private fun route(request: String): String {
        ensureReady()
        return actor!!.route(request)
    }

    private fun copyAsset(assetPath: String, dest: File) {
        context.assets.open(assetPath).use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }
    }
}
```
Note: Flutter bundles assets under the `assets/` prefix accessible via `context.assets.open("assets/...")` through the `flutter_assets` path. If `context.assets.open("assets/routing/valhalla.json")` is not found at runtime, the correct path is `flutter_assets/assets/routing/valhalla.json` — the user will confirm on-device and we adjust the prefix (documented in Task 6).

- [ ] **Step 4: Register the plugin in MainActivity**

Modify `MainActivity.kt` to configure the channel:
```kotlin
package com.talentbridge.offline_navigator

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ValhallaPlugin(applicationContext).register(flutterEngine)
    }
}
```
(Keep the existing package line. If MainActivity already overrides `configureFlutterEngine`, merge the `ValhallaPlugin(...).register(...)` line in.)

- [ ] **Step 5: Dart still green (native not compiled here)**

Run: `flutter analyze` (Dart) → clean; `flutter test` → all pass. (We are NOT building the Android app here.)

- [ ] **Step 6: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/kotlin/com/talentbridge/offline_navigator/ValhallaPlugin.kt android/app/src/main/kotlin/com/talentbridge/offline_navigator/MainActivity.kt
git commit -m "feat(android): add valhalla-mobile dep + ValhallaPlugin MethodChannel bridge"
```

---

## Task 5: Wire ValhallaRoutingService into MapScreen

**Files:**
- Modify: `lib/map/map_screen.dart`

- [ ] **Step 1: Swap the routing service**

In `lib/map/map_screen.dart`, change the import + field. Replace:
```dart
import 'package:offline_navigator/routing/fake_routing_service.dart';
```
with:
```dart
import 'package:offline_navigator/routing/valhalla_routing_service.dart';
```
(Keep any other routing imports.) Change:
```dart
final RoutingService _routing = FakeRoutingService();
```
to:
```dart
// Real on-device Valhalla routing; falls back to straight-line if the native
// engine isn't available (e.g. iOS, or a failed Android build) so the trip
// planner is never dead. Routing works only where tiles exist on-device
// (currently the bundled Ghatshila region).
final RoutingService _routing = ValhallaRoutingService(fallbackToFake: true);
```
If `FakeRoutingService` is no longer referenced in `map_screen.dart`, remove its now-unused import (the analyzer will flag it).

- [ ] **Step 2: Whole-project analyze + test**

Run: `flutter analyze` → clean; `flutter test` → all pass. The existing `map_screen` widget tests use `MapScreen(autoStart:false)` and never invoke routing, so they remain green; the trip-planner panel tests inject their own `FakeRoutingService` directly, unaffected by this change.

- [ ] **Step 3: Commit**

```bash
git add lib/map/map_screen.dart
git commit -m "feat: use ValhallaRoutingService in the map (fallback to straight-line)"
```

---

## Task 6: Device build instructions + README + final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full Dart verification**

Run: `flutter analyze` (expect clean) and `flutter test` (record the real `+N` line). If red, fix before continuing.

- [ ] **Step 2: Write the device-build section in README**

In `README.md`, add a "Native routing (Android)" section with the honest scope + exact steps:
```markdown
## Native offline routing (Android — Milestone 3 part 2)

Real on-device routing uses the Valhalla engine (`valhalla-mobile`) over BUNDLED
Ghatshila routing tiles. **Scope:** this proves the engine runs on the phone; it
routes only where tiles exist on-device (currently Ghatshila). Routes outside
that region fail gracefully ("outside the downloaded map area") until the region
download manager is built. If the native engine is unavailable (e.g. iOS, or a
failed build), the app falls back to straight-line routing so the trip planner
still works.

### Regenerate routing tiles (optional — committed already)
Requires Docker + osmium:
    tool/generate_valhalla_tiles.sh   # builds + verifies assets/routing/valhalla_tiles.tar

### Build + run on an Android device
    flutter pub get
    flutter run                       # on a connected Android device

On first launch the app copies the bundled tiles into app storage and constructs
the native router. Plan a trip inside Ghatshila (Directions button → set start +
destination) and confirm the route line FOLLOWS ROADS with a maneuver list (vs.
the straight-line placeholder). If the route comes back straight, the native
engine fell back — check `flutter run` logs for a `ValhallaPlugin`/MethodChannel
error (most likely the asset path prefix: if assets aren't found, the plugin's
`context.assets.open("assets/routing/...")` may need the `flutter_assets/` prefix).
```
Also: update the Verification status table — add "Valhalla tiles route in Docker — PASS"; "ValhallaRoutingService (request/parse/fallback) — PASS (unit, mocked channel)"; "On-device Android route — NOT YET VERIFIED (user builds)"; keep iOS native as a later part.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: native Android Valhalla routing — build steps + honest scope"
```

- [ ] **Step 4: Push to the user's repo**

```bash
git push origin main
```
(Remote `origin` = `git@github-tb-vms:Drake0306/offline-navigator.git` via the `github-tb-vms` SSH alias — the user's personal account. Confirm with `git remote -v` before pushing.)

---

## Self-review (completed at plan-writing time)

**Spec coverage:**
- Tile pipeline (Docker, verified-routing-before-commit, bundled tar+admins+config) → Task 1. ✓ (verified live during planning)
- MethodChannel bridge `offline_navigator/valhalla`, ensureReady (copy→storage, rewrite config, construct ValhallaActor), route(json)→json → Task 4. ✓
- ValhallaRoutingService: request-builder + reuse parseValhallaRoute + error mapping + fallback → Tasks 2,3. ✓
- Swap into MapScreen behind the unchanged interface → Task 5. ✓
- Storage-based tile loading (so the download manager can add regions) → Task 4 (copies to filesDir, config rewritten). ✓
- Android-first, iOS deferred → only Android native written. ✓
- Honest scope (routes only within bundled tiles; outside fails gracefully; fallback on) → Tasks 3,5,6 + README. ✓
- Testing: Docker route verify (Task 1), Dart request/parse/error/fallback unit tests (Tasks 2,3), device run (Task 6). ✓

**Placeholder scan:** No TBD/TODO. Task 4 has two honest "confirm on device" notes (the asset-path prefix; the MainActivity package path) — these are concrete verification steps for the device-only native build, with the exact fallback (`flutter_assets/` prefix) and the discovery command (`find ... MainActivity.kt`), not blanks.

**Type consistency:** `buildValhallaRequest(List<LatLng>, TravelMode) → String` consistent Tasks 2,3. `ValhallaRoutingService({fallbackToFake})` + `RoutingService.{ensureReady,route}` + `RoutingException` consistent Tasks 3,5. Reuses Part 1 `parseValhallaRoute`, `RoutePlan`, `TravelMode.costing`, `LatLng`, `FakeRoutingService` with their existing signatures. Channel name `offline_navigator/valhalla` + methods `ensureReady`/`route` (arg `request`) consistent across Tasks 3 (Dart) and 4 (Kotlin).

**Device-only items (honest, not blockers):** the Android Gradle build, the AAR linking, the asset-path prefix, and the actual on-device road-following route are verified by the USER (Task 6). Everything Dart + the tile data is verified here.
