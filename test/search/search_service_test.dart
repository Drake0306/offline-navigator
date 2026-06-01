import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_navigator/search/search_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<SearchService> seeded() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''CREATE TABLE features(
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_en TEXT,
      kind TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
      search TEXT NOT NULL)''');
    await db.execute('CREATE INDEX idx_features_search ON features(search)');
    Future<void> ins(String name, String? en, String kind, double lat,
            double lon, String search) =>
        db.insert('features', {
          'name': name, 'name_en': en, 'kind': kind,
          'lat': lat, 'lon': lon, 'search': search,
        });
    // Two "ghatshila"-ish rows at different distances + an unrelated row.
    await ins('Ghatshila', 'Ghatshila', 'place', 22.586, 86.476, 'ghatshila ghatshila');
    await ins('Ghatshila Station', 'Ghatshila Station', 'poi', 22.600, 86.470,
        'ghatshila station ghatshila station');
    await ins('Galudih', 'Galudih', 'place', 22.560, 86.700, 'galudih galudih');
    // A Devanagari-named row with name_en empty (matches only local script).
    await ins('घाटशिला', '', 'place', 22.590, 86.480, 'घाटशिला');
    return SearchService.forTesting(db);
  }

  test('prefix LIKE matches and ranks nearest-first from origin', () async {
    final s = await seeded();
    final res = await s.query('ghat', originLat: 22.586, originLng: 86.476);
    expect(res.length, 2);
    // Ghatshila (0 km) before Ghatshila Station (~1.8 km).
    expect(res.first.name, 'Ghatshila');
    expect(res[1].name, 'Ghatshila Station');
    expect(res.first.distanceM, lessThan(res[1].distanceM!));
  });

  test('non-matching query returns empty', () async {
    final s = await seeded();
    expect((await s.query('zzz', originLat: 22.586, originLng: 86.476)), isEmpty);
  });

  test('empty query returns empty without hitting the db', () async {
    final s = await seeded();
    expect((await s.query('   ', originLat: 22.586, originLng: 86.476)), isEmpty);
  });

  test('local-script query matches the Devanagari row', () async {
    final s = await seeded();
    final res = await s.query('घाट', originLat: 22.586, originLng: 86.476);
    expect(res.map((r) => r.name), contains('घाटशिला'));
  });

  test('respects the limit', () async {
    final s = await seeded();
    final res = await s.query('ghat', originLat: 22.586, originLng: 86.476, limit: 1);
    expect(res.length, 1);
  });
}
