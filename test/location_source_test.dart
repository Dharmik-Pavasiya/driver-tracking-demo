import 'package:driver_tracking_demo/services/location_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'simulated GPS emits fresh IDs and cancellation stops capture',
    () async {
      final source = SimulatedLocationSource(
        interval: const Duration(milliseconds: 5),
      );
      final records = await source.start().take(3).toList();
      expect(records.length, 3);
      expect(records.map((record) => record.id).toSet().length, 3);
      expect(records.first.latitude, isNot(records.last.latitude));
      var captured = 0;
      final subscription = source.start().listen((_) => captured++);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      await subscription.cancel();
      final stoppedAt = captured;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(captured, stoppedAt);
    },
  );
}
