import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// Confirms internet access, rather than assuming that Wi-Fi means online.
class ConnectivityService extends GetxService {
  /// Optional network adapters let tests check internet behavior without a phone.
  ConnectivityService({
    http.Client? client,
    Future<List<ConnectivityResult>> Function()? transport,
    Stream<List<ConnectivityResult>>? changes,
  }) : _client = client ?? http.Client(),
       _transport = transport ?? Connectivity().checkConnectivity,
       _changes = changes ?? Connectivity().onConnectivityChanged;

  final http.Client _client;
  final Future<List<ConnectivityResult>> Function() _transport;
  final Stream<List<ConnectivityResult>> _changes;
  final isOnline = false.obs;
  final simulateOffline = false.obs;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  void Function()? _onConnected;
  bool _closed = false;

  /// Uploads need both confirmed internet access and the demo switch turned off.
  bool get online => isOnline.value && !simulateOffline.value;

  /// Rechecks internet access whenever the device changes network transport.
  void start({required void Function() onConnected}) {
    _onConnected = onConnected;
    _subscription = _changes.listen(
      (_) => unawaited(checkInternet()),
      onError: (_) => isOnline.value = false,
    );
  }

  /// Requires an HTTPS 204 response; captive-portal HTML is not internet access.
  /// The second endpoint covers networks that block the first provider.
  Future<bool> checkInternet() async {
    if (simulateOffline.value || _closed) return false;
    var connected = false;
    try {
      final transports = await _transport();
      if (transports.any((type) => type != ConnectivityResult.none)) {
        connected = await _probeInternet();
      }
    } catch (_) {
      connected = false;
    }
    if (_closed) return false;
    final wasOnline = isOnline.value;
    isOnline.value = connected;
    if (connected && !wasOnline) _onConnected?.call();
    return online;
  }

  /// Tries two providers so one blocked endpoint does not imply an offline phone.
  Future<bool> _probeInternet() async {
    const urls = [
      'https://www.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
    ];
    for (final url in urls) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 204) return true;
      } catch (_) {
        // A timeout or connection error leaves the other provider available.
      }
    }
    return false;
  }

  /// Only changes the demo override; the user's network settings stay unchanged.
  void setSimulateOffline(bool value) => simulateOffline.value = value;

  /// Releases the transport listener and probe client.
  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    _client.close();
  }

  /// GetX releases the same resources when removing this service.
  @override
  void onClose() {
    unawaited(close());
    super.onClose();
  }
}
