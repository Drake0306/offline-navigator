import 'dart:io';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path_provider/path_provider.dart';
import 'package:offline_navigator/common/app_paths.dart';
import 'package:offline_navigator/tiles/local_tile_server.dart';
import 'package:offline_navigator/tiles/pmtiles_reader.dart';

/// Bump when bundled assets change so on-device storage is refreshed.
const String kAssetVersion = '1';

/// The font stack folder name shipped under assets/glyphs/ (must match Task 3).
const String kFontStack = 'Noto Sans Regular';

/// Returned by [TileService.ensureReady]; carries the style URL and the
/// running server (so the caller can stop it when done).
class MapReady {
  MapReady(this.styleUrl, this.server);

  final String styleUrl;
  final LocalTileServer server;
}

/// Copies bundled offline assets to on-device storage (once, version-stamped),
/// starts a [LocalTileServer], and returns a localhost style URL for MapLibre.
class TileService {
  LocalTileServer? _server;

  /// Replaces every `__BASE__` token in [template] with [base] (the server
  /// origin, e.g. `http://127.0.0.1:PORT`).
  static String rewriteStyle(String template, String base) =>
      template.replaceAll('__BASE__', base);

  Future<MapReady> ensureReady() async {
    final supportDir = await getApplicationSupportDirectory();
    final paths = AppPaths(root: supportDir.path);

    // Copy bundled assets to storage on first run (or after a version bump).
    if (await paths.needsRefresh(kAssetVersion)) {
      await _copyAsset('assets/tiles/ghatshila.pmtiles', paths.tilesPath);
      await _copyGlyphs(paths.glyphsDir);
      await paths.writeStamp(kAssetVersion);
    }

    // Load the style template from the bundle.
    final styleTemplate =
        await rootBundle.loadString('assets/style/style.json');

    // Open the tile reader and start the server.
    final reader = await PmTilesReader.open(paths.tilesPath);
    final server = LocalTileServer(
      reader: reader,
      glyphsDir: paths.glyphsDir,
      styleJson: '{}', // placeholder; replaced below once we know baseUrl
    );
    await server.start();

    // Now that we know the ephemeral port, rewrite the style and push it in
    // without any restart — the clean single-start design.
    server.updateStyle(rewriteStyle(styleTemplate, server.baseUrl));

    _server = server;
    return MapReady('${server.baseUrl}/style.json', server);
  }

  Future<void> dispose() async {
    await _server?.stop();
    _server = null;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Loads [assetKey] from the bundle and writes it to [destPath],
  /// creating parent directories as needed.
  Future<void> _copyAsset(String assetKey, String destPath) async {
    final data = await rootBundle.load(assetKey);
    final file = File(destPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  /// Copies every `*.pbf` glyph range for [kFontStack] into [glyphsDir].
  ///
  /// Asset keys are discovered via the modern [AssetManifest] API (supported
  /// since Flutter 3.16; replaces the deprecated `AssetManifest.json` approach).
  /// Throws a [StateError] if no glyph assets are found, so that a missing-font
  /// regression surfaces immediately rather than producing a label-less map.
  Future<void> _copyGlyphs(String glyphsDir) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final glyphKeys = manifest
        .listAssets()
        .where((k) =>
            k.startsWith('assets/glyphs/$kFontStack/') && k.endsWith('.pbf'))
        .toList();

    if (glyphKeys.isEmpty) {
      throw StateError(
        'No glyph assets found under assets/glyphs/$kFontStack/ '
        '— offline labels would be missing',
      );
    }

    for (final key in glyphKeys) {
      // Relative path within the glyphs dir: e.g. "Noto Sans Regular/0-255.pbf"
      final rel = key.substring('assets/glyphs/'.length);
      await _copyAsset(key, '$glyphsDir/$rel');
    }
  }
}
