import 'package:uuid/uuid.dart';

import '../models/location_record.dart';
import 'location_service.dart';

/// Generates a short demo route without GPS permission or emulator controls.
/// This Dart timer runs while the app has execution time; use native GPS for
/// background tracking because a suspended iOS app cannot keep a timer running.
class SimulatedLocationService implements LocationSource {
  /// The service has no resources until the controller subscribes to start().
  const SimulatedLocationService();

  /// Simulation does not access device GPS, so no permission is requested.
  @override
  Future<void> prepare() async {}

  /// Emits the first point after three seconds, then another every three seconds.
  /// Cancelling the subscription stops the timer. The route loops every 100
  /// points to keep coordinates in a small area, with a new ID on every tick.
  @override
  Stream<LocationRecord> start() =>
      Stream.periodic(const Duration(seconds: 3), (tick) {
        final offset = (tick % 100) * 0.0001;
        return LocationRecord(
          id: const Uuid().v4(),
          latitude: 12.9716 + offset,
          longitude: 77.5946 + offset,
          capturedAt: DateTime.now().toUtc(),
        );
      });
}
