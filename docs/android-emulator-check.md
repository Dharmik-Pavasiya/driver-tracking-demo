# Optional native background check

This integration test uses the actual Geolocator service, not a fake GPS stream. It targets a disposable Android emulator; no physical device permissions or locations are changed. The installed app starts its own mock API automatically. Keep actual internet available for the final synchronization step.

1. Build and install the debug app, then grant its emulator permissions:

```sh
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell pm grant dev.assessment.driver_tracking_demo android.permission.ACCESS_COARSE_LOCATION
adb -s emulator-5554 shell pm grant dev.assessment.driver_tracking_demo android.permission.ACCESS_FINE_LOCATION
adb -s emulator-5554 shell pm grant dev.assessment.driver_tracking_demo android.permission.POST_NOTIFICATIONS
adb -s emulator-5554 emu geo fix 77.5946 12.9716
flutter test integration_test/native_tracking_test.dart -d emulator-5554 --reporter expanded
```

2. When the test prints `NATIVE_TRACKING_STARTED`, send the initial fix again after the native GPS subscription is ready:

```sh
adb -s emulator-5554 emu geo fix 77.5946 12.9716
```

3. When the test prints `NATIVE_BACKGROUND_STAGE`, use a second terminal to minimize the app and send a fix:

```sh
adb -s emulator-5554 shell input keyevent KEYCODE_HOME
adb -s emulator-5554 emu geo fix 77.6000 12.9800
```

Wait at least six seconds, then turn off the emulator screen and send another fix:

```sh
adb -s emulator-5554 shell input keyevent KEYCODE_SLEEP
adb -s emulator-5554 emu geo fix 77.6100 12.9900
```

The test waits 35 seconds without pumping Flutter frames and checks that both native fixes reached SQLite while offline. It then stops capture and reconnects; pending rows must become synced. `NATIVE_TRACKING_TEST_COMPLETE` confirms completion. Wake the emulator screen afterward.

Inspect `adb shell dumpsys activity services dev.assessment.driver_tracking_demo` during capture for Geolocator's location foreground service. After Stop, it should no longer be foreground. Real iPhone lock-screen validation needs an iOS device/Mac and is a separate check; these Android results do not establish iOS runtime behavior.

## Periodic sampling with real GPS

`integration_test/simulated_tracking_test.dart` uses the native location stream and samples its latest fix every three seconds. Use the same emulator permission preparation above, and keep actual internet available for synchronization.

Run `flutter test integration_test/simulated_tracking_test.dart -d emulator-5554 --reporter expanded`. In another terminal, when it prints `REAL_GPS_SAMPLER_STARTED`, inject the stationary fix:

```sh
adb -s emulator-5554 emu geo fix -0.1278 51.5074
```

When it prints `REAL_GPS_MOVE`, inject the moved fix:

```sh
adb -s emulator-5554 emu geo fix -0.1274 51.5078
```

The test checks exact stationary GPS coordinates, a sample from the moved fix, offline storage, REST acceptance on reconnection and cancellation of GPS/timer on Stop. These coordinates are test inputs supplied to the emulator; the application contains no fixed coordinates or generated route.
