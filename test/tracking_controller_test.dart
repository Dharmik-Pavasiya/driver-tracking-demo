import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:driver_tracking_demo/data/location_repository.dart';
import 'package:driver_tracking_demo/models/location_record.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/controller/tracking_controller.dart';
import 'package:driver_tracking_demo/services/connectivity_service.dart';
import 'package:driver_tracking_demo/services/location_api.dart';
import 'package:driver_tracking_demo/services/location_service.dart';
import 'package:driver_tracking_demo/services/mock_api_service.dart';
import 'package:driver_tracking_demo/services/sync_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Gives the controller manual GPS fixes, without device permission dialogs.
class TestLocationSource implements LocationSource {
  final points = StreamController<LocationRecord>();
  Completer<void>? permission;
  int starts = 0;
  @override
  Future<void> prepare() async => await permission?.future;
  @override
  Stream<LocationRecord> start() {
    starts++;
    return points.stream;
  }
}

Future<void> waitUntil(bool Function() ready) async {
  for (var count = 0; count < 200; count++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Expected state did not arrive');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocationRepository repository;
  late MockApiService mock;
  late ConnectivityService network;
  late RestLocationApi api;
  late SyncService sync;
  late TestLocationSource source;
  late TrackingController controller;
  late StreamController<List<ConnectivityResult>> events;
  late bool connected;
  setUp(() async {
    repository = LocationRepository(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    await repository.initialize();
    mock = MockApiService(repository);
    // Widget test bindings block real HTTP. The separate phone-mock tests use
    // real sockets; this controller test supplies an HTTP client explicitly.
    api = RestLocationApi(
      baseUrl: 'http://mock',
      client: MockClient((request) async {
        final record = LocationRecord.fromPayload(
          jsonDecode(request.body) as Map<String, dynamic>,
        );
        await repository.acceptMock(record);
        return http.Response(
          jsonEncode({'id': record.id, 'accepted': true}),
          201,
        );
      }),
    );
    connected = false;
    events = StreamController<List<ConnectivityResult>>();
    network = ConnectivityService(
      transport: () async => [
        connected ? ConnectivityResult.wifi : ConnectivityResult.none,
      ],
      changes: events.stream,
      client: MockClient((_) async => http.Response('', 204)),
    );
    sync = SyncService(repository: repository, api: api, connection: network);
    await sync.startAutomaticSync();
    source = TestLocationSource();
    controller = TrackingController(
      repository: repository,
      source: source,
      api: api,
      sync: sync,
    );
    controller.onInit();
  });
  tearDown(() async {
    await controller.closeResources();
    await sync.close();
    await network.close();
    await source.points.close();
    await events.close();
    api.close();
    await mock.close();
    await repository.database.close();
  });
  test('background capture stays local until real internet returns, even after Stop', () async {
    await controller.startTracking();
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    source.points.add(
      LocationRecord(
        id: 'background',
        latitude: 12.97,
        longitude: 77.59,
        capturedAt: DateTime.utc(2026),
      ),
    );
    await waitUntil(() => sync.pending == 1);
    expect(controller.isTracking.value, isTrue);
    expect(await repository.mockRecords(), isEmpty);
    await controller.stopTracking();
    connected = true;
    events.add([ConnectivityResult.wifi]);
    await waitUntil(() => sync.synced == 1);
    expect(sync.pending, 0);
    expect((await repository.mockRecords()).length, 1);
  });
  test(
    'double Start during permission preparation creates only one stream',
    () async {
      source.permission = Completer<void>();
      final start = controller.startTracking();
      await controller.startTracking();
      source.permission!.complete();
      await start;
      expect(source.starts, 1);
    },
  );
}
