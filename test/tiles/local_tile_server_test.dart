import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/tiles/local_tile_server.dart';
import 'package:offline_navigator/tiles/pmtiles_reader.dart';

void main() {
  late LocalTileServer server;

  setUp(() async {
    final reader = await PmTilesReader.open('assets/tiles/ghatshila.pmtiles');
    final glyphs = Directory.systemTemp.createTempSync('glyphs');
    Directory('${glyphs.path}/Noto Sans Regular').createSync(recursive: true);
    File('${glyphs.path}/Noto Sans Regular/0-255.pbf').writeAsBytesSync([1, 2, 3]);
    server = LocalTileServer(
      reader: reader,
      glyphsDir: glyphs.path,
      styles: {'standard': '{"version":8,"name":"std"}'},
    );
    await server.start();
  });

  tearDown(() async => server.stop());

  test('serves a named style', () async {
    final res = await _get('${server.baseUrl}/style/standard.json');
    expect(res.statusCode, 200);
    expect(res.body, contains('"name":"std"'));
  });

  test('404 for an unknown style', () async {
    final res = await _get('${server.baseUrl}/style/nope.json');
    expect(res.statusCode, 404);
  });

  test('updateStyles replaces served content', () async {
    server.updateStyles({'standard': '{"version":8,"name":"updated"}'});
    final res = await _get('${server.baseUrl}/style/standard.json');
    expect(res.body, contains('updated'));
  });

  test('serves a glyph pbf', () async {
    final res = await _get('${server.baseUrl}/fonts/Noto Sans Regular/0-255.pbf');
    expect(res.statusCode, 200);
    expect(res.bodyBytes, [1, 2, 3]);
  });

  test('404 for a missing tile', () async {
    final res = await _get('${server.baseUrl}/tiles/0/9999/9999.mvt');
    expect(res.statusCode, 404);
  });

  test('404 for path-traversal attempt on fonts route', () async {
    // A traversal payload such as ..%2f..%2fetc%2fpasswd must not escape
    // glyphsDir — the containment check must return 404.
    final res = await _get(
        '${server.baseUrl}/fonts/..%2f..%2f..%2f..%2fetc/passwd');
    expect(res.statusCode, 404);
  });

  test('404 for non-numeric tile coordinates', () async {
    final res = await _get('${server.baseUrl}/tiles/abc/x/y.mvt');
    expect(res.statusCode, 404);
  });

}

Future<_Resp> _get(String url) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  final resp = await req.close();
  final bytes = <int>[];
  await for (final chunk in resp) {
    bytes.addAll(chunk);
  }
  client.close();
  return _Resp(resp.statusCode, bytes);
}

class _Resp {
  _Resp(this.statusCode, this.bodyBytes);
  final int statusCode;
  final List<int> bodyBytes;
  String get body => String.fromCharCodes(bodyBytes);
}
