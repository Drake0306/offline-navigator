import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/tiles/pmtiles_reader.dart';

void main() {
  const fixture = 'assets/tiles/ghatshila.pmtiles';

  test('opens archive and reports zoom range', () async {
    final reader = await PmTilesReader.open(fixture);
    expect(reader.maxZoom, greaterThanOrEqualTo(reader.minZoom));
    await reader.close();
  });

  test('returns non-empty bytes for a covered tile', () async {
    final reader = await PmTilesReader.open(fixture);
    // Ghatshila center at z12: standard slippy-tile formula.
    const z = 12;
    final n = 1 << z;
    const lat = 22.586, lon = 86.476;
    final x = ((lon + 180.0) / 360.0 * n).floor();
    final latRad = lat * math.pi / 180.0;
    final y =
        ((1 - (math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi)) /
                2 *
                n)
            .floor();
    final bytes = await reader.readTile(z, x, y);
    expect(bytes, isNotNull);
    expect(bytes!.isNotEmpty, isTrue);
    await reader.close();
  });
}
