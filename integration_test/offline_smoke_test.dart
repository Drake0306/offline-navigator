import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_navigator/tiles/tile_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('serves style and a tile from localhost (offline)',
      (tester) async {
    final tiles = TileService();
    late MapReady ready;

    try {
      ready = await tiles.ensureReady();

      // --- assert style.json serves from loopback ---
      final styleRes = await _get(ready.styleUrl);
      expect(styleRes.statusCode, 200,
          reason: 'style.json should return HTTP 200');
      expect(styleRes.body, contains('127.0.0.1'),
          reason: 'style body should contain loopback origin');
      expect(styleRes.body, contains('version'),
          reason: 'style body should contain the "version" key');

      // --- compute the z14 tile for Ghatshila (lat 22.586, lon 86.476) ---
      // Tile coordinates per the slippy-map/Web-Mercator formula:
      //   x = floor((lon + 180) / 360 * 2^z)
      //   y = floor((1 - ln(tan(latRad) + 1/cos(latRad)) / pi) / 2 * 2^z)
      const lat = 22.586;
      const lon = 86.476;

      final z = 14;
      final n = math.pow(2, z).toInt();
      final tileX = ((lon + 180.0) / 360.0 * n).floor();
      final latRad = lat * math.pi / 180.0;
      final tileY = ((1 -
                  (math.log(math.tan(latRad) + 1 / math.cos(latRad)) /
                      math.pi)) /
              2 *
              n)
          .floor();

      final base = ready.base;
      final tileUrl = '$base/tiles/$z/$tileX/$tileY.mvt';
      final tileRes = await _get(tileUrl);

      if (tileRes.statusCode == 200) {
        expect(tileRes.bodyBytes.isNotEmpty, isTrue,
            reason: 'tile response body should be non-empty');
      } else {
        // z14 tile unexpectedly absent — fall back to z12 (same formula).
        final z12 = 12;
        final n12 = math.pow(2, z12).toInt();
        final tileX12 = ((lon + 180.0) / 360.0 * n12).floor();
        final tileY12 = ((1 -
                    (math.log(math.tan(latRad) + 1 / math.cos(latRad)) /
                        math.pi)) /
                2 *
                n12)
            .floor();
        final tileRes12 =
            await _get('$base/tiles/$z12/$tileX12/$tileY12.mvt');
        expect(tileRes12.statusCode, 200,
            reason:
                'z12 fallback tile $z12/$tileX12/$tileY12 should return HTTP 200');
        expect(tileRes12.bodyBytes.isNotEmpty, isTrue,
            reason: 'z12 fallback tile body should be non-empty');
      }
    } finally {
      await tiles.dispose();
    }
  });
}

// ---------------------------------------------------------------------------
// Minimal HTTP helper (dart:io only — no external packages)
// ---------------------------------------------------------------------------

class _Response {
  const _Response(this.statusCode, this.bodyBytes);
  final int statusCode;
  final List<int> bodyBytes;
  String get body => String.fromCharCodes(bodyBytes);
}

Future<_Response> _get(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return _Response(response.statusCode, bytes);
  } finally {
    client.close();
  }
}
