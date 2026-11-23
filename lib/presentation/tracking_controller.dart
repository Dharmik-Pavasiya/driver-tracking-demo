import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/location_repository.dart';
import '../domain/location_record.dart';
import '../services/location_api.dart';
import '../services/location_source.dart';
import '../services/network_monitor.dart';
import '../services/sync_service.dart';

class TrackingController extends ChangeNotifier {
  TrackingController({
    required this.repository,
    required this.source,
    required this.network,
    required this.api,
    required this.sync,
  });

  final LocationRepository repository;
  final LocationSource source;
  final NetworkMonitor network;
  final RestLocationApi api;
  final SyncService sync;
  StreamSubscription<void>? _gps;
  Timer? _retryTimer;
  bool _disposed = false;
  bool tracking = false;
  bool ready = false;
  String? storageError;
  List<LocationRecord> records = [];
  int get pending =>
      records.where((r) => r.status == UploadStatus.pending).length;
  int get synced =>
      records.where((r) => r.status == UploadStatus.synced).length;
  int get blocked =>
      records.where((r) => r.status == UploadStatus.blocked).length;

  Future<void> initialize() async {
    try {
      await repository.initialize();
      await refresh();
      sync.addListener(_onSync);
      network.addListener(_onNetwork);
      await network.initialize();
      ready = true;
      _retryTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(sync.synchronize()),
      );
      unawaited(sync.synchronize());
    } catch (error) {
      storageError = 'Could not open local outbox: $error';
    }
    _notify();
  }

  void startTracking() {
    if (tracking || !ready) return;
    tracking = true;
    storageError = null;
    _gps = source
        .start()
        .asyncMap((record) async {
          await repository.enqueue(
            record,
          ); // Commit locally before any HTTP request.
          await refresh();
          unawaited(sync.synchronize());
        })
        .listen(
          (_) {},
          onError: (Object error) {
            storageError = 'GPS capture/storage failed: $error';
            unawaited(stopTracking());
            _notify();
          },
        );
    _notify();
  }

  Future<void> stopTracking() async {
    tracking = false;
    final subscription = _gps;
    _gps = null;
    await subscription?.cancel();
    _notify();
  }

  Future<void> retryNow() async {
    try {
      await repository.retryNow();
      await sync.synchronize();
      await refresh();
    } catch (error) {
      storageError = 'Could not retry: $error';
      _notify();
    }
  }

  void setFailure(DemoFailure failure) {
    api.failure = failure;
    _notify();
  }

  Future<void> refresh() async {
    try {
      records = await repository.all();
    } catch (error) {
      storageError = 'Could not read outbox: $error';
    }
    _notify();
  }

  void _onNetwork() {
    _notify();
    if (ready && network.online) unawaited(sync.synchronize());
  }

  void _onSync() => unawaited(refresh());
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    unawaited(_gps?.cancel());
    network.removeListener(_onNetwork);
    sync.removeListener(_onSync);
    network.dispose();
    // Wait for an in-flight request before closing its API and database.
    unawaited(
      sync.close().whenComplete(() async {
        api.close();
        await repository.database.close();
      }),
    );
    super.dispose();
  }
}
