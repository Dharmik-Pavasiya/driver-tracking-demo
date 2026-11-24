import 'dart:convert';
import 'dart:io';

import '../data/location_repository.dart';
import '../models/location_record.dart';

/// A real REST mock that starts automatically inside the installed app.
/// It listens only on this phone's loopback address; no computer or LAN IP is needed.
class MockApiService {
  /// Uses a separate acceptance table in the app's persistent SQLite database.
  MockApiService(this.repository);
  final LocationRepository repository;
  HttpServer? _server;

  /// Chooses a free local port and returns the URL used by LocationApi.
  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    return 'http://127.0.0.1:${_server!.port}';
  }

  /// Handles only the small API needed by this demo.
  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    try {
      if (request.method == 'GET' && request.uri.path == '/locations') {
        final rows = await repository.mockRecords();
        _reply(request, 200, {'count': rows.length, 'locations': rows});
      } else if (request.method == 'POST' && request.uri.path == '/locations') {
        await _saveLocation(request);
      } else {
        _reply(request, 404, {'error': 'Route not found'});
      }
    } on FormatException {
      _reply(request, 400, {'error': 'Invalid location JSON'});
    } on TypeError {
      _reply(request, 400, {'error': 'Missing location fields'});
    } catch (_) {
      _reply(request, 500, {'error': 'Mock storage failed'});
    }
    await request.response.close();
  }

  /// Persists one ID before acknowledging it, including simulated failures.
  Future<void> _saveLocation(HttpRequest request) async {
    final body = jsonDecode(
      await utf8.decoder.bind(request).join(),
    ) as Map<String, dynamic>;
    final record = LocationRecord.fromPayload(body);
    if (record.id.isEmpty ||
        request.headers.value('Idempotency-Key') != record.id ||
        record.latitude.abs() > 90 ||
        record.longitude.abs() > 180 ||
        !record.latitude.isFinite ||
        !record.longitude.isFinite) {
      _reply(request, 400, {'error': 'Invalid location or idempotency key'});
      return;
    }
    final failure = request.headers.value('X-Demo-Failure');
    final alreadySaved = await repository.mockContains(record.id);
    if (!alreadySaved && failure == 'beforeCommit') {
      _reply(request, 503, {'error': 'Failure before saving'});
      return;
    }
    final result = await repository.acceptMock(record);
    if (result == MockResult.conflict) {
      _reply(request, 409, {'error': 'This ID has another payload'});
    } else if (result == MockResult.created && failure == 'afterCommit') {
      _reply(request, 503, {'error': 'Failure after saving'});
    } else {
      _reply(request, result == MockResult.created ? 201 : 200, {
        'id': record.id,
        'accepted': true,
        'duplicate': result == MockResult.duplicate,
      });
    }
  }

  /// Writes one JSON reply with an explicit status.
  void _reply(HttpRequest request, int status, Map<String, dynamic> body) {
    request.response.statusCode = status;
    request.response.write(jsonEncode(body));
  }

  /// Stops the local listener when the app's dependencies are released.
  Future<void> close() async => await _server?.close(force: true);
}
