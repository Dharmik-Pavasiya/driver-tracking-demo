import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/location_record.dart';

/// Describes an API failure and whether automatic retry can resolve it.
class UploadException implements Exception {
  /// Permanent validation errors set retryable to false.
  const UploadException(this.message, {this.retryable = true});
  final String message;
  final bool retryable;

  /// Supplies readable error text for the saved record and screen.
  @override
  String toString() => message;
}

/// Small HTTP contract used by synchronization and its test fakes.
abstract interface class LocationApi {
  /// Completes only when the API acknowledges this exact record ID.
  Future<void> upload(LocationRecord record);
}

/// Mock-only controls for rejection and a failed acknowledgement after saving.
enum DemoFailure { none, beforeCommit, afterCommit }

/// Uploads one point with a stable Idempotency-Key to the local REST mock.
class RestLocationApi implements LocationApi {
  /// Accepts an HTTP client in tests, or creates the normal client on a phone.
  RestLocationApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  DemoFailure failure = DemoFailure.none;

  /// Sends the saved payload, handles HTTP failures and validates the reply.
  /// A timeout or invalid reply keeps the row pending rather than losing it.
  @override
  Future<void> upload(LocationRecord record) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/locations'),
          headers: {
            'Content-Type': 'application/json',
            'Idempotency-Key': record.id,
            'X-Demo-Failure': failure.name,
          },
          body: jsonEncode(record.toPayload()),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 201) {
      final code = response.statusCode;
      throw UploadException(
        'HTTP $code: upload was not acknowledged',
        retryable: code >= 500 || code == 408 || code == 429,
      );
    }
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['id'] != record.id || body['accepted'] != true) {
        throw const FormatException('Mismatched acknowledgement');
      }
    } catch (_) {
      throw const UploadException('Invalid API acknowledgement');
    }
  }

  /// Releases the HTTP client after all uploads have stopped.
  void close() => _client.close();
}
