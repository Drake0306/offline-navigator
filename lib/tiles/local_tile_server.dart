import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:offline_navigator/tiles/pmtiles_reader.dart';

/// In-app HTTP server (127.0.0.1) that feeds offline tiles, glyphs and the
/// style document to MapLibre. Picks a free ephemeral port so multiple
/// launches and test runs never collide.
class LocalTileServer {
  LocalTileServer({
    required this.reader,
    required this.glyphsDir,
    required this.styleJson,
  });

  final PmTilesReader reader;
  final String glyphsDir;
  final String styleJson;

  HttpServer? _server;

  /// The base URL of the running server, e.g. `http://127.0.0.1:54321`.
  /// Throws [StateError] if the server has not been started.
  String get baseUrl {
    final s = _server;
    if (s == null) throw StateError('server not started');
    return 'http://${s.address.host}:${s.port}';
  }

  Future<void> start() async {
    final router = Router();

    // --- /style.json ---
    router.get('/style.json', (Request req) {
      return Response.ok(
        styleJson,
        headers: {'content-type': 'application/json'},
      );
    });

    // --- /tiles/<z>/<x>/<y>.mvt ---
    // shelf_router compiles this to regex ^\/tiles\/([^/]+)\/([^/]+)\/([^/]+)\.mvt$
    // so <z>, <x>, <y> capture just the numeric parts (the literal ".mvt" is
    // matched by the pattern suffix, not included in the captured value).
    router.get('/tiles/<z>/<x>/<y>.mvt',
        (Request req, String z, String x, String y) async {
      final bytes = await reader.readTile(
        int.parse(z),
        int.parse(x),
        int.parse(y),
      );
      if (bytes == null) return Response.notFound('no tile');
      return Response.ok(bytes, headers: {
        'content-type': 'application/x-protobuf',
        'access-control-allow-origin': '*',
      });
    });

    // --- /fonts/<fontstack>/<range>.pbf ---
    // The font-stack name may contain spaces (e.g. "Noto Sans Regular").
    // Dart's HttpClient encodes them as %20 in the request path, so
    // shelf_router captures the URL-encoded form.  Decode before building the
    // file path so we can find the folder on disk.
    router.get('/fonts/<stack>/<range>.pbf',
        (Request req, String stack, String range) async {
      final decodedStack = Uri.decodeComponent(stack);
      final decodedRange = Uri.decodeComponent(range);
      final file = File('$glyphsDir/$decodedStack/$decodedRange.pbf');
      if (!await file.exists()) return Response.notFound('no glyph');
      return Response.ok(
        await file.readAsBytes(),
        headers: {'content-type': 'application/x-protobuf'},
      );
    });

    _server = await shelf_io.serve(
      const Pipeline().addHandler(router.call),
      InternetAddress.loopbackIPv4,
      0, // ephemeral port — avoids collisions across tests and app restarts
    );
  }

  /// Closes the HTTP server and the underlying [PmTilesReader].
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    await reader.close();
  }
}
