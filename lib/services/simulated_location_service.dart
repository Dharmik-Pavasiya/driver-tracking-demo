import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/location_record.dart';
import 'location_service.dart';

/// Simulates a three-second upload cadence using the latest real native GPS fix.
/// Coordinates come only from the injected GPS source; no route is generated.
/// The timer runs while the OS gives the app execution time.
class SimulatedLocationService implements LocationSource {
  /// Accepts the app's configured native GPS adapter, or controlled GPS in tests.
  const SimulatedLocationService({required this.source});
  final LocationSource source;

  /// Requires the same GPS availability and permission as normal tracking.
  @override
  Future<void> prepare() => source.prepare();

  /// Waits for a native fix, then samples the latest one on each three-second tick.
  /// Stationary samples retain the actual GPS coordinates and fix timestamp.
  /// Each sample gets its own ID; retries keep that ID. Stop cancels GPS and timer.
  /// Paused SQLite receivers buffer samples without pausing capture.
  @override
  Stream<LocationRecord> start() {
    late Timer timer;
    late StreamSubscription<LocationRecord> gps;
    late StreamController<LocationRecord> locations;
    LocationRecord? latest;
    locations = StreamController<LocationRecord>(
      onListen: () {
        gps = source.start().listen(
          (record) => latest = record,
          onError: locations.addError,
        );
        timer = Timer.periodic(const Duration(seconds: 3), (_) {
          final fix = latest;
          if (fix == null) return;
          locations.add(
            LocationRecord(
              id: const Uuid().v4(),
              latitude: fix.latitude,
              longitude: fix.longitude,
              capturedAt: fix.capturedAt,
            ),
          );
        });
      },
      onCancel: () async {
        timer.cancel();
        await gps.cancel();
      },
    );
    return locations.stream;
  }
}
