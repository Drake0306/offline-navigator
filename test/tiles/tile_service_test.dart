import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/tiles/tile_service.dart';

void main() {
  test('rewriteStyle replaces __BASE__ with the server origin', () {
    const tmpl = '{"glyphs":"__BASE__/fonts/{fontstack}/{range}.pbf",'
        '"sources":{"p":{"tiles":["__BASE__/tiles/{z}/{x}/{y}.mvt"]}}}';
    final out = TileService.rewriteStyle(tmpl, 'http://127.0.0.1:5599');
    expect(out, contains('http://127.0.0.1:5599/fonts/{fontstack}/{range}.pbf'));
    expect(out, contains('http://127.0.0.1:5599/tiles/{z}/{x}/{y}.mvt'));
    expect(out, isNot(contains('__BASE__')));
  });
}
