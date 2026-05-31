import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';

/// Thin wrapper over the `pmtiles` package: opens a local .pmtiles archive and
/// returns decompressed tile bytes for a z/x/y request.
///
/// GZIP FINDING: `tile.bytes()` in pmtiles 2.0.0 already decompresses
/// internally — for gzip tiles it calls `ZLibDecoder().convert(bytes)` (see
/// `lib/src/native/compression.dart` and `lib/src/tile.dart`). The archive
/// stores tiles gzip-compressed (tileCompression == Compression.gzip), but
/// `tile.bytes()` returns the plain decompressed MVT/protobuf bytes.
/// Therefore NO extra decompression is needed here: we return `tile.bytes()`
/// as-is and Task 6's HTTP server can serve these as raw pbf with no
/// Content-Encoding header.
class PmTilesReader {
  PmTilesReader._(this._archive, this.minZoom, this.maxZoom);

  final PmTilesArchive _archive;

  /// Minimum zoom level available in this archive.
  final int minZoom;

  /// Maximum zoom level available in this archive.
  final int maxZoom;

  /// Opens the archive at [path] and reads the zoom range from metadata.
  ///
  /// min/max zoom are read from the embedded metadata JSON (keys `minzoom` /
  /// `maxzoom`) per the pmtiles 2.0.0 spec.  If either key is absent the
  /// header getters `archive.minZoom` / `archive.maxZoom` are used as a
  /// fallback (they are also populated from the archive header and are always
  /// correct for well-formed archives).
  static Future<PmTilesReader> open(String path) async {
    final archive = await PmTilesArchive.from(path);

    // metadata returns Future<Object?> — cast to Map when present.
    final rawMeta = await archive.metadata;
    final meta = rawMeta is Map ? rawMeta : <dynamic, dynamic>{};

    final minZ =
        (meta['minzoom'] as num?)?.toInt() ?? archive.minZoom;
    final maxZ =
        (meta['maxzoom'] as num?)?.toInt() ?? archive.maxZoom;

    return PmTilesReader._(archive, minZ, maxZ);
  }

  /// Returns raw **decompressed** tile bytes for tile (z, x, y), or null if
  /// the tile is absent from the archive.
  ///
  /// `tile.bytes()` handles decompression internally — the returned
  /// [Uint8List] is plain MVT protobuf, ready to serve without any additional
  /// Content-Encoding.
  Future<Uint8List?> readTile(int z, int x, int y) async {
    try {
      final tileId = ZXY(z, x, y).toTileId();
      final tile = await _archive.tile(tileId);
      // bytes() decompresses (gzip → plain pbf) and throws TileNotFoundException
      // if the tile is missing.
      return Uint8List.fromList(tile.bytes());
    } catch (_) {
      return null;
    }
  }

  /// Closes the underlying archive file handle.
  Future<void> close() => _archive.close();
}
