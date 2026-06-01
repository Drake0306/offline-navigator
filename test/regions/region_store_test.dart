import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_store.dart';

Region _region(String id) => Region.fromJson({
      'id': id, 'name': id, 'state': 'Jharkhand',
      'bbox': [86.0, 22.2, 86.9, 23.1], 'version': 1,
      'files': {
        'tiles': {'url': 'u', 'bytes': 1, 'sha256': 'a'},
        'valhalla': {'url': 'u', 'bytes': 1, 'sha256': 'a'},
        'admins': {'url': 'u', 'bytes': 1, 'sha256': 'a'},
        'search': {'url': 'u', 'bytes': 1, 'sha256': 'a'},
      },
    });

void main() {
  late Directory tmp;
  late RegionStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('regionstore');
    store = RegionStore(rootPath: tmp.path);
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> stage(String id) async {
    final staging = p.join(tmp.path, 'regions', '.part-$id');
    await Directory(staging).create(recursive: true);
    for (final name in ['tiles.pmtiles', 'valhalla.tar', 'admins.sqlite', 'search.sqlite']) {
      await File(p.join(staging, name)).writeAsString('x');
    }
    return staging;
  }

  test('install + list', () async {
    await store.install(_region('r1'), stagingDir: await stage('r1'));
    final installed = await store.installedRegions();
    expect(installed.map((r) => r.id), ['r1']);
    expect(await File(store.filesFor('r1').tiles).exists(), isTrue);
    expect((await store.manifest('r1'))!.installedAt, isNotNull);
  });

  test('filesFor returns the five region paths', () {
    final f = store.filesFor('r1');
    expect(f.tiles, endsWith(p.join('regions', 'r1', 'tiles.pmtiles')));
    expect(f.valhalla, endsWith('valhalla_tiles.tar'));
    expect(f.admins, endsWith('admins.sqlite'));
    expect(f.config, endsWith('valhalla.json'));
    expect(f.search, endsWith('search.sqlite'));
  });

  test('active persists across instances', () async {
    await store.install(_region('r1'), stagingDir: await stage('r1'));
    await store.setActive('r1');
    final store2 = RegionStore(rootPath: tmp.path);
    expect(await store2.activeRegionId(), 'r1');
  });

  test('delete removes the region and clears active if it was active', () async {
    await store.install(_region('r1'), stagingDir: await stage('r1'));
    await store.setActive('r1');
    await store.delete('r1');
    expect(await store.installedRegions(), isEmpty);
    expect(await store.activeRegionId(), isNull);
  });
}
