import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_store.dart';
import 'package:offline_navigator/regions/region_downloader.dart';
import 'package:offline_navigator/regions/region_controller.dart';

void main() {
  late Directory tmp;
  late RegionStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('regionctl');
    store = RegionStore(rootPath: tmp.path);
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  const content = {'tiles': 'T', 'valhalla': 'V', 'admins': 'A', 'search': 'S'};
  String sha(String s) => sha256.convert(utf8.encode(s)).toString();

  Region region(String id) => Region.fromJson({
        'id': id, 'name': id.toUpperCase(), 'state': 'JH',
        'bbox': [86.0, 22.2, 86.9, 23.1], 'version': 1,
        'files': {
          for (final k in const ['tiles', 'valhalla', 'admins', 'search'])
            k: {'url': 'https://x/$id/$k', 'bytes': utf8.encode(content[k]!).length, 'sha256': sha(content[k]!)}
        },
      });

  MockClient okClient() => MockClient((req) async {
        final body = content[req.url.pathSegments.last];
        return body == null ? http.Response('', 404) : http.Response(body, 200);
      });

  // Seed a region directly as installed (no download), for the default region.
  Future<void> seedInstalled(String id) async {
    final staging = '${store.regionDir(id).parent.path}/.part-$id';
    await Directory(staging).create(recursive: true);
    for (final name in ['tiles.pmtiles', 'valhalla.tar', 'admins.sqlite', 'search.sqlite']) {
      await File('$staging/$name').writeAsString('x');
    }
    await store.install(region(id), stagingDir: staging);
  }

  RegionController make() => RegionController(
        store: store,
        downloader: RegionDownloader(okClient()),
        catalogSource: () async => [region('ra')],
        defaultRegionId: 'ghatshila',
      );

  test('loadInstalled reflects the store', () async {
    await seedInstalled('ghatshila');
    await store.setActive('ghatshila');
    final c = make();
    await c.loadInstalled();
    expect(c.installed.map((r) => r.id), ['ghatshila']);
    expect(c.activeRegionId, 'ghatshila');
  });

  test('refreshCatalog populates available', () async {
    final c = make();
    await c.refreshCatalog();
    expect(c.available.map((r) => r.id), ['ra']);
  });

  test('download installs the region and clears its progress', () async {
    await seedInstalled('ghatshila');
    final c = make();
    await c.loadInstalled();
    await c.refreshCatalog();
    final seen = <double>[];
    c.addListener(() {
      final p = c.progress['ra'];
      if (p != null) seen.add(p);
    });
    await c.download('ra');
    expect(c.installed.map((r) => r.id).toSet(), {'ghatshila', 'ra'});
    expect(c.progress.containsKey('ra'), isFalse);
    expect(seen.isNotEmpty, isTrue);
  });

  test('setActive updates the active region', () async {
    await seedInstalled('ghatshila');
    final c = make();
    await c.loadInstalled();
    await c.refreshCatalog();
    await c.download('ra');
    await c.setActive('ra');
    expect(c.activeRegionId, 'ra');
  });

  test('deleting the active region falls back to the default', () async {
    await seedInstalled('ghatshila');
    final c = make();
    await c.loadInstalled();
    await c.refreshCatalog();
    await c.download('ra');
    await c.setActive('ra');
    await c.delete('ra');
    expect(c.installed.map((r) => r.id), ['ghatshila']);
    expect(c.activeRegionId, 'ghatshila');
  });
}
