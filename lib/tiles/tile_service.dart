import 'dart:io';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path_provider/path_provider.dart';
import 'package:offline_navigator/common/app_paths.dart';
import 'package:offline_navigator/map/map_style.dart';
import 'package:offline_navigator/tiles/local_tile_server.dart';
import 'package:offline_navigator/tiles/pmtiles_reader.dart';

/// Bump when bundled assets change so on-device storage is refreshed.
const String kAssetVersion = '1';

/// The font stack folder name shipped under assets/glyphs/ (must match Task 3).
const String kFontStack = 'Noto Sans Regular';

/// Returned by [TileService.ensureReady]. Carries the local server base
/// origin; build a per-style URL with [styleUrlFor]. The server itself is
/// owned and stopped by [TileService] (via [TileService.dispose]).
class MapReady {
  MapReady(this.base);

  /// The server origin, e.g. `http://127.0.0.1:54321`.
  final String base;

  String styleUrlFor(MapStyleId id) => '$base${id.route}';

  /// Convenience: the default (Standard) style URL.
  String get styleUrl => styleUrlFor(MapStyleId.standard);
}

/// Copies bundled offline assets to on-device storage (once, version-stamped),
/// starts a [LocalTileServer], and returns a localhost style URL for MapLibre.
class TileService {
  LocalTileServer? _server;
  Map<String, String>? _templates; // style name -> template, cached for restart
  String? _glyphsDir;

  /// Replaces every `__BASE__` token in [template] with [base].
  static String rewriteStyle(String template, String base) =>
      template.replaceAll('__BASE__', base);

  /// Prepare storage + start the tile server. When [pmtilesPath] is given, the
  /// server reads that region's tiles; when null it falls back to copying and
  /// serving the bundled Ghatshila pack (legacy default).
  Future<MapReady> ensureReady({String? pmtilesPath}) async {
    final supportDir = await getApplicationSupportDirectory();
    final paths = AppPaths(root: supportDir.path);

    if (await paths.needsRefresh(kAssetVersion)) {
      if (pmtilesPath == null) {
        await _copyAsset('assets/tiles/ghatshila.pmtiles', paths.tilesPath);
      }
      await _copyGlyphs(paths.glyphsDir);
      await paths.writeStamp(kAssetVersion);
    } else if (pmtilesPath == null && !await File(paths.tilesPath).exists()) {
      // Stamp present but bundled tiles missing (e.g. first non-region run after
      // an upgrade): make sure the legacy default exists.
      await _copyAsset('assets/tiles/ghatshila.pmtiles', paths.tilesPath);
    }

    _glyphsDir = paths.glyphsDir;
    _templates = {
      for (final id in MapStyleId.values) id.name: await rootBundle.loadString(id.assetPath),
    };
    return _startServer(pmtilesPath ?? paths.tilesPath);
  }

  /// Switch the running server to a different region's tiles.
  Future<MapReady> restartForRegion(String pmtilesPath) async {
    await _server?.stop();
    _server = null;
    return _startServer(pmtilesPath);
  }

  Future<MapReady> _startServer(String pmtilesPath) async {
    final reader = await PmTilesReader.open(pmtilesPath);
    final server = LocalTileServer(
      reader: reader,
      glyphsDir: _glyphsDir!,
      styles: const {},
    );
    await server.start();
    final base = server.baseUrl;
    server.updateStyles({
      for (final e in _templates!.entries) e.key: rewriteStyle(e.value, base),
    });
    _server = server;
    return MapReady(base);
  }

  Future<void> dispose() async {
    await _server?.stop();
    _server = null;
  }

  // ---- private helpers (unchanged) ----
  Future<void> _copyAsset(String assetKey, String destPath) async {
    final data = await rootBundle.load(assetKey);
    final file = File(destPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  Future<void> _copyGlyphs(String glyphsDir) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final glyphKeys = manifest
        .listAssets()
        .where((k) => k.startsWith('assets/glyphs/$kFontStack/') && k.endsWith('.pbf'))
        .toList();
    if (glyphKeys.isEmpty) {
      throw StateError('No glyph assets found under assets/glyphs/$kFontStack/ '
          '— offline labels would be missing');
    }
    for (final key in glyphKeys) {
      final rel = key.substring('assets/glyphs/'.length);
      await _copyAsset(key, '$glyphsDir/$rel');
    }
  }
}
