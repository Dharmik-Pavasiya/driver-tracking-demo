import 'dart:async';

import 'package:driver_tracking_demo/models/location_record.dart';
import 'package:driver_tracking_demo/services/location_service.dart';
import 'package:driver_tracking_demo/services/simulated_location_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supplies measured GPS fixes so the sampler cannot invent coordinates.
class TestGpsSource implements LocationSource {
  final fixes = StreamController<LocationRecord>.broadcast();
  bool prepared = false;

  /// Records that the sampler requested native permission preparation.
  @override
  Future<void> prepare() async => prepared = true;

  /// Delivers only fixes explicitly supplied by the test.
  @override
  Stream<LocationRecord> start() => fixes.stream;
}

/// Verifies real-coordinate sampling, timing, buffering and native cancellation.
void main() {
  final firstFix = LocationRecord(
    id: 'native-fix',
    latitude: 51.5074,
    longitude: -0.1278,
    capturedAt: DateTime.utc(2026),
  );

  test(
    'three-second samples use exact GPS fixes and stop both subscriptions',
    () async {
      final gps = TestGpsSource();
      addTearDown(gps.fixes.close);
      final service = SimulatedLocationService(source: gps);
      await service.prepare();
      expect(gps.prepared, isTrue);
      fakeAsync((clock) {
        final samples = <LocationRecord>[];
        final subscription = service.start().listen(samples.add);
        gps.fixes.add(firstFix);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 2));
        expect(samples, isEmpty);
        clock.elapse(const Duration(seconds: 1));
        expect(samples, hasLength(1));
        clock.elapse(const Duration(seconds: 3));
        expect(samples, hasLength(2));
        for (final sample in samples) {
          expect(sample.latitude, firstFix.latitude);
          expect(sample.longitude, firstFix.longitude);
          expect(sample.capturedAt, firstFix.capturedAt);
        }
        expect(samples[1].id, isNot(samples[0].id));
        final movedFix = LocationRecord(
          id: 'moved-fix',
          latitude: 51.5078,
          longitude: -0.1274,
          capturedAt: firstFix.capturedAt.add(const Duration(seconds: 6)),
        );
        gps.fixes.add(movedFix);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 3));
        expect(samples.last.latitude, movedFix.latitude);
        expect(samples.last.longitude, movedFix.longitude);
        expect(samples.last.capturedAt, movedFix.capturedAt);
        subscription.pause();
        clock.elapse(const Duration(seconds: 6));
        expect(samples, hasLength(3));
        subscription.resume();
        clock.flushMicrotasks();
        expect(samples, hasLength(5));
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
        expect(gps.fixes.hasListener, isFalse);
        clock.elapse(const Duration(seconds: 9));
        expect(samples, hasLength(5));
      });
    },
  );

  test('no sample is fabricated before GPS provides a fix', () {
    final gps = TestGpsSource();
    addTearDown(gps.fixes.close);
    fakeAsync((clock) {
      final samples = <LocationRecord>[];
      final subscription = SimulatedLocationService(source: gps)
          .start()
          .listen(samples.add);
      clock.elapse(const Duration(seconds: 9));
      expect(samples, isEmpty);
      gps.fixes.add(firstFix);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 3));
      expect(samples.single.latitude, firstFix.latitude);
      unawaited(subscription.cancel());
      clock.flushMicrotasks();
    });
  });
}
