import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../models/location_record.dart';

/// The controller needs permission preparation and a stream of location records.
/// Tests supply a controllable stream instead of calling the phone's GPS.
abstract interface class LocationSource {
  /// Checks location services and requests permission before tracking starts.
  Future<void> prepare();

  /// Starts acquisition; cancelling the subscription stops it.
  Stream<LocationRecord> start();
}

/// Uses native GPS while the screen is open, minimized or locked.
/// Android uses Geolocator's foreground service; iOS uses Core Location's
/// background location mode. Emulator-injected GPS uses this same adapter.
class DeviceLocationService implements LocationSource {
  /// Requests permission while the user is still on the visible Start screen.
  /// Tracking never auto-starts from the background or after app termination.
  @override
  Future<void> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'Location services are off. Enable GPS in Settings.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is blocked. Allow it in app Settings.',
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const LocationException(
        'Location permission is required to start tracking.',
      );
    }
    // On Android 13+, this makes the ongoing service notification visible.
    // Denial does not block the location service; Android still lists it in
    // its active-apps/task-manager UI. iOS does not need a service notification.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
    }
  }

  /// Selects background-capable native settings for the current mobile platform.
  /// Ten metres avoids stationary noise. Android's five-second cadence is a
  /// request to the OS, not a promise of exact timing.
  static LocationSettings settingsFor(TargetPlatform platform) {
    if (platform == TargetPlatform.android) {
      return AndroidSettings(
        // Use Android's GPS provider directly. Emulator fixes and phones without
        // Google Play location services then follow the same native GPS path.
        forceLocationManager: true,
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Driver location tracking',
          notificationText: 'Tracking is active. Open the app to stop.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      activityType: ActivityType.automotiveNavigation,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );
  }

  /// Gives each native GPS fix a stable UUID before it enters local storage.
  /// Upload retries reuse this ID; they never create a second location record.
  @override
  Stream<LocationRecord> start() =>
      Geolocator.getPositionStream(
        locationSettings: settingsFor(defaultTargetPlatform),
      ).map(
        (position) => LocationRecord(
          id: const Uuid().v4(),
          latitude: position.latitude,
          longitude: position.longitude,
          capturedAt: position.timestamp.toUtc(),
        ),
      );
}

/// A readable permission or service error that can be shown directly in the UI.
class LocationException implements Exception {
  /// Stores the explanation displayed by the controller.
  const LocationException(this.message);
  final String message;

  /// Returns the explanation without platform exception details.
  @override
  String toString() => message;
}
