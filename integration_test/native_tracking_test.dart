import 'package:driver_tracking_demo/main.dart' as app;
import 'package:driver_tracking_demo/screens/tracking_screen/controller/tracking_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

/// Waits for native GPS/SQLite work without depending on an exact GPS cadence.
Future<void> waitFor(bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Native tracking did not reach the expected state within 20 seconds');
}

/// Optional emulator test; see docs/android-emulator-check.md for preparation.
/// The normal flutter test command runs the device-independent tests in test/.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native GPS persists while minimized/locked and stops cleanly', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    final controller = Get.find<TrackingController>();
    await waitFor(() => controller.isReady.value);
    controller.network.setSimulateOffline(true);
    await controller.startTracking();
    expect(controller.isTracking.value, isTrue);
    // The host sends a fresh fix after the native subscription is established.
    debugPrint('NATIVE_TRACKING_STARTED');
    await waitFor(
      () => controller.pending > 0 || controller.errorMessage.value != null,
    );
    expect(controller.errorMessage.value, isNull);
    expect(controller.pending, greaterThan(0));
    final earlierIds = controller.records.map((row) => row.id).toSet();

    // The host now minimizes the emulator, turns its screen off, and injects
    // two known native GPS points. No Flutter frames are pumped during this wait.
    debugPrint('NATIVE_BACKGROUND_STAGE');
    await Future<void>.delayed(const Duration(seconds: 35));
    final backgroundRows = controller.records.where(
      (row) => !earlierIds.contains(row.id),
    );
    expect(
      backgroundRows.any((row) => (row.latitude - 12.9800).abs() < 0.0001),
      isTrue,
    );
    expect(
      backgroundRows.any((row) => (row.latitude - 12.9900).abs() < 0.0001),
      isTrue,
    );

    await controller.stopTracking();
    expect(controller.isTracking.value, isFalse);
    debugPrint('NATIVE_SERVICE_STOPPED');
    // Leave time for the host to inspect the service before test APK cleanup.
    await Future<void>.delayed(const Duration(seconds: 4));
    controller.network.setSimulateOffline(false);
    await controller.sync.synchronize();
    await controller.refreshRecords();
    expect(controller.pending, 0);
    debugPrint('NATIVE_TRACKING_TEST_COMPLETE');
    await tester.pumpAndSettle();
    await controller.closeResources();
  });
}
