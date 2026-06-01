import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/regions/region.dart';

void main() {
  const json = '''
  {"id":"in-jh-east-singhbhum","name":"East Singhbhum (Jamshedpur)","state":"Jharkhand",
   "bbox":[86.0,22.2,86.9,23.1],"version":1,
   "files":{"tiles":{"url":"https://x/t.pmtiles","bytes":10,"sha256":"aa"},
            "valhalla":{"url":"https://x/v.tar","bytes":20,"sha256":"bb"},
            "admins":{"url":"https://x/a.sqlite","bytes":30,"sha256":"cc"},
            "search":{"url":"https://x/s.sqlite","bytes":40,"sha256":"dd"}}}''';

  test('parses a region entry', () {
    final r = Region.fromJson(jsonDecode(json) as Map<String, Object?>);
    expect(r.id, 'in-jh-east-singhbhum');
    expect(r.name, contains('Jamshedpur'));
    expect(r.bbox.minLon, 86.0);
    expect(r.bbox.center.lat, closeTo(22.65, 1e-9));
    expect(r.files['tiles']!.sha256, 'aa');
    expect(r.version, 1);
  });

  test('missing files throws FormatException', () {
    expect(
      () => Region.fromJson({'id': 'x', 'name': 'y', 'bbox': [0, 0, 1, 1], 'version': 1}),
      throwsFormatException,
    );
  });

  test('round-trips through toJson', () {
    final r = Region.fromJson(jsonDecode(json) as Map<String, Object?>);
    final r2 = Region.fromJson(r.toJson());
    expect(r2.id, r.id);
    expect(r2.files['search']!.bytes, 40);
    expect(r2.bbox.maxLat, 23.1);
  });
}
