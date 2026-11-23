import 'dart:convert';
import 'dart:io';

import 'package:driver_tracking_demo/screens/tracking_screen/data/location_record.dart';
import 'package:driver_tracking_demo/network/api_provider/location_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../mock_api/server.dart';

/// Checks the HTTP contract and real mock-server idempotency behavior.
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

  test(
    'failure after server commit survives restart and replay has no duplicate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'driver_api_test_',
      );
      final storage = File('${directory.path}/accepted.json');
      var server = MockLocationServer(storage: storage);
      await server.start(port: 0);
      var api = RestLocationApi(baseUrl: 'http://127.0.0.1:${server.port}')
        ..failure = DemoFailure.afterCommit;
      try {
        await expectLater(api.upload(point), throwsA(isA<UploadException>()));
        expect(server.acceptedCount, 1);
        api.close();
        await server.close();
        server = MockLocationServer(storage: storage);
        await server.start(port: 0);
        api = RestLocationApi(baseUrl: 'http://127.0.0.1:${server.port}')
          ..failure = DemoFailure.afterCommit;
        await api.upload(point); // Duplicate is acknowledged even while failure injection remains enabled.
        await api.upload(point);
        expect(server.acceptedCount, 1);
        final response = await http.get(
          Uri.parse('http://127.0.0.1:${server.port}/locations'),
        );
        expect(jsonDecode(response.body)['count'], 1);
      } finally {
        api.close();
        await server.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('reusing an ID with changed coordinates is rejected with 409', () async {
    final directory = await Directory.systemTemp.createTemp(
      'driver_conflict_test_',
    );
    final server = MockLocationServer(
      storage: File('${directory.path}/accepted.json'),
    );
    await server.start(port: 0);
    final api = RestLocationApi(baseUrl: 'http://127.0.0.1:${server.port}');
    try {
      await api.upload(point);
      final changed = LocationRecord(
        id: id,
        latitude: 13,
        longitude: 77.59,
        capturedAt: point.capturedAt,
      );
      await expectLater(
        api.upload(changed),
        throwsA(
          isA<UploadException>().having((e) => e.retryable, 'retryable', false),
        ),
      );
      expect(server.acceptedCount, 1);
    } finally {
      api.close();
      await server.close();
      await directory.delete(recursive: true);
    }
  });
}
