# Driver Location

A focused Android/iOS Flutter demo using GetX, native GPS and SQLite. The single screen has Start/Stop, latest coordinates, upload counts, recent points and demo controls. Both modes use real native GPS: normal tracking captures delivered fixes, and periodic mode samples the latest measured fix every three seconds.

## Setup instructions

Tested toolchain: Flutter 3.47.0 and Dart 3.13.0. This project has Android and iOS targets only. GitHub access to this private repository is required to clone it.

### Prerequisites

- Flutter SDK and Git available in your terminal.
- Android: Android SDK, an emulator or a phone with USB debugging, and Java 17 or a compatible newer JDK.
- iOS: macOS, Xcode with its command-line tools, and an iOS 15-or-later simulator or provisioned iPhone. The project uses Swift Package Manager for native plugins.

### Get the project

```sh
git clone https://github.com/Dharmik-Pavasiya/driver-tracking-demo.git
cd driver-tracking-demo
flutter pub get
flutter doctor
flutter devices
```

Resolve any Android or iOS toolchain issues reported by `flutter doctor` before running that platform.

### Run on Android

Start an Android emulator or connect a phone with USB debugging. Use its ID from `flutter devices`:

```sh
flutter run -d <android-device-id>
```

To build an APK for installation:

```sh
flutter build apk --release
```

Install `build/app/outputs/flutter-apk/app-release.apk`. The assessment APK uses the project's debug signing configuration; it is not signed for store distribution.

### Run on iOS

On a Mac, let Flutter prepare the generated Swift package, check compilation, and then open the workspace:

```sh
flutter build ios --debug --no-codesign
open ios/Runner.xcworkspace
```

Flutter and Xcode resolve the native plugin packages through Swift Package Manager. The unsigned build checks compilation; installation on a physical iPhone requires signing.

For a physical iPhone, select the Runner target, choose your team under Signing & Capabilities, and use a bundle identifier that your team can provision. Start an iOS simulator or connect the provisioned iPhone, then run:

```sh
flutter run -d <ios-device-id>
```

### Backend and permissions

**No backend setup is required.** The installed app starts a real HTTP mock on its own loopback address and chooses a free port. There is no computer IP, port forwarding or server URL to enter. It works the same way in an installed Android APK and an iOS app. Android permits cleartext HTTP only for loopback hosts; internet checks use HTTPS.

Enable GPS, press **Start tracking**, and grant location permission. Android also requests notification permission for its ongoing tracking notification. Start the journey while the app is visible, then minimize or lock it. Move beyond the ten-metre distance filter to receive another fix. GPS can take a few seconds, especially indoors.

Enable **GPS every 3 seconds** before Start to sample real coordinates on a timer. GPS must be enabled and location permission granted. The app waits for a native fix, then saves the latest measured coordinates every three seconds. Periodic mode requests Android GPS updates every three seconds with a zero-distance filter; the OS controls when fixes arrive. Moving the phone updates that fix; stationary samples may have identical coordinates. No offsets, random coordinates or generated routes are used.

Each sample has a fresh UUID and preserves the native GPS fix timestamp, so repeating a stationary fix does not claim that GPS measured a new position. The same SQLite, internet checks, REST uploads and retries apply. Stop cancels both the timer and native GPS subscription.

Periodic mode also starts the native location service. Its three-second Dart timer runs while the OS gives the app execution time; iOS suspension can delay ticks. Normal native GPS remains the option for assessing background callbacks without a timer. For emulator GPS, use Android Emulator → Extended Controls → Location, or iOS Simulator → Features → Location.

## Try the workflow

1. Enable **Simulate offline**, press Start, and move or inject coordinates. Pending points are saved in SQLite.
2. Minimize or lock during tracking, continue moving, then reopen the app to inspect the saved points.
3. Disable the offline switch while the device has internet. Pending points synchronize automatically. You can also turn off Wi-Fi and mobile data to test real offline behavior.
4. Choose **Fail before saving** and capture another point. The mock returns HTTP 503; attempts and the retry error remain saved. Select Healthy and wait, or press Retry pending uploads.
5. Choose **Fail after saving** and capture a point. The mock stores it but returns 503. The retry sends the same ID and succeeds without another accepted record, even if this failure option remains selected.
6. Stop tracking. GPS and Android's foreground notification stop; saved uploads remain eligible for synchronization. Close and reopen the app to check persistence.

In this demonstration, **synced means accepted by the on-device mock**, not uploaded to a remote cloud service. The mock is reachable locally even without internet; the synchronization service deliberately gates uploads on actual internet availability to demonstrate the assessment's offline/reconnection behavior. Both outbox records and mock acceptance IDs survive app restart. Tracking and demo switches reset when the process ends, so press Start again for a new journey. The UI shows ten recent points; SQLite retains all records.

## Architecture

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
    simulated_location_service.dart Sample real GPS every three seconds
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

### Architectural decisions

| Decision | Reason and practical limit |
| --- | --- |
| GetX bindings, constructor injection and small `Obx` regions | Matches the supplied template and keeps dependency creation out of widgets. A reactive change updates its dependent UI sections. Widget methods stay in the screen file. |
| Screen controller, root services and repository | The controller handles Start/Stop and screen actions. Shared services handle GPS, connectivity and uploads; the repository owns SQL. `AppScreens` registers route names, views and bindings together. |
| SQLite outbox as the source of truth | Every point is saved before HTTP, so offline records and retry deadlines survive restart. Updates target one row, preventing an upload acknowledgement from overwriting another captured point. |
| Native GPS with an optional three-second sampler | Both modes use measured device coordinates. The sampler copies the latest fix and its original timestamp; it does not invent movement. Native fix delivery and background execution depend on the OS. |
| Automatic on-device REST mock | An installed phone needs no computer, LAN address or separate backend. Acceptance is stored separately from the outbox. In this demo, synced means accepted locally by the mock. |
| Stable UUID and idempotent acceptance | Each captured point or periodic sample gets an ID once; retries reuse it. The mock acknowledges matching replays and rejects a changed payload for the same ID. Requests may occur more than once without creating another accepted record. |
| One shared sync operation with persisted backoff | Overlapping capture, reconnect and retry triggers share a single upload operation. Sequential requests keep the code simple; saved attempts and deadlines preserve retry behavior across restart. |
| Transport events plus HTTPS internet probes | Wi-Fi alone does not prove internet access. Successful probes permit automatic synchronization; a network that blocks both probe providers can delay uploads. |

This is a focused assessment demo. A remote authenticated API, OS-scheduled uploads, retention limits and production signing are future extensions.

### Reading order and data flow

Start reading `TrackingController.startTracking`, then `_saveLocation`, `LocationRepository.enqueue`, `SyncService._uploadPending`, `_uploadRecord` and `RestLocationApi.upload`.

1. Native GPS supplies measured coordinates and a UTC fix timestamp. Normal tracking records delivered fixes; periodic mode samples the latest fix every three seconds. Each saved point or sample receives one UUID.
2. The controller awaits the SQLite insert before requesting synchronization.
3. The synchronization service checks internet and reads the oldest due pending row.
4. It counts the attempt and sends the original ID as `Idempotency-Key`.
5. Only HTTP 200/201 with `accepted: true` and that same ID marks the row synced.
6. Failure saves the error and next retry deadline. A later pass uses the same ID and payload.

SQLite owns the durable data. `SyncService.records` is a current Rx copy for the view, with derived counts. `Obx` rebuilds when these fields change. The controller handles screen actions; synchronization owns one retry timer and its network listener. SQL stays in the repository, HTTP in the API class, and native settings in the location service. Application classes and methods have documentation comments. A separate local workflow guide is deliberately excluded from Git.

`TrackingView.build` assembles the app bar and body through widget methods in the same screen file. Each reactive component has its own `Obx`, so an upload error updates its message without rebuilding Start/Stop or the list container. Saved-record changes update the coordinates, counts and recent-record section. All handwritten Dart files are under 500 lines.

## Internet checks and delivery

`connectivity_plus` reports available network transports. The service also requires HTTP 204 from an HTTPS probe at `www.gstatic.com/generate_204`, falling back to `cp.cloudflare.com/generate_204`. Each request has a three-second timeout. A Wi-Fi connection with captive-portal HTML, or failure of both probes, remains offline. Probes contain no location data. A network that blocks both providers may delay uploads even when other sites work.

Network changes, new GPS fixes, app resume and a five-second check request synchronization while the app has execution time. Overlapping triggers share one active upload operation. Points upload sequentially, and each request times out after eight seconds.

Retry deadlines use delays of 2, 4, 8, 16, 32 and then 60 seconds. Attempts and deadlines survive restart. These are minimum delays; the next eligible trigger performs the upload. HTTP 408/429/5xx and transport or invalid-response failures retry automatically. Other HTTP rejections become blocked until explicit review/retry.

The mock has a separate `mock_locations` acceptance table. Its SQLite transaction accepts a new ID once, acknowledges a matching replay, and returns 409 for the same ID with a changed payload. The outbox primary key also prevents duplicate local IDs. This provides at-least-once requests with idempotent acceptance, including a committed request whose acknowledgement fails.

## Background GPS on Android and iOS

Start tracking while the app is visible and grant location permission. The controller keeps the native GPS subscription active when the app is minimized or the screen is locked. Stop cancels GPS and the periodic sampling timer.

**Android:** Geolocator runs a native location foreground service with an ongoing notification and wake lock. The manifest declares foreground-service/location permissions and the plugin uses `foregroundServiceType="location"`. This supports an active journey while minimized or locked. Starting or restarting from the background must also satisfy Android's background-location authorization and foreground-service start restrictions.

**iOS:** Core Location continues an authorized session through Location Background Mode (`UIBackgroundModes: location`). The adapter enables background updates, disables automatic pausing and shows the system location indicator. Additional background-start or relaunch use cases may require Always authorization; this demo starts from the visible screen.

**Storage and synchronization:** Normal-mode native callbacks save each delivered fix to SQLite before uploading. Resume rechecks the pending queue. The three-second sampler uses the latest native fix, but its timer cannot guarantee that cadence while iOS is suspended. Production deferred uploads would use WorkManager on Android and background URLSession on iOS with a remote API.

**Reliability limits:** Force-stop/force-quit, OS termination, revoked permission or battery policies can end tracking. This demo requires a new Start after termination. Production validation should cover real-device battery behavior and iOS database file protection while locked. Android emulator minimized/screen-off behavior was verified; physical iPhone screen-lock behavior remains untested.

References: [Geolocator](https://pub.dev/packages/geolocator), [Android location foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#location), [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background).

## Validation

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter test integration_test/install_and_run_test.dart -d <device-id>
# Android emulator only; follow the linked GPS injection instructions first
flutter test integration_test/simulated_tracking_test.dart -d emulator-5554 --reporter expanded
flutter build apk --release
# macOS only; signing is needed for physical iPhone installation
flutter build ios --debug --no-codesign
```

Unit tests cover persistent offline storage, retries and saved deadlines, reconnection, overlapping upload triggers, permanent rejections, acknowledgements, captive portals, fallback internet probes, on-device HTTP mock acceptance/replay, simulation cadence/cancellation, independent UI updates and native settings. The install-and-run integration test verifies internet-gated synchronization to the automatically started phone mock. The periodic-mode emulator test checks known native GPS fixes, stationary samples, movement, offline storage, upload and Stop. See the emulator preparation instructions before running it.

The optional [native Android emulator check](docs/android-emulator-check.md) exercises actual GPS callbacks while minimized and screen-off, then Stop and reconnection. These Android checks do not establish iPhone runtime behavior. Physical iPhone screen-lock behavior has not been tested. GitHub Actions validates Android analysis/tests/build and an unsigned iOS build on macOS.

On Windows, `kotlin.incremental=false` avoids Kotlin's cross-drive Pub-cache build error. Signing for stores, authentication, batching and retention cleanup are beyond this focused demo.

The [Android screen capture](docs/android-tracking.png) shows the minimal UI using emulator locations.

The [short Android recording](docs/demo.mp4) shows the installed release app capturing a point with Wi-Fi and mobile data disabled, automatically synchronizing after connectivity returns, and stopping tracking. The offline demo switch remains off throughout; coordinates come from the emulator's native GPS provider.

The [simulation recording](docs/simulation-demo.mp4) shows the installed app sampling and uploading native GPS coordinates every three seconds, then stopping tracking.

Verification performed for this refactor:

- Static analysis passed and all 26 tests passed, including real-coordinate sampling, native GPS settings, mode selection and component-scoped UI updates.
- The native Android integration check passed while minimized and screen-off; Stop removed the foreground service.
- The normal release APK built and passed the real network outage/recovery check with no external mock server.
- The installed-app integration test confirmed the default loopback API and internet-gated synchronization. Physical iPhone screen-lock behavior remains untested.
- The periodic GPS emulator test passed with stationary and moved native fixes, offline SQLite records, REST acceptance after reconnecting, and cancellation of both native GPS and timer on Stop.
