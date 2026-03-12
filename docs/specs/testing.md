# Simulator Testing Toolkit

## Context

This project has iOS and Android mobile apps that need to be tested in simulators/emulators. This spec describes a set of shell scripts that enable programmatic simulator interaction: building, deploying, screenshotting, inspecting, and interacting with the apps.

The primary use case is AI-assisted testing — an AI agent can use these scripts to boot simulators, deploy the app, take screenshots (which it can view as images), inspect UI elements, and interact with the app through taps, typing, and swipes.

## Prerequisites

### Android

- Android SDK installed at `~/Library/Android/sdk/`
- AVD `Medium_Phone_API_36.1` configured
- `adb` and `emulator` binaries available in SDK paths

### iOS

- Xcode 16+ installed
- iPhone 16 Pro simulator available (UDID: `C06D96F6-6AE3-4B73-874F-C8324A15B0B9`)
- macOS Accessibility permissions granted to `/usr/bin/osascript` (required for iOS tap/type/swipe via CoreGraphics)

## Scripts Reference

All scripts live in `scripts/simulator/` and follow the pattern:

```
scripts/simulator/<action>.sh <ios|android> [arguments...]
```

Shared configuration (device IDs, SDK paths, helpers) lives in `scripts/simulator/_config.sh`.

### build.sh

Build the app for the simulator/emulator.

```bash
scripts/simulator/build.sh android
scripts/simulator/build.sh ios
```

- **Android**: Runs `./gradlew assembleDebug` in the `android/` directory. Output APK at `android/app/build/outputs/apk/debug/app-debug.apk`.
- **iOS**: Runs `xcodebuild build` targeting the iPhone 16 Pro simulator. Build artifacts in `ios/build/`.

### deploy.sh

Install and launch the app. Auto-boots the simulator/emulator if not running.

```bash
scripts/simulator/deploy.sh android
scripts/simulator/deploy.sh ios
```

- Auto-boots the target device if not already running
- Installs the most recently built app (run `build.sh` first)
- Launches the app's main activity/scene

**iOS programmatic launch:** To launch the iOS app with E2E environment variables (suppressing dialogs, enabling triggers), use `xcrun simctl launch` with `SIMCTL_CHILD_*` prefixed env vars:

```bash
SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
SIMCTL_CHILD_E2E_USE_SPLASH_TRIGGER=1 \
SIMCTL_CHILD_E2E_FORCE_DEBUG_MODE=1 \
xcrun simctl launch <UDID> com.iceblox.app
```

The app reads these via `ProcessInfo.processInfo.environment` in `AppConfig.swift`. See `e2e/ios/lib/app.sh` for the full set of E2E environment variables.

### screenshot.sh

Capture a screenshot to `/tmp/`.

```bash
scripts/simulator/screenshot.sh android
scripts/simulator/screenshot.sh ios
```

Outputs the file path of the saved screenshot. Screenshots are timestamped (`screenshot_<platform>_<timestamp>.png`) and accumulate in `/tmp/`.

### screenshot_session.sh

Automated screenshot session: build, deploy, launch, and capture screenshots at key stages.

```bash
scripts/simulator/screenshot_session.sh ios                          # basic session
scripts/simulator/screenshot_session.sh ios --skip-build             # reuse existing build
scripts/simulator/screenshot_session.sh ios --debug                  # enable debug overlay
scripts/simulator/screenshot_session.sh ios --debug --test-images ./e2e/android/fixtures/target_plate/
scripts/simulator/screenshot_session.sh android --debug
scripts/simulator/screenshot_session.sh ios --output-dir ./screenshots/
```

**Options:**

| Flag | Description |
|---|---|
| `--skip-build` | Reuse existing build artifacts |
| `--debug` | Enable debug overlay (iOS: `E2E_FORCE_DEBUG_MODE` env var; Android: triple-tap) |
| `--test-images DIR` | Push test images for pipeline testing instead of live camera |
| `--output-dir DIR` | Save screenshots to `DIR` (default: `/tmp`) |

**Screenshots captured:**

1. `01_pre_launch` — simulator home screen before launch
2. `02_splash` — app splash screen
3. `03_camera_active` — camera/test-image feed active
4. `04_debug_overlay` — debug overlay visible (only with `--debug`)

Files are named `session_<platform>_<step>_<timestamp>.png`.

**iOS launch details:** The script launches the app with environment variables via `SIMCTL_CHILD_*` prefix:

- `E2E_SKIP_NOTIFICATION_REQUEST=1` — suppresses the notification permission dialog
- `E2E_REQUEST_LOCATION_PERMISSION=0` — skips location permission prompt
- `E2E_USE_SPLASH_TRIGGER=1` — enables file-based splash-to-camera transition
- `E2E_FORCE_DEBUG_MODE=1` — forces debug overlay on without triple-tap (when `--debug`)

After launch, the script writes `e2e_start_camera.trigger` into the app's `Library/Application Support/` directory. The app polls for this file and transitions from the splash screen to the camera view when it appears.

### inspect.sh

Dump the UI element hierarchy.

```bash
scripts/simulator/inspect.sh android
```

- **Android**: Uses `uiautomator dump` to output XML with element bounds, text, resource IDs, and content descriptions. Use this to find tap targets by reading element bounds.
- **iOS**: Not yet available (requires XCUITest target). Use `screenshot.sh` for visual inspection.

### tap.sh

Tap at screen coordinates (in pixels, matching screenshot coordinate space).

```bash
scripts/simulator/tap.sh android <x> <y>
scripts/simulator/tap.sh ios <x> <y>
```

- **Android**: Uses `adb shell input tap`.
- **iOS**: Uses CoreGraphics events to click on the Simulator window at the mapped position. Requires Accessibility permissions.

### type.sh

Type text into the focused input field.

```bash
scripts/simulator/type.sh android "hello world"
scripts/simulator/type.sh ios "hello world"
```

- **Android**: Uses `adb shell input text`. Spaces are encoded automatically.
- **iOS**: Uses CoreGraphics keyboard events on the active Simulator. Simulator must be frontmost.

### swipe.sh

Perform a swipe gesture.

```bash
scripts/simulator/swipe.sh android <x1> <y1> <x2> <y2> [duration_ms]
scripts/simulator/swipe.sh ios <x1> <y1> <x2> <y2> [duration_ms]
```

Default duration is 300ms. Coordinates are in pixels (matching screenshot space).

- **Android**: Uses `adb shell input swipe`.
- **iOS**: Uses CoreGraphics mouse drag events on the Simulator window.

### navigate.sh

Perform system navigation.

```bash
scripts/simulator/navigate.sh android back
scripts/simulator/navigate.sh android home
scripts/simulator/navigate.sh ios home
```

- **Android**: Uses `adb shell input keyevent` (KEYCODE_BACK, KEYCODE_HOME).
- **iOS**: Uses `simctl terminate` to return to the home screen. iOS has no system "back" button — use `swipe.sh` from the left edge or tap the back button directly.

### logs.sh

View app logs.

```bash
scripts/simulator/logs.sh android          # dump recent logs
scripts/simulator/logs.sh android stream   # stream continuously
scripts/simulator/logs.sh ios              # dump recent logs
scripts/simulator/logs.sh ios stream       # stream continuously
```

- **Android**: Uses `adb logcat` filtered to the app's PID.
- **iOS**: Uses `xcrun simctl spawn booted log` with process predicate.

### test_mode.sh

Launch the Android app in test mode, feeding test images through the full detection pipeline instead of using the camera.

```bash
scripts/simulator/test_mode.sh                        # use images bundled in APK
scripts/simulator/test_mode.sh --push-dir ./plates/   # push images from local dir first
```

- Installs the debug APK and launches with `--ez test_mode true`
- Test images are loaded from two sources (in priority order):
  1. `android/app/src/debug/assets/test_images/` — bundled in the debug APK
  2. `filesDir/test_images/` — pushed at runtime via `--push-dir`
- `--push-dir` pushes images to the app's private storage using `adb push` + `run-as` (works on debuggable builds)
- The splash screen is shown normally — tap "Start Camera" to proceed
- The camera permission check is bypassed in test mode (no real camera needed)
- Images cycle through the detection pipeline on a 500ms interval
- The UI shows each test image with a `[TEST MODE]` banner instead of the camera preview

#### Android Test Mode Architecture

When launched with the `test_mode` intent extra:

1. `MainActivity` reads the extra, shows splash screen, bypasses camera permission on "Start Camera" tap
2. `CameraScreen` renders `TestImagePreview` instead of `CameraPreview`
3. `MainViewModel.startForegroundPipeline(isTestMode=true)` creates a `TestFrameFeeder`
4. `TestFrameFeeder` loads images, then cycles them through `FrameAnalyzer.analyzeBitmap()` on a coroutine timer
5. The full pipeline executes: detect → OCR → normalize → deduplicate → hash → queue → batch upload

This exercises the entire end-to-end path without a physical camera.

#### Adding Test Images

Drop `.png`, `.jpg`, `.jpeg`, or `.bmp` files into `android/app/src/debug/assets/test_images/`. These are included only in debug builds (the `src/debug/` source set is merged automatically by Gradle). For runtime injection without rebuilding, use the `--push-dir` flag.

## Coordinates

All coordinate-based scripts (tap, swipe) use **pixel coordinates matching the screenshot output**.

- **Android**: Screenshots are at device resolution (1080x2400 for the configured AVD). Coordinates go directly to `adb shell input`.
- **iOS**: Screenshots are at device resolution (1206x2622 for the configured iPhone 16 Pro simulator at 3x). The scripts internally map device pixels to Simulator window screen coordinates using the window's geometry.

## Testing Workflow

The standard loop for testing a change:

```
1. Build     →  scripts/simulator/build.sh <platform>
2. Deploy    →  scripts/simulator/deploy.sh <platform>
3. Screenshot → scripts/simulator/screenshot.sh <platform>  →  view the image
4. Inspect   →  scripts/simulator/inspect.sh android         →  read element tree
5. Interact  →  tap.sh / type.sh / swipe.sh / navigate.sh
6. Verify    →  screenshot again, check logs
7. Iterate   →  edit code, go to step 1
```

### Example: Verify Android app launches correctly

```bash
scripts/simulator/build.sh android
scripts/simulator/deploy.sh android
scripts/simulator/screenshot.sh android
# → view /tmp/screenshot_android_20260308_143022.png

scripts/simulator/inspect.sh android
# → find elements: TextView "Hello, World!" at [417,1337][664,1400]

# Tap on the text
scripts/simulator/tap.sh android 540 1368

scripts/simulator/screenshot.sh android
# → verify state changed
```

### Example: Verify iOS app launches correctly

```bash
scripts/simulator/build.sh ios
scripts/simulator/deploy.sh ios
scripts/simulator/screenshot.sh ios
# → view /tmp/screenshot_ios_20260308_143055.png

# Go home and return
scripts/simulator/navigate.sh ios home
scripts/simulator/screenshot.sh ios
```

## iOS Simulator Best Practices

### Prefer env-var and file-based triggers over coordinate taps

iOS Simulator coordinate mapping is unreliable on multi-monitor setups. The `ios_map_coords` function reads screen geometry from a plist and picks the first entry, which may not correspond to the monitor the Simulator is actually on. This causes taps to land on the wrong screen or wrong coordinates.

**Instead of tapping UI elements, use environment variables or file-based triggers to drive the app programmatically:**

- **Environment variables** (via `SIMCTL_CHILD_*` prefix): Set flags that the app reads in `AppConfig.swift` to skip dialogs, auto-navigate to screens, or enable test modes. Examples:
  - `SIMCTL_CHILD_E2E_AUTO_SHOW_REPORT=1` — opens the report sheet without tapping
  - `SIMCTL_CHILD_E2E_AUTO_SHOW_SETTINGS=1` — opens the settings sheet without tapping
  - `SIMCTL_CHILD_E2E_USE_SPLASH_TRIGGER=1` — enables file-based splash-to-camera transition
  - `SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1` — suppresses notification permission dialog
  - `SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0` — skips location permission prompt

- **File-based triggers**: Write a trigger file into the app's `Library/Application Support/` directory. The app polls for it and transitions state when it appears. Use for transitions that happen after launch (e.g., splash → camera).

When adding new UI flows that need E2E testing or screenshots, add a corresponding `E2E_*` env var in `AppConfig.swift` and check it in the relevant view's `.onAppear` or init. This is more reliable than coordinate-based interaction and works regardless of monitor setup.

### Write scripts, don't execute steps individually

For E2E tests and screenshot sessions, always write a self-contained shell script that does all the work (build, deploy, launch, screenshot, etc.) and produces output files. Then read the results. This is more reproducible and avoids losing progress if a single step fails interactively.

Example: `scripts/simulator/screenshot_report_flow.sh` builds the app, installs it, launches twice (once for splash, once with `E2E_AUTO_SHOW_REPORT=1` for the report form), and saves both screenshots to an output directory.

### Port conflicts

When running E2E tests, port 8080 may be occupied by another workspace's server. Use `E2E_SERVER_PORT` to pick an alternate port (e.g., `E2E_SERVER_PORT=8099 e2e/ios/run.sh`). The E2E infrastructure passes this to both the Go server and the app.

### Clean app state

Uninstall the app before reinstalling to clear cached permission dialogs (notification, location). Even with `E2E_SKIP_NOTIFICATION_REQUEST=1`, a previously-granted notification permission dialog may re-trigger if the app was installed before. Use:

```bash
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_PATH"
```

### Grant permissions upfront

To avoid interactive permission dialogs blocking automation:

```bash
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID"
xcrun simctl privacy "$UDID" grant camera "$BUNDLE_ID"
```

## Limitations

### iOS Interaction

- **tap/type/swipe** use macOS-level CoreGraphics events (via `osascript`) to interact with the Simulator window. This requires:
  - The Simulator to be the frontmost application (scripts activate it automatically)
  - macOS Accessibility permissions granted to `/usr/bin/osascript` (System Settings > Privacy & Security > Accessibility)
  - The Simulator window to not be obscured by other windows
- **Coordinate mapping** is unreliable on multi-monitor setups — `ios_map_coords` picks the first screen entry from a plist, which may not match the Simulator's actual monitor. Prefer env-var/file-based triggers over coordinate taps.
- **inspect** (UI hierarchy dump) is not available for iOS without an XCUITest target. Use screenshots for visual inspection.

### Android Interaction

- `adb shell input text` does not handle all special characters. Stick to alphanumeric text and basic punctuation.
- `uiautomator dump` may not capture all Jetpack Compose elements — add `Modifier.testTag()` and `Modifier.semantics {}` to make elements discoverable.

## E2E Testing

End-to-end tests validate the full pipeline: the Android and iOS apps detect a plate from injected images, hash it, post it to the Go server, and the server persists a sighting in PostgreSQL.

### Entry Point

```bash
e2e/android/run.sh              # full run: build + infra + tests
e2e/android/run.sh --skip-build  # reuse existing APK
e2e/ios/run.sh                  # full run: build + infra + tests
e2e/ios/run.sh --skip-build     # reuse existing .app build
```

### How It Works

1. **Infrastructure**: Starts an ephemeral PostgreSQL container (random port) and the Go server with `testdata/test_plates.txt`
2. **App**: Builds and installs the debug app on the target simulator/emulator
3. **Injection**:
   - **Android**: Pushes fixture images to `filesDir/test_images/` and launches with `--ez test_mode true`
   - **iOS**: Launches the app with `E2E_SKIP_NOTIFICATION_REQUEST=1` to suppress the notification permission dialog, then triggers the start-camera transition by writing a splash trigger file into the app container's `Library/Application Support/` directory and waiting for the app to consume it. Once in camera mode, the harness copies fixture images into `Library/Application Support/test_images/`. The harness can also touch an Application Support stop-trigger file and wait for a session-summary artifact written by the app.
4. **Verification**: Queries the database directly (via `docker exec psql`) to check for sightings, then verifies stop-summary behavior from UI state (Android) or the summary artifact (iOS)
5. **Cleanup**: `trap EXIT` stops the app, kills the server, and removes the postgres container

### Test Scenarios

- **No-plate image** (`tests/test_no_plate.sh`): Pushes an image with no license plates. After the batch flush interval, verifies zero sightings in the database.
- **Non-target plate image** (`tests/test_non_target_plate.sh`): Pushes an image containing a real plate that is NOT in `test_plates.txt`. After the batch flush interval, verifies zero sightings (the app detects and uploads the plate, but the server does not match it).
- **Target plate image** (`tests/test_target_plate.sh`): Pushes an image containing a known test plate. After the batch flush interval, verifies at least one matched sighting exists in the database.
- **Stop recording summary**: The Android target-plate test taps `Stop Recording` and inspects the summary overlay. The iOS target-plate test triggers stop via an Application Support file and validates the summary artifact fields emitted by the app.
- **Background capture** (`tests/test_background_capture.sh`): Pushes a target plate image, starts the camera, then backgrounds the app via `KEYCODE_HOME`. Verifies the app process survives backgrounding, remains alive after the batch flush window, and produces at least one sighting while backgrounded.
- **Batch upload** (`tests/test_batch_upload.sh`): Pushes a target plate image, starts the camera, waits for the batch flush, then verifies the server received batch-format POSTs (with `count=` in logs) and sightings were recorded. The Android version additionally verifies the upload queue banner appears while plates are queued and clears after the flush.
- **Proximity subscribe** (`tests/test_proximity_alerts.sh`): After a target plate sighting exists, calls `POST /api/v1/subscribe` with coordinates near the sighting (radius 500 miles) and verifies nearby sightings are returned, then calls subscribe with distant coordinates (radius 1 mile) and verifies zero sightings are returned.
- **Device registration** (`tests/test_device_registration.sh`): Calls `POST /api/v1/devices` with a valid token and verifies status=ok and the token is stored in the database. Also verifies upsert behavior (re-registering the same device does not duplicate) and that an empty token returns 400.
- **Match debug label** (`tests/test_match_debug_label.sh`): Pushes a target plate image, enables debug mode via triple-tap, waits for the batch flush, then verifies the server logged a match and the debug feed shows a `[MTCH]` label for the matched plate.
- **Queued entries clear** (`tests/test_queued_clears.sh`): Pushes a target plate image, enables debug mode via triple-tap, waits for the batch flush, then verifies all detection feed entries have transitioned from QUEUED to either SENT or MATCHED (no entries remain stuck in QUEUED state).
- **Report API** (`tests/test_report_submission.sh` / `tests/test_report_ice.sh`): Submits a report via `POST /api/v1/reports` with a photo, description, and coordinates. Verifies the response includes `status: ok` and a `report_id`, and that the report is stored in the database with correct fields (description, latitude, longitude, photo path).
- **Report validation** (`tests/test_report_submission.sh` / `tests/test_report_ice.sh`): Verifies that missing required fields (description, photo, X-Device-ID) and out-of-range coordinates return `400 Bad Request`.
- **Report app UI** (Android: `tests/test_report_submission.sh`): Taps "Report ICE Activity" on the splash screen, verifies the report form opens with a description field visible, and attempts a submission through the app UI.
- **Zoom retry initialization** (Android: `tests/test_zoom_retry_init.sh`): Launches the app in test mode and verifies that ZoomController initializes at camera startup, logging its optical zoom detection results. On emulators, verifies `maxOpticalZoom=1.0` and `available=false` (no optical zoom hardware).
- **Settings UI** (Android: `tests/test_settings.sh`, iOS: `tests/test_settings.sh`): Opens the settings screen and verifies the Push Notifications toggle is visible. Android version taps the Settings button on the splash screen. iOS version launches with `E2E_AUTO_SHOW_SETTINGS=1` and captures a screenshot.
- **Settings toggle persistence** (Android: `tests/test_settings.sh`): Opens settings, toggles the Push Notifications switch, navigates back, reopens settings, and verifies the toggle state persisted.
- **Map sightings API** (Android: `tests/test_map_sightings.sh`, iOS: `tests/test_map_sightings.sh`): Seeds a plate sighting and a report, then queries `GET /api/v1/map-sightings` and verifies the response contains both entries with required fields (latitude, longitude, confidence, seen_at, type).
- **Map sightings validation** (Android: `tests/test_map_sightings.sh`, iOS: `tests/test_map_sightings.sh`): Verifies that missing lat returns 400, out-of-range radius returns 400, empty area returns 0 sightings, and POST method returns 405.
- **Map view UI** (Android: `tests/test_map_sightings.sh`, iOS: `tests/test_map_sightings.sh`): Taps "View Map" on the splash screen, verifies the map header text is visible, then navigates back to the splash screen.

### Prerequisites

- Docker (for ephemeral PostgreSQL)
- Android SDK with emulator (`Medium_Phone_API_36.1` AVD configured)
- Go toolchain (to build and run the server)

### Fixtures

Test images live in `e2e/android/fixtures/` and are shared by both mobile harnesses:
- `no_plate/` — images without license plates
- `non_target_plate/` — images with real plates not in `test_plates.txt`
- `target_plate/` — images with known test plates (e.g., AB12345)

For iOS simulator E2E, optional same-basename `.txt` sidecars can accompany injected images:
- `target_plate/target.txt` → `AB12345`
- `non_target_plate/non_target.txt` → `ZZZ9999`

When present, the simulator camera injects that normalized plate string into the post-detection pipeline. This keeps iOS E2E deterministic even when simulator OCR differs from device behavior.
The iOS harness still launches on the real splash screen first; it only uses the sidecar after the splash-to-camera transition has happened.
For stop-summary verification, the iOS harness sets `E2E_USE_STOP_RECORDING_TRIGGER=1`, touches `Library/Application Support/e2e_stop_recording.trigger`, and waits for `Library/Application Support/e2e_session_summary.txt`.

### Timing

- Both platforms flush within 1 second of any plate being queued (deadline flush). The 30-second batch timer is a fallback safety net.
- **iOS**: The E2E harness overrides the batch interval to 1 second at launch, so each scenario waits 6 seconds for upload and DB persistence.

## Local Device Testing

`scripts/android-test.sh` supports testing on a physical Android device connected via USB or Wi-Fi ADB. It automates the full build-deploy-run cycle for local development.

```bash
scripts/android-test.sh               # local server (default)
scripts/android-test.sh --prod-server  # prod server (Railway)
```

**What it does:**

1. **Connects** to a USB-attached device or prompts for a Wi-Fi ADB address
2. **Patches** `AppConfig.SERVER_BASE_URL` for the target (localhost via `adb reverse`, or the Railway production URL)
3. **Builds and installs** the debug APK
4. **Reverts** the AppConfig patch after build
5. **Launches** the app on the device
6. **(Local only)** Starts a Docker PostgreSQL container if needed, sets up `adb reverse tcp:8080`, and runs the Go server in the foreground

A `trap EXIT` handler reverts the AppConfig URL on script exit regardless of how it terminates.

## Future Enhancements

1. **iOS XCUITest interaction runner**: A dedicated UI test target providing reliable tap/type/swipe and UI hierarchy inspection via `XCUIApplication` APIs, replacing the AppleScript approach.
2. **Element-based interaction**: Tap by accessibility label or test tag instead of coordinates.
3. **Screenshot diff**: Automated visual regression testing.
4. **E2E in CI**: Run Android E2E tests in GitHub Actions with an emulator and Docker services.
