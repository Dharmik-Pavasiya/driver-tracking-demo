import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:driver_tracking_demo/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Verifies transport availability cannot bypass the real internet check.
void main() {
  ConnectivityService connection(http.Client client) => ConnectivityService(
    client: client,
    transport: () async => [ConnectivityResult.wifi],
    changes: const Stream.empty(),
  );

  test('Wi-Fi with captive-portal HTML stays offline', () async {
    final service = connection(
      MockClient((_) async => http.Response('<html>Sign in</html>', 200)),
    );
    expect(await service.checkInternet(), isFalse);
    expect(service.online, isFalse);
    await service.close();
  });
  test('a successful HTTPS probe enables synchronization', () async {
    final service = connection(
      MockClient((request) async {
        expect(request.url.scheme, 'https');
        return http.Response('', 204);
      }),
    );
    expect(await service.checkInternet(), isTrue);
    expect(service.online, isTrue);
    await service.close();
  });
  test('a failed first probe can use the second provider', () async {
    var calls = 0;
    final service = connection(
      MockClient((_) async => http.Response('', ++calls == 1 ? 503 : 204)),
    );
    expect(await service.checkInternet(), isTrue);
    expect(calls, 2);
    await service.close();
  });
  test('an offline override sends no internet probe', () async {
    var calls = 0;
    final service = connection(
      MockClient((_) async {
        calls++;
        return http.Response('', 204);
      }),
    );
    service.setSimulateOffline(true);
    expect(await service.checkInternet(), isFalse);
    expect(calls, 0);
    await service.close();
  });
  test(
    'transport reconnect is confirmed before the sync callback fires',
    () async {
      final events = StreamController<List<ConnectivityResult>>();
      var connected = false;
      final service = ConnectivityService(
        client: MockClient((_) async => http.Response('', 204)),
        transport: () async => [
          connected ? ConnectivityResult.wifi : ConnectivityResult.none,
        ],
        changes: events.stream,
      );
      final restored = Completer<void>();
      service.start(onConnected: () => restored.complete());
      expect(await service.checkInternet(), isFalse);
      connected = true;
      events.add([ConnectivityResult.wifi]);
      await restored.future.timeout(const Duration(seconds: 1));
      expect(service.online, isTrue);
      await service.close();
      await events.close();
    },
  );
}
