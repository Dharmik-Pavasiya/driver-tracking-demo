import 'package:driver_tracking_demo/main.dart' as app;
import 'package:driver_tracking_demo/models/location_record.dart';
import 'package:driver_tracking_demo/screens/tracking_screen/controller/tracking_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

/// Verifies the default phone-local API works without a separately started server.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'installed app owns its mock and synchronizes after internet returns',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      final controller = Get.find<TrackingController>();
      final sync = controller.sync;
      for (var attempt = 0; attempt < 50 && !sync.isReady.value; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(controller.api.baseUrl, startsWith('http://127.0.0.1:'));
      await controller.setOfflineMode(true);
      final record = LocationRecord(
        id: 'installed-${DateTime.now().millisecondsSinceEpoch}',
        latitude: 12.97,
        longitude: 77.59,
        capturedAt: DateTime.now().toUtc(),
      );
      await controller.repository.enqueue(record);
      await sync.loadRecords();
      await sync.synchronize();
      expect(await controller.repository.mockContains(record.id), isFalse);
      await controller.setOfflineMode(false);
      expect(
        sync.connection.online,
        isTrue,
        reason: 'This native check needs actual internet access.',
      );
      expect(sync.pending, 0);
      expect(await controller.repository.mockContains(record.id), isTrue);
      await controller.closeResources();
      await sync.close();
    },
  );
}
