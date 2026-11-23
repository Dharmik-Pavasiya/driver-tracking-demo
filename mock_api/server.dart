import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local-only mock with durable deduplication and serialized request handling.
class MockLocationServer {
  MockLocationServer({required this.storage});
  final File storage;
  final Map<String, Map<String, dynamic>> _accepted = {};
  HttpServer? _server;
  Future<void> _requests = Future.value();
  int get acceptedCount => _accepted.length;
  int get port => _server!.port;

  Future<void> start({int port = 8081, String host = '127.0.0.1'}) async {
    if (await storage.exists()) {
      final saved = jsonDecode(await storage.readAsString()) as List<dynamic>;
      for (final row in saved.cast<Map<String, dynamic>>()) {
        _accepted[row['id'] as String] = row;
      }
    }
    _server = await HttpServer.bind(host, port);
    _server!.listen((request) {
      _requests = _requests.then((_) => _handle(request)).catchError((
        Object _,
      ) {
        // A disconnected client must not poison the serialized request chain.
      });
    });
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Content-Type,Idempotency-Key,X-Demo-Failure',
      )
      ..contentType = ContentType.json;
    try {
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 204;
      } else if (request.method == 'GET' && request.uri.path == '/health') {
        _reply(request, 200, {'ok': true});
      } else if (request.method == 'GET' && request.uri.path == '/locations') {
        _reply(request, 200, {
          'count': acceptedCount,
          'locations': _accepted.values.toList(),
        });
      } else if (request.method == 'POST' && request.uri.path == '/locations') {
        final payload = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        final id = payload['id'];
        final lat = payload['latitude'];
        final lon = payload['longitude'];
        final timestamp = payload['capturedAt'];
        if (id is! String ||
            id.isEmpty ||
            id != request.headers.value('Idempotency-Key') ||
            lat is! num ||
            !lat.isFinite ||
            lat < -90 ||
            lat > 90 ||
            lon is! num ||
            !lon.isFinite ||
            lon < -180 ||
            lon > 180 ||
            timestamp is! String ||
            DateTime.tryParse(timestamp) == null) {
          _reply(request, 400, {
            'error': 'Invalid location or idempotency key',
          });
        } else {
          final canonical = <String, dynamic>{
            'id': id,
            'latitude': lat,
            'longitude': lon,
            'capturedAt': timestamp,
          };
          final existing = _accepted[id];
          if (existing != null &&
              jsonEncode(existing) != jsonEncode(canonical)) {
            _reply(request, 409, {
              'error': 'ID already exists with different payload',
            });
          } else if (existing != null) {
            _reply(request, 200, {
              'accepted': true,
              'id': id,
              'duplicate': true,
            });
          } else if (request.headers.value('X-Demo-Failure') ==
              'beforeCommit') {
            _reply(request, 503, {'error': 'Simulated failure before commit'});
          } else {
            // Commit before injecting a failed acknowledgement. Replay must succeed.
            await storage.parent.create(recursive: true);
            final temporary = File('${storage.path}.tmp');
            await temporary.writeAsString(
              jsonEncode([..._accepted.values, canonical]),
              flush: true,
            );
            await temporary.rename(storage.path);
            _accepted[id] = canonical;
            if (request.headers.value('X-Demo-Failure') == 'afterCommit') {
              _reply(request, 503, {'error': 'Simulated failure after commit'});
            } else {
              _reply(request, 201, {
                'accepted': true,
                'id': id,
                'duplicate': false,
              });
            }
          }
        }
      } else {
        _reply(request, 404, {'error': 'Route not found'});
      }
    } on FormatException {
      _reply(request, 400, {'error': 'Invalid JSON'});
    } on TypeError {
      _reply(request, 400, {'error': 'Expected a JSON object'});
    } catch (_) {
      _reply(request, 500, {'error': 'Mock server storage failure'});
    } finally {
      await request.response.close();
    }
  }

  void _reply(HttpRequest request, int code, Map<String, dynamic> body) {
    request.response.statusCode = code;
    request.response.write(jsonEncode(body));
  }

  Future<void> close() async {
    await _server?.close(force: true);
    await _requests;
  }
}

Future<void> main(List<String> args) async {
  final server = MockLocationServer(
    storage: File('mock_api/data/locations.json'),
  );
  await server.start(
    port: args.isEmpty ? 8081 : int.parse(args.first),
    host: args.length > 1 ? args[1] : '127.0.0.1',
  );
  stdout.writeln('Mock API listening on http://127.0.0.1:${server.port}');
  stdout.writeln(
    'GET /locations shows unique accepted records. Ctrl+C to stop.',
  );
}
