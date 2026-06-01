import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:offline_navigator/regions/region_store.dart';
import 'package:offline_navigator/regions/region_downloader.dart';
import 'package:offline_navigator/regions/region_controller.dart';
import 'package:offline_navigator/settings/settings_screen.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('settings'));
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  RegionController emptyController() => RegionController(
        store: RegionStore(rootPath: tmp.path),
        downloader: RegionDownloader(MockClient((r) async => http.Response('', 404))),
        catalogSource: () async => [],
      );

  testWidgets('shows the download-regions tile and opens the manager',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(regions: emptyController())));
    await tester.pump();

    expect(find.byKey(const Key('downloadRegionsTile')), findsOneWidget);
    expect(find.text('Download regions'), findsOneWidget);

    await tester.tap(find.byKey(const Key('downloadRegionsTile')));
    await tester.pumpAndSettle();

    // The manager screen is now on top (its AppBar refresh action is unique).
    expect(find.byKey(const Key('refreshRegions')), findsOneWidget);
  });
}
