import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_store.dart';

/// The built-in Ghatshila region, installed from bundled assets on first run so
/// the app is never empty offline. Its `files` carry placeholder download
/// metadata (it ships in the APK, not downloaded).
final Region ghatshilaRegion = Region(
  id: 'ghatshila',
  name: 'Ghatshila (built-in)',
  state: 'Jharkhand',
  bbox: const RegionBounds(86.25, 22.35, 86.75, 22.85),
  version: 1,
  files: const {
    'tiles': RegionFile(url: 'bundled', bytes: 0, sha256: 'bundled'),
    'valhalla': RegionFile(url: 'bundled', bytes: 0, sha256: 'bundled'),
    'admins': RegionFile(url: 'bundled', bytes: 0, sha256: 'bundled'),
    'search': RegionFile(url: 'bundled', bytes: 0, sha256: 'bundled'),
  },
);

/// Install the bundled Ghatshila region into [store] if absent, and make it the
/// active region when none is set. Idempotent.
Future<void> seedDefaultRegion(RegionStore store) async {
  if (!await store.isInstalled(ghatshilaRegion.id)) {
    final files = store.filesFor(ghatshilaRegion.id);
    await Directory(files.dir).create(recursive: true);
    await _copyAsset('assets/tiles/ghatshila.pmtiles', files.tiles);
    await _copyAsset('assets/routing/valhalla_tiles.tar', files.valhalla);
    await _copyAsset('assets/routing/admins.sqlite', files.admins);
    await _copyAsset('assets/search/ghatshila.sqlite', files.search);
    await store.writeManifest(
        ghatshilaRegion.copyWith(installedAt: DateTime.now()));
  }
  if (await store.activeRegionId() == null) {
    await store.setActive(ghatshilaRegion.id);
  }
}

Future<void> _copyAsset(String assetKey, String destPath) async {
  final data = await rootBundle.load(assetKey);
  final f = File(destPath);
  await f.parent.create(recursive: true);
  await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
}
