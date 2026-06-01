import 'dart:io';
import 'package:path/path.dart' as p;
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
    required Map<String, String> styles,
  }) : _styles = Map<String, String>.from(styles);

  final PmTilesReader reader;
  final String glyphsDir;
  Map<String, String> _styles;

  /// Replaces all served styles (called after [start] once the baseUrl —
  /// and therefore the rewritten `__BASE__` — is known).
  void updateStyles(Map<String, String> styles) =>
      _styles = Map<String, String>.from(styles);

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

    // --- /style/<name>.json ---
    router.get('/style/<name>.json', (Request req, String name) {
      final json = _styles[name];
      if (json == null) return Response.notFound('no style');
      return Response.ok(json, headers: {'content-type': 'application/json'});
    });

    // --- /tiles/<z>/<x>/<y>.mvt ---
    // shelf_router compiles this to regex ^\/tiles\/([^/]+)\/([^/]+)\/([^/]+)\.mvt$
    // so <z>, <x>, <y> capture just the numeric parts (the literal ".mvt" is
    // matched by the pattern suffix, not included in the captured value).
    router.get('/tiles/<z>/<x>/<y>.mvt',
        (Request req, String z, String x, String y) async {
      final zi = int.tryParse(z);
      final xi = int.tryParse(x);
      final yi = int.tryParse(y);
      if (zi == null || xi == null || yi == null) {
        return Response.notFound('no tile');
      }
      final bytes = await reader.readTile(zi, xi, yi);
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
      final base = p.normalize(Directory(glyphsDir).absolute.path);
      final target = p.normalize(
        File('$glyphsDir/$decodedStack/$decodedRange.pbf').absolute.path,
      );
      if (!p.isWithin(base, target)) {
        return Response.notFound('glyph not found');
      }
      final file = File(target);
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
