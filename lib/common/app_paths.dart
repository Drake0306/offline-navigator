import 'dart:io';
import 'package:path/path.dart' as p;

/// Resolves on-device storage locations and tracks which asset version has
/// been copied into storage, so we only re-copy when the bundled data changes.
class AppPaths {
  AppPaths({required this.root});

  /// Root directory for app data (use path_provider's app support dir in prod).
  final String root;

  String get tilesPath => p.join(root, 'tiles', 'ghatshila.pmtiles');
  String get glyphsDir => p.join(root, 'glyphs');
  String get _stampPath => p.join(root, '.asset_version');

  /// True if storage has no stamp or the stamp differs from [version].
  Future<bool> needsRefresh(String version) async {
    final f = File(_stampPath);
    if (!await f.exists()) return true;
    return (await f.readAsString()).trim() != version;
  }

  Future<void> writeStamp(String version) async {
    final f = File(_stampPath);
    await f.parent.create(recursive: true);
    await f.writeAsString(version);
  }
}
