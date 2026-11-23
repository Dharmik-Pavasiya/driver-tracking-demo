import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkMonitor extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _available = false;
  bool _simulateOffline = false;
  bool get simulateOffline => _simulateOffline;
  bool get online => _available && !_simulateOffline;

  Future<void> initialize() async {
    _subscription = _connectivity.onConnectivityChanged.listen(
      _update,
      onError: (_) => _update([ConnectivityResult.none]),
    );
    await refresh();
  }

  Future<void> refresh() async {
    try {
      _update(await _connectivity.checkConnectivity());
    } catch (_) {
      _update([ConnectivityResult.none]);
    }
  }

  void _update(List<ConnectivityResult> results) {
    _available = results.any((result) => result != ConnectivityResult.none);
    notifyListeners();
  }

  void setSimulateOffline(bool value) {
    _simulateOffline = value;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
