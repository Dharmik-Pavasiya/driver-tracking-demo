import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../network/api_provider/location_api.dart';
import '../../../network/connectivity/network_connectivity.dart';
import '../data/location_record.dart';
import '../data/location_repository.dart';
import '../service/location_service.dart';
import '../service/sync_service.dart';

/// Coordinates screen actions, native GPS, the local outbox and synchronization.
///
/// Rx fields notify Obx in the view. SQL, permissions and HTTP remain in their
/// own classes, so a beginner can follow one responsibility at a time.
class TrackingController extends GetxController with WidgetsBindingObserver {
  /// Receives dependencies from TrackingBinding; tests pass controllable fakes.
  TrackingController({
    required this.repository,
    required this.source,
    required this.network,
    required this.api,
    required this.sync,
  });
  final LocationRepository repository;
  final LocationSource source;
  final NetworkConnectivity network;
  final RestLocationApi api;
  final SyncService sync;

  final isReady = false.obs;
  final isStarting = false.obs;
  final isTracking = false.obs;
  final records = <LocationRecord>[].obs;
  final errorMessage = RxnString();
  final uploadFailure = DemoFailure.none.obs;
  final isSyncing = false.obs;
  StreamSubscription<void>? _gps;
  Timer? _retryTimer;
  Worker? _networkWorker;
  Worker? _syncWorker;
  bool _initialized = false;
  bool _closed = false;

  /// Counts rows still waiting for a successful API acknowledgement.
  int get pending =>
      records.where((row) => row.status == UploadStatus.pending).length;

  /// Counts rows successfully accepted by the server.
  int get synced =>
      records.where((row) => row.status == UploadStatus.synced).length;

  /// Counts rejected rows that will require explicit review/retry.
  int get blocked =>
      records.where((row) => row.status == UploadStatus.blocked).length;

  /// Returns the most recent saved GPS fix for the screen.
  LocationRecord? get latest => records.isEmpty ? null : records.first;

  /// Registers lifecycle and GetX workers once when the controller is created.
  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _networkWorker = everAll([network.available, network.simulateOffline], (_) {
      if (isReady.value && network.online) unawaited(sync.synchronize());
    });
    _syncWorker = ever(sync.revision, (_) {
      isSyncing.value = sync.syncing;
      unawaited(refreshRecords());
    });
  }

  /// Loads the outbox and connectivity after the first screen frame.
  @override
  void onReady() {
    super.onReady();
    unawaited(initialize());
  }

  /// Initializes listeners and resumes any stored uploads without restarting GPS.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await refreshRecords();
      await network.initialize();
      if (_closed) return;
      isReady.value = true;
      // Android's service keeps this process active. On iOS, native location
      // callbacks also trigger sync; this timer is not a background entitlement.
      _retryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(sync.synchronize());
      });
      unawaited(sync.synchronize());
    } catch (error) {
      errorMessage.value = 'Unable to initialize tracking: $error';
    }
  }

  /// Asks permission, then subscribes to native foreground/background updates.
  /// Repeated taps cannot create several subscriptions while permission is pending.
  Future<void> startTracking() async {
    if (!isReady.value || isStarting.value || isTracking.value || _closed) {
      return;
    }
    isStarting.value = true;
    errorMessage.value = null;
    try {
      await source.prepare();
      if (_closed) return;
      _gps = source
          .start()
          .asyncMap(_saveLocation)
          .listen(
            (_) {},
            onError: (Object error) {
              errorMessage.value = 'Tracking stopped: $error';
              unawaited(stopTracking());
            },
            onDone: () => isTracking.value = false,
          );
      isTracking.value = true;
    } catch (error) {
      errorMessage.value = error.toString();
    } finally {
      if (!_closed) isStarting.value = false;
    }
  }

  /// Commits a GPS fix locally before asking the worker to upload it.
  /// asyncMap processes fixes sequentially; failures stop acquisition visibly.
  Future<void> _saveLocation(LocationRecord record) async {
    await repository.enqueue(record);
    await refreshRecords();
    unawaited(sync.synchronize());
  }

  /// Cancels native updates, which also removes Android's foreground service.
  /// Existing pending records can continue syncing after capture has stopped.
  Future<void> stopTracking() async {
    final subscription = _gps;
    _gps = null;
    isTracking.value = false;
    await subscription?.cancel();
  }

  /// Reloads SQLite for reactive counters/list; the database is the source of truth.
  Future<void> refreshRecords() async {
    try {
      final saved = await repository.all();
      if (!_closed) records.assignAll(saved);
    } catch (error) {
      if (!_closed) {
        errorMessage.value = 'Unable to read local locations: $error';
      }
    }
  }

  /// Gives failed/blocked rows another chance without resubmitting synced rows.
  Future<void> retryNow() async {
    try {
      await repository.retryNow();
      await sync.synchronize();
      await refreshRecords();
    } catch (error) {
      errorMessage.value = 'Unable to retry uploads: $error';
    }
  }

  /// Sets a mock-only failure header; this does not modify the saved GPS payload.
  void setUploadFailure(DemoFailure failure) {
    uploadFailure.value = failure;
    api.failure = failure;
  }

  /// Rechecks network/outbox on resume without stopping GPS when minimized.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_closed) {
      unawaited(network.refresh());
      unawaited(refreshRecords());
    }
  }

  /// Releases this screen's timers and subscriptions; useful in lifecycle tests.
  Future<void> closeResources() async {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    _networkWorker?.dispose();
    _syncWorker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    await stopTracking();
  }

  /// Starts cleanup when GetX removes the route. Minimize/lock does not remove it.
  @override
  void onClose() {
    unawaited(closeResources());
    super.onClose();
  }
}
