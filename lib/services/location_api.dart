import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/location_record.dart';

class UploadException implements Exception {
  const UploadException(this.message, {this.retryable = true});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

abstract interface class LocationApi {
  Future<void> upload(LocationRecord record);
}

enum DemoFailure { none, beforeCommit, afterCommit }

class RestLocationApi implements LocationApi {
  RestLocationApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  DemoFailure failure = DemoFailure.none;

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

  void close() => _client.close();
}
