import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:driver_tracking_demo/network/api_provider/location_api.dart';
import 'package:driver_tracking_demo/network/connectivity/network_connectivity.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/controller/tracking_controller.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/data/location_record.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/data/location_repository.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/service/location_service.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/service/sync_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Supplies GPS fixes manually so a controller test does not access real GPS.
class TestLocationSource implements LocationSource {
  final points = StreamController<LocationRecord>();
  Completer<void>? permission;
  int starts = 0;

  /// Can hold permission pending to verify repeated Start taps are ignored.
  @override
  Future<void> prepare() async => await permission?.future;

  /// Exposes a stream whose cancellation can be checked after Stop.
  @override
  Stream<LocationRecord> start() {
    starts++;
    return points.stream;
  }
}

/// Waits for real async SQLite work with a bounded timeout instead of long sleeps.
Future<void> waitUntil(bool Function() complete) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (complete()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Controller did not reach the expected state');
}

/// Exercises GetX orchestration with SQLite and a mock HTTP client.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late TrackingController controller;
  late LocationRepository repository;
  late NetworkConnectivity network;
  late RestLocationApi api;
  late SyncService sync;
  late TestLocationSource source;
  late StreamController<List<ConnectivityResult>> networkEvents;
  late Set<String> accepted;

  setUp(() async {
    repository = LocationRepository(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    await repository.initialize();
    networkEvents = StreamController<List<ConnectivityResult>>.broadcast();
    network = NetworkConnectivity(
      check: () async => [ConnectivityResult.none],
      changes: networkEvents.stream,
    );
    accepted = {};
    api = RestLocationApi(
      baseUrl: 'http://mock',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        accepted.add(body['id'] as String);
        return http.Response(
          jsonEncode({'id': body['id'], 'accepted': true}),
          201,
        );
      }),
    );
    sync = SyncService(
      repository: repository,
      api: api,
      isOnline: () => network.online,
    );
    source = TestLocationSource();
    controller = TrackingController(
      repository: repository,
      source: source,
      network: network,
      api: api,
      sync: sync,
    );
    controller.onInit();
    await controller.initialize();
  });
  tearDown(() async {
    await controller.closeResources();
    await sync.close();
    network.onClose();
    await networkEvents.close();
    await source.points.close();
    api.close();
    await repository.database.close();
  });

  test('GPS continues while minimized; reconnection uploads stored points after Stop', () async {
    await controller.startTracking();
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    source.points.add(
      LocationRecord(
        id: 'background-fix',
        latitude: 12.97,
        longitude: 77.59,
        capturedAt: DateTime.utc(2026),
      ),
    );
    await waitUntil(() => controller.pending == 1);
    expect(controller.isTracking.value, isTrue);
    expect(accepted, isEmpty);
    await controller.stopTracking();
    expect(source.points.hasListener, isFalse);
    networkEvents.add([ConnectivityResult.wifi]);
    await waitUntil(() => controller.synced == 1);
    expect(controller.pending, 0);
    expect(accepted, {'background-fix'});
  });

  test(
    'repeated Start taps during permission request create one GPS subscription',
    () async {
      source.permission = Completer<void>();
      final first = controller.startTracking();
      await controller.startTracking();
      expect(source.starts, 0);
      source.permission!.complete();
      await first;
      expect(source.starts, 1);
      expect(controller.isTracking.value, isTrue);
    },
  );
}
