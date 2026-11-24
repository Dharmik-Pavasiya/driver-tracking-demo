import 'package:driver_tracking_demo/app/app_strings.dart';
import 'package:driver_tracking_demo/main.dart' as app;
import 'package:driver_tracking_demo/screens/tracking_screen/controller/tracking_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

/// Waits for the timer, SQLite and HTTP without requiring an exact upload time.
Future<void> waitFor(bool Function() ready) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Simulation did not reach the expected state within twenty seconds');
}

/// Emulator check: the host injects known native GPS fixes at the printed stages.
/// See docs/android-emulator-check.md for preparation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('simulated points persist offline, upload and stop generating', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    final controller = Get.find<TrackingController>();
    final sync = controller.sync;
    await waitFor(() => sync.isReady.value);
    await controller.setOfflineMode(true);
    final previousIds = sync.records.map((row) => row.id).toSet();
    await tester.tap(find.text(AppStrings.simulateLocation));
    await tester.pumpAndSettle();
    expect(controller.simulateLocation.value, isTrue);
    await tester.tap(find.text(AppStrings.start));
    await tester.pumpAndSettle();
    expect(controller.isTracking.value, isTrue);
    debugPrint('REAL_GPS_SAMPLER_STARTED');
    await waitFor(
      () =>
          sync.records
              .where(
                (row) =>
                    !previousIds.contains(row.id) &&
                    (row.latitude - 51.5074).abs() < 0.00001 &&
                    (row.longitude + 0.1278).abs() < 0.00001,
              )
              .length >=
          2,
    );
    final stationary = sync.records
        .where(
          (row) =>
              !previousIds.contains(row.id) &&
              (row.latitude - 51.5074).abs() < 0.00001,
        )
        .toList();
    for (final sample in stationary) {
      expect(sample.latitude, closeTo(51.5074, 0.00001));
      expect(sample.longitude, closeTo(-0.1278, 0.00001));
    }
    final beforeMove = sync.records.map((row) => row.id).toSet();
    debugPrint('REAL_GPS_MOVE');
    await waitFor(
      () => sync.records.any(
        (row) =>
            !beforeMove.contains(row.id) &&
            (row.latitude - 51.5078).abs() < 0.00001,
      ),
    );
    await controller.stopTracking();
    debugPrint('REAL_GPS_STOPPED');
    final generated = sync.records
        .where((row) => !previousIds.contains(row.id))
        .toList();
    expect(
      generated.any((row) => (row.longitude + 0.1274).abs() < 0.00001),
      isTrue,
    );
    for (final record in generated) {
      expect(await controller.repository.mockContains(record.id), isFalse);
      expect(record.attempts, 0);
    }
    await controller.setOfflineMode(false);
    expect(
      sync.connection.online,
      isTrue,
      reason: 'This check needs actual internet access.',
    );
    expect(sync.pending, 0);
    for (final record in generated) {
      expect(await controller.repository.mockContains(record.id), isTrue);
    }
    final savedCount = sync.records.length;
    await Future<void>.delayed(const Duration(seconds: 4));
    await sync.loadRecords();
    expect(sync.records, hasLength(savedCount));
    await controller.closeResources();
    await sync.close();
    await tester.pumpAndSettle();
  });
}
