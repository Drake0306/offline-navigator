import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:offline_navigator/search/search_result.dart';
import 'package:offline_navigator/search/search_screen.dart' show SearchQuerier;
import 'package:offline_navigator/search/text_normalize.dart';

/// Bump when the bundled search DB changes so storage is refreshed.
const String kSearchDbVersion = '1';
const String _kAsset = 'assets/search/ghatshila.sqlite';

/// Offline place search over a bundled SQLite DB (normalized `search` column,
/// queried with LIKE — no FTS5, so it works on every Android/SQLite version).
class SearchService implements SearchQuerier {
  SearchService._(this._db);

  /// Production constructor: copy the bundled DB to storage, open read-only.
  static Future<SearchService> open() async {
    final dir = await getApplicationSupportDirectory();
    final dest = p.join(dir.path, 'search', 'ghatshila.sqlite');
    final stamp = File(p.join(dir.path, 'search', '.db_version'));
    final needsCopy = !await File(dest).exists() ||
        !await stamp.exists() ||
        (await stamp.readAsString()).trim() != kSearchDbVersion;
    if (needsCopy) {
      final bytes = await rootBundle.load(_kAsset);
      final f = File(dest);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await stamp.writeAsString(kSearchDbVersion);
    }
    final db = await openDatabase(dest, readOnly: true);
    return SearchService._(db);
  }

  /// Open an already-on-disk region search DB (read-only). Used by the region
  /// download manager; unlike [open] it does not copy from bundled assets.
  static Future<SearchService> openForRegion(String dbPath) async {
    final db = await openDatabase(dbPath, readOnly: true);
    return SearchService._(db);
  }

  /// Test constructor: use an already-open database.
  @visibleForTesting
  factory SearchService.forTesting(Database db) = SearchService._;

  final Database _db;

  /// Returns up to [limit] results whose normalized name starts with, or
  /// contains a word starting with, the normalized [text]; ranked by distance
  /// from (originLat, originLng) ascending, then by match quality (prefix
  /// before mid-word).
  @override
  Future<List<SearchResult>> query(
    String text, {
    required double originLat,
    required double originLng,
    int limit = 30,
  }) async {
    final norm = normalizeSearch(text);
    if (norm.isEmpty) return const [];
    final prefix = '$norm%';
    final word = '% $norm%';
    final rows = await _db.rawQuery(
      'SELECT name, name_en, kind, lat, lon, search FROM features '
      'WHERE search LIKE ? OR search LIKE ? LIMIT ?',
      [prefix, word, limit * 4], // over-fetch, then distance-rank + trim
    );
    final results = rows.map((r) {
      final res = SearchResult(
        name: r['name'] as String,
        nameEn: (r['name_en'] as String?)?.isEmpty ?? true
            ? null
            : r['name_en'] as String,
        kind: r['kind'] as String,
        lat: (r['lat'] as num).toDouble(),
        lng: (r['lon'] as num).toDouble(),
      ).withDistanceFrom(originLat, originLng);
      final isPrefix = (r['search'] as String).startsWith(norm);
      return (res: res, isPrefix: isPrefix);
    }).toList();
    // Sort: nearest first; tiebreak prefix-matches above mid-word matches.
    results.sort((a, b) {
      final d = a.res.distanceM!.compareTo(b.res.distanceM!);
      if (d != 0) return d;
      if (a.isPrefix != b.isPrefix) return a.isPrefix ? -1 : 1;
      return 0;
    });
    return results.take(limit).map((e) => e.res).toList();
  }

  Future<void> dispose() => _db.close();
}
