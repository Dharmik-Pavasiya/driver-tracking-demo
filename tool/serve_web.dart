import 'dart:io';

import 'package:path/path.dart' as path;

/// Minimal localhost static server for the compiled Flutter demonstration.
Future<void> main() async {
  final root = path.normalize(path.absolute('build/web'));
  final server = await HttpServer.bind('127.0.0.1', 8080);
  stdout.writeln('Flutter preview: http://127.0.0.1:8080');
  await for (final request in server) {
    try {
      final requested = request.uri.path == '/'
          ? 'index.html'
          : request.uri.path.substring(1);
      final target = path.normalize(path.join(root, requested));
      if (!path.isWithin(root, target)) {
        request.response.statusCode = 403;
      } else {
        final file = File(target);
        if (!await file.exists()) {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = switch (path.extension(
            target,
          )) {
            '.html' => ContentType.html,
            '.js' => ContentType('application', 'javascript'),
            '.json' => ContentType.json,
            '.wasm' => ContentType('application', 'wasm'),
            '.png' => ContentType('image', 'png'),
            '.css' => ContentType('text', 'css'),
            _ => ContentType.binary,
          };
          await request.response.addStream(file.openRead());
        }
      }
    } catch (_) {
      request.response.statusCode = 500;
    }
    await request.response.close();
  }
}
