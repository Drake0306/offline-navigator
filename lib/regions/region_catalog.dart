import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:offline_navigator/regions/region.dart';

/// Thrown when the region catalog can't be fetched or parsed.
class RegionCatalogException implements Exception {
  const RegionCatalogException(this.message);
  final String message;
  @override
  String toString() => 'RegionCatalogException: $message';
}

/// The online catalog of downloadable regions (`regions.json`).
class RegionCatalog {
  /// Parse a catalog body. Throws [RegionCatalogException] on a bad schema/shape.
  static List<Region> parse(String body) {
    final Object? j;
    try {
      j = jsonDecode(body);
    } on FormatException catch (e) {
      throw RegionCatalogException('catalog: invalid JSON (${e.message})');
    }
    if (j is! Map || j['schemaVersion'] != 1) {
      throw const RegionCatalogException('unsupported catalog schema');
    }
    final regions = j['regions'];
    if (regions is! List) {
      throw const RegionCatalogException('catalog: regions is not a list');
    }
    try {
      return [for (final r in regions) Region.fromJson(r as Map<String, Object?>)];
    } on FormatException catch (e) {
      throw RegionCatalogException('catalog: ${e.message}');
    }
  }

  /// Fetch + parse the catalog at [url].
  static Future<List<Region>> fetch(http.Client client, Uri url) async {
    final http.Response res;
    try {
      res = await client.get(url);
    } catch (e) {
      throw RegionCatalogException('catalog fetch failed: $e');
    }
    if (res.statusCode != 200) {
      throw RegionCatalogException('catalog fetch failed (${res.statusCode})');
    }
    return parse(res.body);
  }
}
