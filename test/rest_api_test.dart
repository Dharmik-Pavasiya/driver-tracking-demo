import 'dart:convert';

import 'package:driver_tracking_demo/models/location_record.dart';
import 'package:driver_tracking_demo/services/location_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Checks request identity and acknowledgement validation without native plugins.
void main() {
  const id = 'stable-id';
  final point = LocationRecord(
    id: id,
    latitude: 12.97,
    longitude: 77.59,
    capturedAt: DateTime.utc(2026),
  );

  test('POST uses stable idempotency key and payload', () async {
    final api = RestLocationApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async {
        expect(request.headers['Idempotency-Key'], id);
        expect(jsonDecode(request.body), point.toPayload());
        return http.Response(jsonEncode({'id': id, 'accepted': true}), 201);
      }),
    );
    addTearDown(api.close);
    await api.upload(point);
  });

  test(
    'a mismatched acknowledgement never marks an upload successful',
    () async {
      final api = RestLocationApi(
        baseUrl: 'http://localhost',
        client: MockClient(
          (_) async => http.Response('{"id":"other","accepted":true}', 200),
        ),
      );
      addTearDown(api.close);
      await expectLater(api.upload(point), throwsA(isA<UploadException>()));
    },
  );
}
