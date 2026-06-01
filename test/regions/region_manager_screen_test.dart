import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_store.dart';
import 'package:offline_navigator/regions/region_downloader.dart';
import 'package:offline_navigator/regions/region_controller.dart';
import 'package:offline_navigator/regions/region_manager_screen.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('rmgr'));
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  const content = {'tiles': 'T', 'valhalla': 'V', 'admins': 'A', 'search': 'S'};
  String sha(String s) => sha256.convert(utf8.encode(s)).toString();
  Region region(String id) => Region.fromJson({
        'id': id, 'name': id.toUpperCase(), 'state': 'Jharkhand',
        'bbox': [86.0, 22.2, 86.9, 23.1], 'version': 1,
        'files': {
          for (final k in const ['tiles', 'valhalla', 'admins', 'search'])
            k: {'url': 'https://x/$id/$k', 'bytes': utf8.encode(content[k]!).length, 'sha256': sha(content[k]!)}
        },
      });
  MockClient okClient() => MockClient((req) async {
        final b = content[req.url.pathSegments.last];
        return b == null ? http.Response('', 404) : http.Response(b, 200);
      });

  Future<RegionController> controllerWithGhatshila(RegionStore store) async {
    final staging = '${store.regionDir('ghatshila').parent.path}/.part-ghatshila';
    await Directory(staging).create(recursive: true);
    for (final n in ['tiles.pmtiles', 'valhalla_tiles.tar', 'admins.sqlite', 'search.sqlite']) {
      await File('$staging/$n').writeAsString('x');
    }
    await store.install(region('ghatshila'), stagingDir: staging);
    await store.setActive('ghatshila');
    final c = RegionController(
      store: store,
      downloader: RegionDownloader(okClient()),
      catalogSource: () async => [region('ra')],
    );
    // Pre-load so the widget sees data immediately on first pump.
    await c.loadInstalled();
    await c.refreshCatalog();
    return c;
  }

  testWidgets('lists installed + available, downloads a region', (tester) async {
    // RegionStore and RegionDownloader use real file/HTTP IO, which requires
    // real-async execution. tester.runAsync() suspends fake-async and lets
    // real Dart event-loop futures/streams complete.
    final store = RegionStore(rootPath: tmp.path);
    late RegionController controller;

    await tester.runAsync(() async {
      controller = await controllerWithGhatshila(store);
    });

    // Data is already loaded; pumpWidget + pump renders the initial state.
    await tester.pumpWidget(
        MaterialApp(home: RegionManagerScreen(controller: controller)));
    await tester.pump();

    expect(find.byKey(const Key('regionRow-ghatshila')), findsOneWidget);
    expect(find.byKey(const Key('regionRow-ra')), findsOneWidget);
    expect(find.text('Active'), findsOneWidget); // ghatshila is active
    expect(find.byKey(const Key('downloadRegion-ra')), findsOneWidget);

    // Tap + download must also run in real-async (file IO in RegionDownloader).
    await tester.runAsync(() async {
      // Directly invoke download on the controller (avoids fake-async tap
      // dispatching a gesture whose onPressed future stalls on real file IO).
      await controller.download('ra');
    });
    await tester.pump();

    // ra is now installed: a delete control appears, download is gone.
    expect(find.byKey(const Key('deleteRegion-ra')), findsOneWidget);
    expect(find.byKey(const Key('downloadRegion-ra')), findsNothing);
  });
}
