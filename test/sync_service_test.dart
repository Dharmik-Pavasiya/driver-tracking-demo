import 'dart:async';
import 'dart:io';

import 'package:driver_tracking_demo/data/location_repository.dart';
import 'package:driver_tracking_demo/domain/location_record.dart';
import 'package:driver_tracking_demo/services/location_api.dart';
import 'package:driver_tracking_demo/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LocationRecord point(String id) => LocationRecord(
  id: id,
  latitude: 12.9716,
  longitude: 77.5946,
  capturedAt: DateTime.utc(2026, 1, 1),
);

class FakeApi implements LocationApi {
  int calls = 0;
  final Set<String> accepted = {};
  Object? failure;
  Completer<void>? gate;
  @override
  Future<void> upload(LocationRecord record) async {
    calls++;
    await gate?.future;
    if (failure != null) throw failure!;
    accepted.add(record.id);
  }
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocationRepository repository;
  late FakeApi api;
  late SyncService sync;
  late bool online;
  late DateTime clock;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('driver_sync_test_');
    repository = LocationRepository(
      await databaseFactoryFfi.openDatabase('${directory.path}/outbox.db'),
    );
    await repository.initialize();
    api = FakeApi();
    online = false;
    clock = DateTime.utc(2026, 1, 1);
    sync = SyncService(
      repository: repository,
      api: api,
      isOnline: () => online,
      now: () => clock,
      backoff: (attempt) => Duration(seconds: 2 * (1 << (attempt - 1))),
    );
  });
  tearDown(() async {
    sync.dispose();
    await repository.database.close();
    await directory.delete(recursive: true);
  });

  test(
    'offline capture survives reopening SQLite and then synchronizes',
    () async {
      await repository.enqueue(point('offline'));
      await sync.synchronize();
      expect(api.calls, 0);
      await repository.database.close();
      repository = LocationRepository(
        await databaseFactoryFfi.openDatabase('${directory.path}/outbox.db'),
      );
      await repository.initialize();
      expect((await repository.all()).single.status, UploadStatus.pending);
      sync.dispose();
      sync = SyncService(
        repository: repository,
        api: api,
        isOnline: () => online,
      );
      online = true;
      await sync.synchronize();
      expect((await repository.all()).single.status, UploadStatus.synced);
      expect(api.accepted, {'offline'});
    },
  );

  test('duplicate enqueue and repeated sync submit one record', () async {
    await repository.enqueue(point('same'));
    await repository.enqueue(point('same'));
    online = true;
    await sync.synchronize();
    await sync.synchronize();
    expect((await repository.all()).length, 1);
    expect(api.calls, 1);
  });

  test(
    'failure and retry deadline persist; early retries do not upload',
    () async {
      await repository.enqueue(point('retry'));
      online = true;
      api.failure = const UploadException('HTTP 503');
      await sync.synchronize();
      final failed = (await repository.all()).single;
      expect(failed.attempts, 1);
      expect(failed.status, UploadStatus.pending);
      expect(failed.nextAttemptAt, clock.add(const Duration(seconds: 2)));
      await repository.database.close();
      repository = LocationRepository(
        await databaseFactoryFfi.openDatabase('${directory.path}/outbox.db'),
      );
      sync.dispose();
      sync = SyncService(
        repository: repository,
        api: api,
        isOnline: () => online,
        now: () => clock,
        backoff: (_) => const Duration(seconds: 4),
      );
      await sync.synchronize();
      expect(api.calls, 1);
      api.failure = null;
      clock = clock.add(const Duration(seconds: 2));
      await sync.synchronize();
      expect((await repository.all()).single.status, UploadStatus.synced);
      expect((await repository.all()).single.attempts, 2);
      expect(api.calls, 2);
    },
  );

  test(
    'overlapping triggers share one drain and preserve concurrent GPS inserts',
    () async {
      await repository.enqueue(point('first'));
      online = true;
      api.gate = Completer<void>();
      final first = sync.synchronize();
      final second = sync.synchronize();
      expect(identical(first, second), isTrue);
      // Let the first upload enter its gate, then capture another GPS point.
      while (api.calls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await repository.enqueue(point('during-upload'));
      api.gate!.complete();
      await Future.wait([first, second]);
      expect(api.calls, 2);
      expect(api.accepted, {'first', 'during-upload'});
      expect(
        (await repository.all()).every(
          (row) => row.status == UploadStatus.synced,
        ),
        isTrue,
      );
    },
  );

  test('a permanent API rejection is blocked until explicit retry', () async {
    await repository.enqueue(point('bad'));
    online = true;
    api.failure = const UploadException('HTTP 400', retryable: false);
    await sync.synchronize();
    clock = clock.add(const Duration(days: 1));
    await sync.synchronize();
    expect(api.calls, 1);
    expect((await repository.all()).single.status, UploadStatus.blocked);
    api.failure = null;
    await repository.retryNow();
    await sync.synchronize();
    expect((await repository.all()).single.status, UploadStatus.synced);
  });

  test('transport timeout keeps record pending for retry', () async {
    await repository.enqueue(point('timeout'));
    online = true;
    api.failure = TimeoutException('Network timeout');
    await sync.synchronize();
    expect((await repository.all()).single.status, UploadStatus.pending);
    expect((await repository.all()).single.lastError, contains('timeout'));
  });
}
