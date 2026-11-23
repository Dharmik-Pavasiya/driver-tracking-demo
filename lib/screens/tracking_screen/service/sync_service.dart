import 'dart:math';

import 'package:get/get.dart';

import '../data/location_repository.dart';
import '../../../network/api_provider/location_api.dart';

/// One drain per app instance. At-least-once delivery + server idempotency
/// handles a crash/lost response between server commit and local acknowledgement.
class SyncService {
  /// Injects the repository, API and connectivity check.
  /// Tests can also supply a clock and fixed retry delays without real waiting.
  SyncService({
    required this.repository,
    required this.api,
    required this.isOnline,
    DateTime Function()? now,
    Duration Function(int attempt)? backoff,
  }) : now = now ?? (() => DateTime.now().toUtc()),
       backoff = backoff ?? defaultBackoff;

  final LocationRepository repository;
  final LocationApi api;
  final bool Function() isOnline;
  final DateTime Function() now;
  final Duration Function(int attempt) backoff;
  Future<void>? _active;
  bool _stopped = false;

  /// Increases after state changes so the GetX controller can refresh SQLite.
  final revision = 0.obs;

  /// Reports whether one shared upload pass is active.
  bool get syncing => _active != null;
  String? lastError;

  /// Doubles retry delays from 2 seconds up to 60 seconds, plus small jitter.
  /// Jitter stops several drivers from retrying at precisely the same moment.
  static Duration defaultBackoff(int attempt) {
    var seconds = 2;
    for (
      var previousAttempt = 1;
      previousAttempt < attempt;
      previousAttempt++
    ) {
      seconds = min(seconds * 2, 60);
      if (seconds == 60) break;
    }
    return Duration(milliseconds: seconds * 1000 + Random().nextInt(501));
  }

  /// Starts one upload pass; repeated triggers share its existing future.
  Future<void> synchronize() {
    if (_active != null) return _active!;
    if (_stopped || !isOnline()) return Future.value();
    // Schedule after assigning _active so listeners see consistent state.
    final run = Future<void>.microtask(_drain);
    _active = run.whenComplete(() {
      _active = null;
      revision.value++;
    });
    revision.value++;
    return _active!;
  }

  /// Uploads due rows in order, saving success or retry metadata for each row.
  /// GPS writes can happen concurrently because every SQL update targets one ID.
  Future<void> _drain() async {
    try {
      while (!_stopped && isOnline()) {
        final record = await repository.nextDue(now());
        if (record == null || _stopped || !isOnline()) break;
        await repository.recordAttempt(record.id);
        try {
          await api.upload(record);
          await repository.acknowledge(record.id);
          lastError = null;
        } catch (error) {
          final retryable = error is! UploadException || error.retryable;
          lastError = error.toString();
          await repository.fail(
            record.id,
            error: lastError!,
            retryAt: now().add(backoff(record.attempts + 1)),
            retryable: retryable,
          );
        }
        revision.value++;
      }
    } catch (error) {
      // Storage failures must leave rows unacknowledged and remain visible.
      lastError = 'Local storage: $error';
      revision.value++;
    }
  }

  /// Stops new passes and lets an already running request finish safely.
  Future<void> close() async {
    _stopped = true;
    await _active;
  }

  /// Prevents further work when a test or application releases this worker.
  void dispose() => _stopped = true;
}
