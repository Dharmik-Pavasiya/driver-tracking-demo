import 'package:driver_tracking_demo/data/location_repository.dart';
import 'package:driver_tracking_demo/models/location_record.dart';
import 'package:driver_tracking_demo/services/location_api.dart';
import 'package:driver_tracking_demo/services/mock_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the exact phone mock with HTTP and SQLite, without any external backend.
void main() {
  sqfliteFfiInit();
  late LocationRepository repository;
  late MockApiService server;
  late RestLocationApi api;
  final record = LocationRecord(
    id: 'phone-point',
    latitude: 12.97,
    longitude: 77.59,
    capturedAt: DateTime.utc(2026),
  );
  setUp(() async {
    repository = LocationRepository(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    await repository.initialize();
    server = MockApiService(repository);
    api = RestLocationApi(baseUrl: await server.start());
  });
  tearDown(() async {
    api.close();
    await server.close();
    await repository.database.close();
  });

  test(
    'install-and-run mock accepts HTTP uploads without a computer URL',
    () async {
      expect(api.baseUrl, startsWith('http://127.0.0.1:'));
      await api.upload(record);
      expect((await repository.mockRecords()).length, 1);
    },
  );
  test(
    'saved mock acceptance survives server restart and failed acknowledgement',
    () async {
      api.failure = DemoFailure.afterCommit;
      await expectLater(api.upload(record), throwsA(isA<UploadException>()));
      await server.close();
      api.close();
      server = MockApiService(repository);
      api = RestLocationApi(baseUrl: await server.start())
        ..failure = DemoFailure.afterCommit;
      await api.upload(record);
      await api.upload(record);
      expect((await repository.mockRecords()).length, 1);
    },
  );
  test('same ID with another payload is rejected', () async {
    await api.upload(record);
    final changed = LocationRecord(
      id: record.id,
      latitude: 13,
      longitude: record.longitude,
      capturedAt: record.capturedAt,
    );
    await expectLater(
      api.upload(changed),
      throwsA(
        isA<UploadException>().having((e) => e.retryable, 'retryable', false),
      ),
    );
    expect((await repository.mockRecords()).length, 1);
  });
}
