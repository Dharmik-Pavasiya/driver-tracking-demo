# Driver Location

A focused Android/iOS Flutter demo using GetX, native or simulated locations and SQLite. The single screen has Start/Stop, latest coordinates, upload counts, recent points and demo controls. A physical phone supplies real GPS, or the app can generate a demo location every three seconds.

## Setup

Tested toolchain: Flutter 3.47.0 and Dart 3.13.0. Android needs its SDK and Java 17 or a compatible newer JDK. iOS needs macOS and Xcode. This project has only Android and iOS targets.

```sh
git clone https://github.com/Dharmik-Pavasiya/driver-tracking-demo.git
cd driver-tracking-demo
flutter pub get
flutter devices
flutter run -d <device-id>
```

**No backend setup is required.** The installed app starts a real HTTP mock on its own loopback address and chooses a free port. There is no computer IP, port forwarding or server URL to enter. It works the same way in an installed Android APK and an iOS app. Android permits cleartext HTTP only for loopback hosts; internet checks use HTTPS.

For a standalone Android installation, run `flutter build apk --release` and install `build/app/outputs/flutter-apk/app-release.apk`. The assessment APK uses the project's debug signing configuration; it is not a store release. On iOS, select the Runner signing team in Xcode before installing on a physical iPhone.

Enable GPS, press **Start tracking**, and grant location permission. Android also requests notification permission for its ongoing tracking notification. Start the journey while the app is visible, then minimize or lock it. Move beyond the ten-metre distance filter to receive another fix. GPS can take a few seconds, especially indoors.

For automatic demo coordinates, enable **Simulate location** before Start. No GPS permission or movement is needed. The first point arrives after three seconds, followed by a new coordinate every three seconds. Points follow a small repeating route with a fresh UUID and UTC time per point. They use the same SQLite, internet checks, REST uploads and retries as native GPS. Stop cancels the timer; stop the journey before changing modes.

The automatic simulation runs while the app has execution time. It does not start a native location service or keep a suspended iOS process alive. Use real GPS or native emulator injection when assessing minimized/screen-lock tracking. For native GPS simulation, use Android Emulator → Extended Controls → Location, or iOS Simulator → Features → Location.

## Try the workflow

1. Enable **Simulate offline**, press Start, and move or inject coordinates. Pending points are saved in SQLite.
2. Minimize or lock during tracking, continue moving, then reopen the app to inspect the saved points.
3. Disable the offline switch while the device has internet. Pending points synchronize automatically. You can also turn off Wi-Fi and mobile data to test real offline behavior.
4. Choose **Fail before saving** and capture another point. The mock returns HTTP 503; attempts and the retry error remain saved. Select Healthy and wait, or press Retry pending uploads.
5. Choose **Fail after saving** and capture a point. The mock stores it but returns 503. The retry sends the same ID and succeeds without another accepted record, even if this failure option remains selected.
6. Stop tracking. GPS and Android's foreground notification stop; saved uploads remain eligible for synchronization. Close and reopen the app to check persistence.

In this demonstration, **synced means accepted by the on-device mock**, not uploaded to a remote cloud service. The mock is reachable locally even without internet; the synchronization service deliberately gates uploads on actual internet availability to demonstrate the assessment's offline/reconnection behavior. Both outbox records and mock acceptance IDs survive app restart. Tracking and demo switches reset when the process ends, so press Start again for a new journey. The UI shows ten recent points; SQLite retains all records.

## Architecture and reading order

The project follows [the supplied GetX template](https://github.com/Dharmik-Pavasiya/getx-architechture): screen bindings, constructor injection, GetxController, GetView and Obx. Shared data and services live at the root of lib so another screen can reuse them.

```text
lib/
  main.dart                         Open SQLite, start mock, show app
  app/
    app_binding.dart                Register app-wide dependencies
    app_screens.dart                All route names, views and bindings
    app_strings.dart                Visible screen wording
  models/location_record.dart       Captured point and upload metadata
  data/
    database_factory.dart           Open persistent phone database
    location_repository.dart        All SQLite reads and updates
  services/
    location_service.dart           Native GPS and permission handling
    simulated_location_service.dart Three-second demo coordinates
    connectivity_service.dart       Confirm actual internet access
    location_api.dart               POST and acknowledgement validation
    mock_api_service.dart           Install-and-run local REST mock
    sync_service.dart               Shared upload state and retries
  screens/tracking_screen/
    binding/tracking_binding.dart   Inject shared services
    controller/tracking_controller.dart  Start/Stop and screen actions
    view/tracking_view.dart         Plain Material widgets
test/                               Storage, HTTP, internet and retry tests
integration_test/                   Installed-app and native GPS checks
```

Start reading `TrackingController.startTracking`, then `_saveLocation`, `LocationRepository.enqueue`, `SyncService._uploadPending`, `_uploadRecord` and `RestLocationApi.upload`.

1. The selected native or simulated source creates one UUID and UTC capture time per delivered point.
2. The controller awaits the SQLite insert before requesting synchronization.
3. The synchronization service checks internet and reads the oldest due pending row.
4. It counts the attempt and sends the original ID as `Idempotency-Key`.
5. Only HTTP 200/201 with `accepted: true` and that same ID marks the row synced.
6. Failure saves the error and next retry deadline. A later pass uses the same ID and payload.

SQLite owns the durable data. `SyncService.records` is a current Rx copy for the view, with derived counts. `Obx` rebuilds when these fields change. The controller handles screen actions; synchronization owns one retry timer and its network listener. SQL stays in the repository, HTTP in the API class, and native settings in the location service. Application classes and methods have documentation comments. A separate local workflow guide is deliberately excluded from Git.

## Internet checks and delivery

`connectivity_plus` reports available network transports. The service also requires HTTP 204 from an HTTPS probe at `www.gstatic.com/generate_204`, falling back to `cp.cloudflare.com/generate_204`. Each request has a three-second timeout. A Wi-Fi connection with captive-portal HTML, or failure of both probes, remains offline. Probes contain no location data. A network that blocks both providers may delay uploads even when other sites work.

Network changes, new GPS fixes, app resume and a five-second check request synchronization while the app has execution time. Overlapping triggers share one active upload operation. Points upload sequentially, and each request times out after eight seconds.

Retry deadlines use delays of 2, 4, 8, 16, 32 and then 60 seconds. Attempts and deadlines survive restart. These are minimum delays; the next eligible trigger performs the upload. HTTP 408/429/5xx and transport or invalid-response failures retry automatically. Other HTTP rejections become blocked until explicit review/retry.

The mock has a separate `mock_locations` acceptance table. Its SQLite transaction accepts a new ID once, acknowledges a matching replay, and returns 409 for the same ID with a changed payload. The outbox primary key also prevents duplicate local IDs. This provides at-least-once requests with idempotent acceptance, including a committed request whose acknowledgement fails.

## Background GPS on Android and iOS

**Android:** Geolocator's native location foreground service runs with an ongoing notification and wake lock. The manifest declares location, foreground-service/location and wake-lock permissions; the plugin supplies `foregroundServiceType="location"`. The direct native GPS provider also supports emulator injection and devices without Google Play location services. Android 13+ notification permission makes the notification visible; denial does not prevent the service, but Android may show it only in its active-apps UI. Stop cancels the subscription and service. This demo starts from the visible activity with while-in-use location permission. Automatic starts from the background need additional authorization and must obey current foreground-start restrictions.

**iOS:** Core Location runs with `UIBackgroundModes: location` and location usage descriptions. Apple settings allow background updates, disable automatic pausing during the journey, use automotive navigation and show the system location indicator. An authorized session starts while the app is visible. Always authorization matters for additional background-start/relaunch cases. iOS provides location background execution rather than an Android-style service. Stop ends native updates.

The controller leaves tracking active on pause/inactive events. Native fixes are stored before synchronization; resume checks pending uploads again. An ordinary Dart timer cannot keep a suspended iOS process alive. If tracking stops while offline and the OS suspends the app, uploads wait for another permitted execution window or reopening. Exact upload timing during suspension is not guaranteed.

Screen lock differs from process termination. Force-stop/force-quit, revoked permission, disabled GPS, OS termination or OEM battery policies can end tracking. This demo does not restart after termination or reboot. A production version would add OS-scheduled uploads such as WorkManager/background URLSession, retention limits, battery testing and validation of iOS database protection while locked after first unlock.

References: [Geolocator](https://pub.dev/packages/geolocator), [Android location foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#location), [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background).

## Validation

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter test integration_test/install_and_run_test.dart -d <device-id>
flutter test integration_test/simulated_tracking_test.dart -d <device-id>
flutter build apk --release
# macOS only; signing is needed for physical iPhone installation
flutter build ios --debug --no-codesign
```

Unit tests cover persistent offline storage, retries and saved deadlines, reconnection, overlapping upload triggers, permanent rejections, acknowledgements, captive portals, fallback internet probes, on-device HTTP mock acceptance/replay, simulation cadence/cancellation and native settings. The install-and-run integration test verifies internet-gated synchronization to the automatically started phone mock. The simulation integration test checks the real timer, offline storage, upload and Stop without GPS permission.

The optional [native Android emulator check](docs/android-emulator-check.md) exercises actual GPS callbacks while minimized and screen-off, then Stop and reconnection. These Android checks do not establish iPhone runtime behavior. Physical iPhone screen-lock behavior has not been tested. GitHub Actions validates Android analysis/tests/build and an unsigned iOS build on macOS.

On Windows, `kotlin.incremental=false` avoids Kotlin's cross-drive Pub-cache build error. Signing for stores, authentication, batching and retention cleanup are beyond this focused demo.

The [Android screen capture](docs/android-tracking.png) shows the minimal UI using emulator locations.

The [short Android recording](docs/demo.mp4) shows the installed release app capturing a point with Wi-Fi and mobile data disabled, automatically synchronizing after connectivity returns, and stopping tracking. The offline demo switch remains off throughout; coordinates come from the emulator's native GPS provider.

Verification performed for this refactor:

- Static analysis passed and all 22 unit tests passed, including three-second simulation and mode selection.
- The native Android integration check passed while minimized and screen-off; Stop removed the foreground service.
- The normal release APK built and passed the real network outage/recovery check with no external mock server.
- The installed-app integration test confirmed the default loopback API and internet-gated synchronization. Physical iPhone screen-lock behavior remains untested.
- The simulation integration test passed with the real three-second timer, offline SQLite records, REST acceptance after reconnecting, and no new points after Stop.
