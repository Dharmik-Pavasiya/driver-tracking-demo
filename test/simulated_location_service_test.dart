import 'dart:async';

import 'package:driver_tracking_demo/models/location_record.dart';
import 'package:driver_tracking_demo/services/simulated_location_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Advances a test clock to verify timing without waiting six real seconds.
void main() {
  test(
    'simulation creates a new point every three seconds until cancelled',
    () async {
      const service = SimulatedLocationService();
      await service.prepare();
      fakeAsync((clock) {
        final points = <LocationRecord>[];
        final subscription = service.start().listen(points.add);
        clock.elapse(const Duration(seconds: 2));
        expect(points, isEmpty);
        clock.elapse(const Duration(seconds: 1));
        expect(points, hasLength(1));
        clock.elapse(const Duration(seconds: 3));
        expect(points, hasLength(2));
        expect(points[1].id, isNot(points[0].id));
        expect(points[1].latitude, greaterThan(points[0].latitude));
        expect(points[1].longitude, greaterThan(points[0].longitude));
        expect(points.every((point) => point.capturedAt.isUtc), isTrue);
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 9));
        expect(points, hasLength(2));
      });
    },
  );
}
