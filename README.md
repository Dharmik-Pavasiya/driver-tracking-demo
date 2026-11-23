# Driver location tracking & offline synchronization

A focused Flutter assessment demo with simulated GPS, a persistent SQLite outbox, a real local HTTP mock API, automatic synchronization, and retry-safe delivery. The UI includes a route illustration, pending/synced/blocked counts, and explicit offline and API-failure controls. Scope is appropriate for a 60–90 minute exercise; native background services are documented extensions.

## Setup

Prerequisites: Flutter **3.47.0** / Dart **3.13.0** (the versions used here), Git, and Chrome for the quickest demonstration. Android additionally needs the Android SDK and Java 17. iOS needs macOS, compatible Xcode/CocoaPods, and iOS 13 or later.

```sh
git clone https://github.com/Dharmik-Pavasiya/driver-tracking-demo.git
cd driver-tracking-demo
flutter pub get
```

From the repository root, start the API in terminal 1:

```sh
dart run mock_api/server.dart
```

Run the UI in terminal 2:

```sh
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://127.0.0.1:8081
```

The SQLite worker and WebAssembly binaries are committed in `web/`. After a dependency upgrade, regenerate them with `dart run sqflite_common_ffi_web:setup --force`. Keep the same web port: IndexedDB persistence is scoped to the browser origin, including its port.

To run the compiled app without Flutter's development runner:

```sh
flutter build web --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8081
dart run tool/serve_web.dart
```

Open `http://127.0.0.1:8080` while the API remains running.

Android emulator:

```sh
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://10.0.2.2:8081
```

Android debug builds allow HTTP for this local mock. For an Android USB device, use `adb reverse tcp:8081 tcp:8081` with `API_BASE_URL=http://127.0.0.1:8081`. Release builds should use HTTPS. iOS simulator on the same Mac uses `http://localhost:8081`; the plist permits local networking. No GPS permissions are needed for simulation.

## Demonstration (about a minute)

An edited screen-capture walkthrough is included at [docs/demo.gif](docs/demo.gif). It uses five screenshots from the running Flutter web app to show offline capture, automatic synchronization, failed uploads, and recovery. [docs/demo.jpg](docs/demo.jpg) is the final app preview.

1. Enable **Simulate offline**, then **Start tracking**. A point is captured immediately and every three seconds; pending count grows with no HTTP submissions.
2. **Stop tracking**. Turn offline simulation off. Pending points upload automatically and become synced, even with GPS stopped.
3. Select **API: fail before save (503)** and start/stop tracking to capture a point. Its attempt count and last error remain visible. Switch to **API: healthy** and wait for backoff or press **Retry now**.
4. Select **API: fail after save (503)** and capture a point. The server persists it but returns an error. Retry uses the same ID; the server acknowledges the existing point and local state becomes synced. The failure control can remain enabled for this replay.
5. Inspect `http://127.0.0.1:8081/locations` for unique server records. Repeated synchronization does not add entries.

For persistence testing, stop the mock server, capture points, and reload the app. Restart the mock: the persisted outbox drains automatically when retry deadlines are due. Tracking and demo switches reset on restart; the outbox, attempts, and retry times remain stored. Stopping GPS cancels new capture; an already captured write/upload may finish.

## Architecture and decisions

```text
UI / ListenableBuilder
        |
TrackingController (ChangeNotifier)
        |                 |
LocationSource       NetworkMonitor (connectivity_plus)
        |                 |
SQLite repository <- SyncService -> RestLocationApi -> local HTTP mock
```

- **Domain:** immutable `LocationRecord`; UUID generated once at capture, UTC timestamp, coordinates, status, attempts, error, and next retry time.
- **Data:** `LocationRepository` owns SQL. Mobile uses `sqflite`; web uses SQLite WASM persisted in IndexedDB. Native SQLite FFI tests use real temporary database files. The primary key prevents duplicate local inserts; an index selects pending due records. Individual SQL writes are atomic and target one ID, so acknowledgements cannot overwrite concurrent GPS inserts.
- **Services:** replaceable `LocationSource` and `LocationApi` interfaces. Connectivity is a wake-up signal, not proof the API is reachable: requests have an eight-second timeout and handle transport/server errors. Connectivity is rechecked on resume.
- **State:** Flutter's built-in `ChangeNotifier`/`ListenableBuilder`, with injected services and database. This separates acquisition, persistence, sync, and UI without a large framework or global service locator.
- **Sync:** save before HTTP; process due rows oldest first; acknowledge only a valid response matching the ID. A shared drain future prevents overlapping workers within an app instance. Capture, reconnection, startup, and a one-second foreground timer trigger sync. Persisted backoff is 2/4/8/16/32/60 seconds, capped at 60 seconds, plus 0–500ms jitter. HTTP 408/429/5xx and transport/protocol failures retry. Other HTTP rejections become blocked until explicit **Retry now**. Rows are retained; there is no retry-count limit.
- **Delivery:** at-least-once requests with idempotent server acceptance. A crash or lost response after server commit allows another request. The immutable UUID is sent as `Idempotency-Key`; only successful matching acknowledgement marks it synced. This does not claim exactly-once network transmission.
- **Mock:** Dart `HttpServer`, no extra runtime. Serialized requests and an atomically replaced JSON file persist acceptance before acknowledgement. Same ID/same payload succeeds; same ID/different payload returns 409. Accepted records survive restart. Failure injection applies only to new IDs, allowing replays after post-commit failure.

## API contract

`POST /locations`, `Content-Type: application/json`, `Idempotency-Key` equal to `id`:

```json
{"id":"uuid-v4","latitude":12.9716,"longitude":77.5946,"capturedAt":"2026-01-01T00:00:00.000Z"}
```

New record: `201 {"accepted":true,"id":"uuid-v4","duplicate":false}`. Replay: `200` with `duplicate:true`. Validation: `400`; conflicting payload: `409`; simulated failure: `503`. `GET /locations` returns `{count, locations}`; `GET /health` returns `{ok:true}`. `X-Demo-Failure: beforeCommit | afterCommit | none` enables failure injection. Runtime API data is ignored by Git.

## Automated checks

```sh
dart format --output=none --set-exit-if-changed lib test mock_api tool
flutter analyze
flutter test --reporter expanded
flutter build web --no-web-resources-cdn
```

Tests cover offline persistence through reopening SQLite; successful sync; duplicate enqueue and repeated sync; persisted retry deadlines; overlapping triggers with a concurrent GPS insert; permanent rejections; transport timeouts; stable request identity; invalid acknowledgements; real HTTP post-commit failure with server restart and deduplication; conflicting payloads; and simulator cancellation. GitHub Actions runs formatting, analysis, tests, and a web build.

Validation on the development host: all **11 tests passed**, `flutter analyze` reported no issues, and the web build succeeded. The live browser demonstration queued 34 points offline, synchronized them on reconnection, recovered six more after injected 503 failures, and retained all 40 synced records after reload. The 390px phone viewport was checked. Native Android/iOS builds were not run on this Windows host.

## Background GPS on Android and iOS

This foreground Dart-timer demo does **not** implement dependable tracking while minimized, locked, suspended, or terminated. A production extension would move acquisition and persistence into a native location service (or a plugin implementing one) and reuse the outbox/idempotency contract.

**Android:** use the Fused Location Provider in a location-type foreground service for an explicitly started journey. Obtain coarse/fine runtime authorization before starting while the activity is visible; declare `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` for applicable targets, and `foregroundServiceType="location"`. Keep an ongoing notification with a stop action. An authorized foreground service can continue a journey while minimized/locked. Background location permission is additionally needed for use cases accessing/starting location from the background; request it separately only when justified. Modern Android restricts background service starts and access to while-in-use permissions. Ordinary background apps receive only a few updates per hour. WorkManager with network constraints can flush points opportunistically; it is not a continuous GPS engine. Doze, OEM battery management, process death, reboot, and force-stop prevent promises of uninterrupted tracking. Persist each native callback and retry on resume/allowed worker execution.

**iOS:** enable Background Modes → Location updates (`UIBackgroundModes: location`) and accurate usage descriptions. Start Core Location while foregrounded with the authorization required by the journey lifecycle. Traditional `CLLocationManager` integrations use `allowsBackgroundLocationUpdates`; current APIs use retained `CLBackgroundActivitySession` / `CLServiceSession` objects on supported OS versions. Choose accuracy, distance filtering, and automatic pausing to balance battery use. Native location can deliver permitted updates while minimized/locked; a Dart timer cannot keep a suspended app running. Handle revoked authorization and reconstruct applicable sessions on relaunch. Background URLSession can deliver queued uploads; BGTaskScheduler is opportunistic without exact scheduling. User force-quit does not guarantee relaunch or continued GPS; significant-change/geofence services have different precision and relaunch behavior. For database access while locked, select a suitable file-protection class after the first unlock and assess its privacy tradeoff.

**Shared:** persist before upload, preserve IDs across restarts, serialize/lease workers when adding isolates or OS jobs, retain server idempotency, and test real devices under lock, battery saver, network changes, termination, and force-stop. OS execution windows do not guarantee delivery times.

References: [Android background location](https://developer.android.com/develop/sensors-and-location/location/background), [location foreground service requirements](https://developer.android.com/develop/background-work/services/fgs/service-types#location), [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [connectivity_plus caveats](https://pub.dev/packages/connectivity_plus).

## Deliberate limits

Single-user demo; no authentication, encryption, batching, retention cleanup, schema upgrades, or production observability. Coordinates are simulated. Synced history is retained; UI shows the latest 30 rows. The web SQLite adapter is experimental and browser storage can be evicted/cleared. Background workers need coordination beyond this per-instance drain, although server idempotency still protects acceptance. Local JSON persistence and development HTTP/CORS settings are assessment-only. Android/iOS scaffolds are included; native builds and lock-screen tracking need validation on their respective toolchains.
