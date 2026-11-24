import 'dart:async';

import 'package:get/get.dart';

import '../data/location_repository.dart';
import '../models/location_record.dart';
import 'connectivity_service.dart';
import 'location_api.dart';

/// Loads saved points, uploads due rows one at a time, and schedules retries.
class SyncService extends GetxService {
  /// Receives shared dependencies; tests can supply a clock and shorter delays.
  SyncService({
    required this.repository,
    required this.api,
    required this.connection,
    DateTime Function()? now,
    Duration Function(int)? retryDelay,
  }) : _now = now ?? DateTime.now,
       _retryDelay = retryDelay ?? defaultRetryDelay;

  final LocationRepository repository;
  final LocationApi api;
  final ConnectivityService connection;
  final DateTime Function() _now;
  final Duration Function(int) _retryDelay;
  final records = <LocationRecord>[].obs;
  final isReady = false.obs;
  final isSyncing = false.obs;
  final errorMessage = RxnString();
  Timer? _timer;
  Future<void>? _activeUpload;
  bool _closed = false;

  /// Rows still waiting for an acknowledgement, including scheduled retries.
  int get pending =>
      records.where((row) => row.status == UploadStatus.pending).length;

  /// Rows acknowledged by the API and excluded from future upload passes.
  int get synced =>
      records.where((row) => row.status == UploadStatus.synced).length;

  /// Permanent rejections that require an explicit retry or investigation.
  int get blocked =>
      records.where((row) => row.status == UploadStatus.blocked).length;

  /// Starts one network listener and one five-second retry check for the app.
  Future<void> startAutomaticSync() async {
    if (_timer != null) return;
    await loadRecords();
    isReady.value = true;
    connection.start(onConnected: () => unawaited(synchronize()));
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(synchronize()),
    );
    unawaited(synchronize());
  }

  /// The database owns the data; these Rx rows are only the screen's current copy.
  Future<void> loadRecords() async => records.assignAll(await repository.all());

  /// Repeated capture/network/retry triggers share an existing upload operation.
  Future<void> synchronize() {
    if (_closed) return Future.value();
    _activeUpload ??= _uploadPending().whenComplete(() => _activeUpload = null);
    return _activeUpload!;
  }

  /// Confirms real internet first, then processes only rows whose retry is due.
  Future<void> _uploadPending() async {
    try {
      if (!await connection.checkInternet()) return;
      isSyncing.value = true;
      while (!_closed && connection.online) {
        final record = await repository.nextDue(_now());
        if (record == null || !connection.online) break;
        await _uploadRecord(record);
      }
    } catch (error) {
      errorMessage.value = 'Unable to synchronize: $error';
    } finally {
      isSyncing.value = false;
      try {
        await loadRecords();
      } catch (error) {
        errorMessage.value = 'Unable to read saved points: $error';
      }
    }
  }

  /// Acknowledges this ID or saves its error and the next retry deadline.
  Future<void> _uploadRecord(LocationRecord record) async {
    await repository.recordAttempt(record.id);
    try {
      await api.upload(record);
      await repository.acknowledge(record.id);
      errorMessage.value = null;
    } catch (error) {
      final retryable = error is! UploadException || error.retryable;
      await repository.fail(
        record.id,
        error: error.toString(),
        retryAt: _now().add(_retryDelay(record.attempts + 1)),
        retryable: retryable,
      );
      errorMessage.value = error.toString();
    }
  }

  /// Explicit retry skips the saved delay, but never sends a synced row again.
  Future<void> retryNow() async {
    await repository.retryNow();
    await synchronize();
  }

  /// Failed attempts wait 2, 4, 8, 16, 32, then at most 60 seconds.
  static Duration defaultRetryDelay(int attempt) {
    const seconds = [2, 4, 8, 16, 32, 60];
    final index = (attempt - 1).clamp(0, seconds.length - 1);
    return Duration(seconds: seconds[index]);
  }

  /// Stops scheduled work and waits for any in-flight request before shutdown.
  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _activeUpload;
  }

  /// GetX stops this service's scheduled work when it is removed.
  @override
  void onClose() {
    unawaited(close());
    super.onClose();
  }
}
