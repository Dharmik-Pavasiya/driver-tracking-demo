import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/location_repository.dart';
import '../../../models/location_record.dart';
import '../../../services/location_api.dart';
import '../../../services/location_service.dart';
import '../../../services/sync_service.dart';

/// Owns GPS Start/Stop and screen actions. Shared services own network/uploads.
class TrackingController extends GetxController with WidgetsBindingObserver {
  /// Receives app-owned services through TrackingBinding.
  TrackingController({
    required this.repository,
    required this.source,
    required this.simulatedSource,
    required this.api,
    required this.sync,
  });
  final LocationRepository repository;
  final LocationSource source;
  final LocationSource simulatedSource;
  final RestLocationApi api;
  final SyncService sync;
  final isStarting = false.obs;
  final isTracking = false.obs;
  final simulateLocation = false.obs;
  final errorMessage = RxnString();
  final uploadFailure = DemoFailure.none.obs;
  StreamSubscription<void>? _locations;
  bool _closed = false;

  /// The repository orders the shared list newest first.
  LocationRecord? get latest =>
      sync.records.isEmpty ? null : sync.records.first;

  /// Observes resume events without tying tracking to screen visibility.
  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Starts the selected source; both modes share the same save/upload callback.
  Future<void> startTracking() async {
    if (_closed ||
        isStarting.value ||
        isTracking.value ||
        !sync.isReady.value) {
      return;
    }
    isStarting.value = true;
    errorMessage.value = null;
    try {
      final selectedSource = simulateLocation.value ? simulatedSource : source;
      await selectedSource.prepare();
      if (_closed) return;
      _locations = selectedSource
          .start()
          .asyncMap(_saveLocation)
          .listen(
            (_) {},
            onError: (Object error) {
              errorMessage.value = error.toString();
              unawaited(stopTracking());
            },
          );
      isTracking.value = true;
    } catch (error) {
      errorMessage.value = error.toString();
    } finally {
      isStarting.value = false;
    }
  }

  /// Save first, refresh the screen, then let the shared worker upload when online.
  Future<void> _saveLocation(LocationRecord record) async {
    await repository.enqueue(record);
    await sync.loadRecords();
    unawaited(sync.synchronize());
  }

  /// Cancels native GPS, its notification, and the periodic timer when enabled.
  Future<void> stopTracking() async {
    await _locations?.cancel();
    _locations = null;
    isTracking.value = false;
  }

  /// Choose the source before Start so an active journey cannot change its mode.
  void setLocationSimulation(bool value) {
    if (isStarting.value || isTracking.value) return;
    simulateLocation.value = value;
  }

  /// The switch affects this demo only; switching back also checks real internet.
  Future<void> setOfflineMode(bool value) async {
    sync.connection.setSimulateOffline(value);
    if (!value) await sync.synchronize();
  }

  /// The local mock can reject a new row before or after storing it.
  void setUploadFailure(DemoFailure value) {
    uploadFailure.value = value;
    api.failure = value;
  }

  /// Minimize/lock leaves GPS active. Resume rechecks missed network changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync.synchronize());
  }

  /// Releases screen-owned GPS. Shared synchronization remains app-owned.
  Future<void> closeResources() async {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    await stopTracking();
  }

  /// GetX cancels GPS if the tracking screen's controller is removed.
  @override
  void onClose() {
    unawaited(closeResources());
    super.onClose();
  }
}
