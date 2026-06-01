import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_store.dart';

class RegionDownloadException implements Exception {
  const RegionDownloadException(this.message);
  final String message;
  @override
  String toString() => 'RegionDownloadException: $message';
}

class RegionDownloadCancelled implements Exception {
  const RegionDownloadCancelled();
  @override
  String toString() => 'RegionDownloadCancelled';
}

/// Cooperative cancellation token for a download.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Downloads a region's files to a staging dir, verifies each sha256, then
/// installs atomically via [RegionStore.install]. Progress is reported in
/// [0, 1] summed by bytes across files. On any error/cancel the staging dir is
/// removed so no half-region is left behind.
class RegionDownloader {
  RegionDownloader(this._client);
  final http.Client _client;

  static const _fileOrder = ['tiles', 'valhalla', 'admins', 'search'];

  Future<void> download(Region region, RegionStore store,
      {void Function(double frac)? onProgress, CancelToken? cancel}) async {
    final stagingPath = '${store.regionDir(region.id).parent.path}/.part-${region.id}';
    final staging = Directory(stagingPath);
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    final targets = RegionFiles(stagingPath);
    final dest = <String, String>{
      'tiles': targets.tiles,
      'valhalla': targets.valhalla,
      'admins': targets.admins,
      'search': targets.search,
    };
    final total = region.totalBytes;
    var done = 0;

    try {
      for (final key in _fileOrder) {
        if (cancel?.isCancelled ?? false) throw const RegionDownloadCancelled();
        await _downloadOne(region.files[key]!, dest[key]!, cancel: cancel,
            onBytes: (n) {
          done += n;
          onProgress?.call(total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0));
        });
      }
      await store.install(region, stagingDir: stagingPath);
      onProgress?.call(1.0);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _downloadOne(RegionFile file, String destPath,
      {required void Function(int) onBytes, CancelToken? cancel}) async {
    final res = await _client.send(http.Request('GET', Uri.parse(file.url)));
    if (res.statusCode != 200) {
      throw RegionDownloadException('download failed (${res.statusCode}) for ${file.url}');
    }
    final out = File(destPath);
    await out.parent.create(recursive: true);
    final sink = out.openWrite();
    Digest? digest;
    final hashIn = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((d) => digest = d.single),
    );
    try {
      await for (final chunk in res.stream) {
        if (cancel?.isCancelled ?? false) throw const RegionDownloadCancelled();
        sink.add(chunk);
        hashIn.add(chunk);
        onBytes(chunk.length);
      }
    } finally {
      await sink.close();
      hashIn.close();
    }
    if ((digest?.toString() ?? '') != file.sha256) {
      throw RegionDownloadException('checksum mismatch for ${file.url}');
    }
  }
}
