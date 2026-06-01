import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_store.dart';
import 'package:offline_navigator/regions/region_downloader.dart';

void main() {
  late Directory tmp;
  late RegionStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('regiondl');
    store = RegionStore(rootPath: tmp.path);
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  const content = {
    'tiles': 'TILES-DATA',
    'valhalla': 'VALHALLA-DATA',
    'admins': 'ADMINS-DATA',
    'search': 'SEARCH-DATA',
  };
  String sha(String s) => sha256.convert(utf8.encode(s)).toString();

  Region regionWith({Map<String, String>? badSha}) => Region.fromJson({
        'id': 'r1', 'name': 'R1', 'state': 'JH',
        'bbox': [86.0, 22.2, 86.9, 23.1], 'version': 1,
        'files': {
          for (final k in const ['tiles', 'valhalla', 'admins', 'search'])
            k: {
              'url': 'https://x/$k',
              'bytes': utf8.encode(content[k]!).length,
              'sha256': (badSha != null && badSha.containsKey(k))
                  ? badSha[k]
                  : sha(content[k]!),
            }
        },
      });

  MockClient okClient() => MockClient((req) async {
        final key = req.url.pathSegments.last;
        final body = content[key];
        if (body == null) return http.Response('', 404);
        return http.Response(body, 200);
      });

  test('downloads + verifies + installs, progress ends at 1.0', () async {
    final dl = RegionDownloader(okClient());
    final fracs = <double>[];
    await dl.download(regionWith(), store, onProgress: fracs.add);
    expect(await store.isInstalled('r1'), isTrue);
    expect(await File(store.filesFor('r1').tiles).readAsString(), 'TILES-DATA');
    expect(await File(store.filesFor('r1').search).readAsString(), 'SEARCH-DATA');
    expect(fracs.last, closeTo(1.0, 1e-9));
    expect(fracs.first <= fracs.last, isTrue);
  });

  test('checksum mismatch throws and leaves no installed region', () async {
    final dl = RegionDownloader(okClient());
    await expectLater(
      dl.download(regionWith(badSha: {'admins': 'deadbeef'}), store),
      throwsA(isA<RegionDownloadException>()),
    );
    expect(await store.isInstalled('r1'), isFalse);
    expect(await Directory('${store.regionDir('r1').parent.path}/.part-r1').exists(), isFalse);
  });

  test('cancel aborts and cleans up', () async {
    final cancel = CancelToken()..cancel();
    final dl = RegionDownloader(okClient());
    await expectLater(
      dl.download(regionWith(), store, cancel: cancel),
      throwsA(isA<RegionDownloadCancelled>()),
    );
    expect(await store.isInstalled('r1'), isFalse);
  });
}
