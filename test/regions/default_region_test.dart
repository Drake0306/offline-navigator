import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/regions/region_store.dart';
import 'package:offline_navigator/regions/default_region.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // for rootBundle

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('seed'));
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('seeds the bundled Ghatshila region and activates it', () async {
    final store = RegionStore(rootPath: tmp.path);
    await seedDefaultRegion(store);

    expect(await store.isInstalled('ghatshila'), isTrue);
    final f = store.filesFor('ghatshila');
    expect(await File(f.tiles).exists(), isTrue);
    expect(await File(f.valhalla).exists(), isTrue);
    expect(await File(f.admins).exists(), isTrue);
    expect(await File(f.search).exists(), isTrue);
    expect(await store.activeRegionId(), 'ghatshila');
    expect((await store.installedRegions()).single.id, 'ghatshila');
  });

  test('is idempotent and respects an existing active region', () async {
    final store = RegionStore(rootPath: tmp.path);
    await seedDefaultRegion(store);
    await store.setActive('somewhere-else');
    await seedDefaultRegion(store); // must not throw or reset active
    expect(await store.activeRegionId(), 'somewhere-else');
  });
}
