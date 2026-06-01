import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:offline_navigator/regions/region.dart';

/// Absolute paths to a region's on-device files.
class RegionFiles {
  const RegionFiles(this.dir);
  final String dir;
  String get tiles => p.join(dir, 'tiles.pmtiles');
  String get valhalla => p.join(dir, 'valhalla.tar');
  String get admins => p.join(dir, 'admins.sqlite');
  String get config => p.join(dir, 'valhalla.json'); // generated on-device, not downloaded
  String get search => p.join(dir, 'search.sqlite');
}

/// Manages region packages on device: `<root>/regions/<id>/{...,manifest.json}`
/// plus the persisted active region id (`<root>/regions/active.txt`).
/// [rootPath] is injected so tests use a temp dir; production resolves it via
/// [RegionStore.open].
class RegionStore {
  RegionStore({required this.rootPath});
  final String rootPath;

  static Future<RegionStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return RegionStore(rootPath: dir.path);
  }

  Directory get _regionsRoot => Directory(p.join(rootPath, 'regions'));
  Directory regionDir(String id) => Directory(p.join(_regionsRoot.path, id));
  RegionFiles filesFor(String id) => RegionFiles(regionDir(id).path);
  File _manifestFile(String id) => File(p.join(regionDir(id).path, 'manifest.json'));
  File get _activeFile => File(p.join(_regionsRoot.path, 'active.txt'));

  Future<bool> isInstalled(String id) => _manifestFile(id).exists();

  Future<Region?> manifest(String id) async {
    final f = _manifestFile(id);
    if (!await f.exists()) return null;
    return Region.fromJson(jsonDecode(await f.readAsString()) as Map<String, Object?>);
  }

  Future<List<Region>> installedRegions() async {
    if (!await _regionsRoot.exists()) return [];
    final out = <Region>[];
    await for (final e in _regionsRoot.list()) {
      if (e is Directory) {
        final m = await manifest(p.basename(e.path));
        if (m != null) out.add(m);
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<void> writeManifest(Region region) async {
    final f = _manifestFile(region.id);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(region.toJson()), flush: true);
  }

  /// Promote a fully-staged dir into `regions/<id>/` and write its manifest.
  Future<void> install(Region region, {required String stagingDir}) async {
    final dest = regionDir(region.id);
    if (await dest.exists()) await dest.delete(recursive: true);
    await dest.parent.create(recursive: true);
    await Directory(stagingDir).rename(dest.path);
    await writeManifest(region.copyWith(installedAt: DateTime.now()));
  }

  Future<void> delete(String id) async {
    final d = regionDir(id);
    if (await d.exists()) await d.delete(recursive: true);
    if (await activeRegionId() == id) await setActive(null);
  }

  Future<String?> activeRegionId() async {
    if (!await _activeFile.exists()) return null;
    final s = (await _activeFile.readAsString()).trim();
    return s.isEmpty ? null : s;
  }

  Future<void> setActive(String? id) async {
    await _regionsRoot.create(recursive: true);
    await _activeFile.writeAsString(id ?? '', flush: true);
  }
}
