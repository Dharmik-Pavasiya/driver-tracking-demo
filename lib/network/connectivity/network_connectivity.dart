import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

/// Watches network interfaces and provides the assessment's offline switch.
/// An available interface does not prove the API is reachable; HTTP still retries.
class NetworkConnectivity extends GetxService {
  /// Uses connectivity_plus normally, or injected functions in tests.
  NetworkConnectivity({
    Future<List<ConnectivityResult>> Function()? check,
    Stream<List<ConnectivityResult>>? changes,
  }) : _check = check ?? Connectivity().checkConnectivity,
       _changes = changes ?? Connectivity().onConnectivityChanged;
  final Future<List<ConnectivityResult>> Function() _check;
  final Stream<List<ConnectivityResult>> _changes;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _closed = false;
  final available = false.obs;
  final simulateOffline = false.obs;

  /// Allows uploads only when a transport exists and simulation is disabled.
  bool get online => available.value && !simulateOffline.value;

  /// Subscribes once and reads the initial network state.
  Future<void> initialize() async {
    _subscription = _changes.listen(_update, onError: (_) => _update([]));
    await refresh();
  }

  /// Rechecks on resume because the OS may suppress background network events.
  Future<void> refresh() async {
    try {
      _update(await _check());
    } catch (_) {
      _update([]);
    }
  }

  /// Converts network types into the flag used by the sync worker.
  void _update(List<ConnectivityResult> results) {
    if (_closed) return;
    available.value = results.any(
      (result) => result != ConnectivityResult.none,
    );
  }

  /// Changes only the demo override, without changing device settings.
  void setSimulateOffline(bool value) => simulateOffline.value = value;

  /// Cancels the platform listener when GetX releases app dependencies.
  @override
  void onClose() {
    _closed = true;
    unawaited(_subscription?.cancel());
    super.onClose();
  }
}
