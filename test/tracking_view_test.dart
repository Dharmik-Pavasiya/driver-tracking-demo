import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:driver_tracking_demo/app/app_strings.dart';
import 'package:driver_tracking_demo/data/location_repository.dart';
import 'package:driver_tracking_demo/models/location_record.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/controller/tracking_controller.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/view/tracking_view.dart';
import 'package:driver_tracking_demo/services/connectivity_service.dart';
import 'package:driver_tracking_demo/services/location_api.dart';
import 'package:driver_tracking_demo/services/location_service.dart';
import 'package:driver_tracking_demo/services/simulated_location_service.dart';
import 'package:driver_tracking_demo/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Checks that unrelated controls keep their widgets when reactive data changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocationRepository repository;
  late ConnectivityService connection;
  late RestLocationApi api;
  late SyncService sync;
  late TrackingController controller;

  setUp(() async {
    repository = LocationRepository(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    await repository.initialize();
    connection = ConnectivityService(
      transport: () async => [ConnectivityResult.none],
      changes: const Stream.empty(),
    );
    api = RestLocationApi(baseUrl: 'http://test');
    sync = SyncService(
      repository: repository,
      api: api,
      connection: connection,
    );
    sync.isReady.value = true;
    final source = DeviceLocationService();
    controller = Get.put(
      TrackingController(
        repository: repository,
        source: source,
        simulatedSource: SimulatedLocationService(source: source),
        api: api,
        sync: sync,
      ),
    );
  });

  tearDown(() async {
    await controller.closeResources();
    await sync.close();
    await connection.close();
    api.close();
    await repository.database.close();
    Get.reset();
  });

  testWidgets(
    'an upload error updates its message without rebuilding the body or Start',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TrackingView()));
      final body = tester.widget<ListView>(find.byType(ListView));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final location = tester.widget<Text>(find.text(AppStrings.noLocation));
      sync.errorMessage.value = 'Upload failed';
      await tester.pump();
      expect(find.text('Upload failed'), findsOneWidget);
      expect(
        identical(tester.widget<ListView>(find.byType(ListView)), body),
        isTrue,
      );
      expect(
        identical(
          tester.widget<FilledButton>(find.byType(FilledButton)),
          button,
        ),
        isTrue,
      );
      expect(
        identical(
          tester.widget<Text>(find.text(AppStrings.noLocation)),
          location,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'network, upload and record changes refresh their sections independently',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TrackingView()));
      final body = tester.widget<ListView>(find.byType(ListView));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      connection.isOnline.value = true;
      await tester.pump();
      expect(find.text(AppStrings.online), findsOneWidget);
      sync.isSyncing.value = true;
      await tester.pump();
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      sync.records.add(
        LocationRecord(
          id: 'ui-point',
          latitude: 12.97,
          longitude: 77.59,
          capturedAt: DateTime.utc(2026),
        ),
      );
      await tester.pump();
      expect(find.text(AppStrings.counts(1, 0, 0)), findsOneWidget);
      expect(find.text('12.970000, 77.590000'), findsWidgets);
      expect(find.text(AppStrings.uploading), findsOneWidget);
      expect(
        identical(tester.widget<ListView>(find.byType(ListView)), body),
        isTrue,
      );
      expect(
        identical(
          tester.widget<FilledButton>(find.byType(FilledButton)),
          button,
        ),
        isTrue,
      );
    },
  );
}
