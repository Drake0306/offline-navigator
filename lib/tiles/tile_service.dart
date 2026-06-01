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
