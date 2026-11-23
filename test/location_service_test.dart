import 'package:driver_tracking_demo/screens/tracking_screen/service/location_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// Checks the native configurations without requiring location permissions.
void main() {
  test('Android enables a visible foreground service and wake lock', () {
    final settings = DeviceLocationService.settingsFor(
      TargetPlatform.android,
    ) as AndroidSettings;
    expect(settings.distanceFilter, 10);
    expect(settings.forceLocationManager, isTrue);
    expect(settings.foregroundNotificationConfig?.enableWakeLock, isTrue);
    expect(settings.foregroundNotificationConfig?.setOngoing, isTrue);
  });
  test('iOS enables background location and does not automatically pause', () {
    final settings =
        DeviceLocationService.settingsFor(TargetPlatform.iOS) as AppleSettings;
    expect(settings.allowBackgroundLocationUpdates, isTrue);
    expect(settings.pauseLocationUpdatesAutomatically, isFalse);
    expect(settings.showBackgroundLocationIndicator, isTrue);
  });
}
