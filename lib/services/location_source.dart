import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../domain/location_record.dart';

abstract interface class LocationSource {
  Stream<LocationRecord> start();
}

/// A deterministic loop near Bengaluru. Cancel the subscription to stop GPS.
/// Replace this adapter with a permission-aware native location stream.
class SimulatedLocationSource implements LocationSource {
  SimulatedLocationSource({this.interval = const Duration(seconds: 3)});
  final Duration interval;
  int _step = 0;

  @override
  Stream<LocationRecord> start() {
    Timer? timer;
    late final StreamController<LocationRecord> controller;
    void capture() {
      final angle = _step++ * pi / 18;
      controller.add(
        LocationRecord(
          id: const Uuid().v4(),
          latitude: 12.9716 + sin(angle) * 0.002,
          longitude: 77.5946 + cos(angle) * 0.003,
          capturedAt: DateTime.now().toUtc(),
        ),
      );
    }

    controller = StreamController<LocationRecord>(
      onListen: () {
        capture();
        timer = Timer.periodic(interval, (_) => capture());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}
