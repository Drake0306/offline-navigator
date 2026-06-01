import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_navigator/regions/region_catalog.dart';

const _catalog = '''
{"schemaVersion":1,"regions":[
  {"id":"in-jh-east-singhbhum","name":"East Singhbhum","state":"Jharkhand",
   "bbox":[86.0,22.2,86.9,23.1],"version":1,
   "files":{"tiles":{"url":"https://x/t","bytes":1,"sha256":"a"},
            "valhalla":{"url":"https://x/v","bytes":2,"sha256":"b"},
            "admins":{"url":"https://x/a","bytes":3,"sha256":"c"},
            "search":{"url":"https://x/s","bytes":4,"sha256":"d"}}}
]}''';

void main() {
  test('parses a valid catalog', () {
    final regions = RegionCatalog.parse(_catalog);
    expect(regions, hasLength(1));
    expect(regions.single.id, 'in-jh-east-singhbhum');
  });

  test('rejects an unsupported schema version', () {
    expect(() => RegionCatalog.parse('{"schemaVersion":99,"regions":[]}'),
        throwsA(isA<RegionCatalogException>()));
  });

  test('rejects regions that is not a list', () {
    expect(() => RegionCatalog.parse('{"schemaVersion":1,"regions":{}}'),
        throwsA(isA<RegionCatalogException>()));
  });

  test('fetch returns parsed regions on 200', () async {
    final client = MockClient((req) async => http.Response(_catalog, 200));
    final regions = await RegionCatalog.fetch(client, Uri.parse('https://x/regions.json'));
    expect(regions.single.name, 'East Singhbhum');
  });

  test('fetch throws on non-200', () async {
    final client = MockClient((req) async => http.Response('nope', 404));
    expect(() => RegionCatalog.fetch(client, Uri.parse('https://x/regions.json')),
        throwsA(isA<RegionCatalogException>()));
  });
}
