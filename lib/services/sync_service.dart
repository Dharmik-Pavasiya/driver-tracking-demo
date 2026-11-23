import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/location_repository.dart';
import 'location_api.dart';

/// One drain per app instance. At-least-once delivery + server idempotency
/// handles a crash/lost response between server commit and local acknowledgement.
class SyncService extends ChangeNotifier {
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
  bool get syncing => _active != null;
  String? lastError;

  static Duration defaultBackoff(int attempt) => Duration(
    milliseconds:
        min(60000, 2000 * (1 << min(attempt - 1, 5))) + Random().nextInt(501),
  );

  Future<void> synchronize() {
    if (_active != null) return _active!;
    if (_stopped || !isOnline()) return Future.value();
    // Schedule after assigning _active so listeners see consistent state.
    final run = Future<void>.microtask(_drain);
    _active = run.whenComplete(() {
      _active = null;
      notifyListeners();
    });
    notifyListeners();
    return _active!;
  }

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
        notifyListeners();
      }
    } catch (error) {
      // Storage failures must leave rows unacknowledged and remain visible.
      lastError = 'Local storage: $error';
      notifyListeners();
    }
  }

  Future<void> close() async {
    _stopped = true;
    await _active;
    dispose();
  }
}
