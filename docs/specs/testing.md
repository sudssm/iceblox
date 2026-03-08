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

### screenshot.sh

Capture a screenshot to `/tmp/`.

```bash
scripts/simulator/screenshot.sh android
scripts/simulator/screenshot.sh ios
```

Outputs the file path of the saved screenshot. Screenshots are timestamped (`screenshot_<platform>_<timestamp>.png`) and accumulate in `/tmp/`.

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
- The app skips the splash screen and camera permission in test mode
- Images cycle through the detection pipeline on a 500ms interval
- The UI shows each test image with a `[TEST MODE]` banner instead of the camera preview

#### Android Test Mode Architecture

When launched with the `test_mode` intent extra:

1. `MainActivity` reads the extra, skips splash screen and camera permission
2. `CameraScreen` renders `TestImagePreview` instead of `CameraPreview`
3. `MainViewModel.startPipeline(isTestMode=true)` creates a `TestFrameFeeder`
4. `TestFrameFeeder` loads images, then cycles them through `FrameAnalyzer.analyzeBitmap()` on a coroutine timer
5. The full pipeline executes: detect → OCR → normalize → deduplicate → hash → queue → batch upload

This exercises the entire end-to-end path without a physical camera.

#### Adding Test Images

Drop `.png`, `.jpg`, `.jpeg`, or `.bmp` files into `android/app/src/debug/assets/test_images/`. These are included only in debug builds (the `src/debug/` source set is merged automatically by Gradle). For runtime injection without rebuilding, use the `--push-dir` flag.

## Coordinates

All coordinate-based scripts (tap, swipe) use **pixel coordinates matching the screenshot output**.

- **Android**: Screenshots are at device resolution (1080x2400 for the configured AVD). Coordinates go directly to `adb shell input`.
- **iOS**: Screenshots are at device resolution (1179x2556 for iPhone 16 Pro at 3x). The scripts internally map device pixels to Simulator window screen coordinates using the window's geometry.

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

## Limitations

### iOS Interaction

- **tap/type/swipe** use macOS-level CoreGraphics events (via `osascript`) to interact with the Simulator window. This requires:
  - The Simulator to be the frontmost application (scripts activate it automatically)
  - macOS Accessibility permissions granted to `/usr/bin/osascript` (System Settings > Privacy & Security > Accessibility)
  - The Simulator window to not be obscured by other windows
- **Coordinate mapping** assumes the Simulator renders the device screen filling the window content area with standard macOS title bar chrome. Unusual window sizing may cause coordinate drift.
- **inspect** (UI hierarchy dump) is not available for iOS without an XCUITest target. Use screenshots for visual inspection.

### Android Interaction

- `adb shell input text` does not handle all special characters. Stick to alphanumeric text and basic punctuation.
- `uiautomator dump` may not capture all Jetpack Compose elements — add `Modifier.testTag()` and `Modifier.semantics {}` to make elements discoverable.

## Future Enhancements

1. **iOS XCUITest interaction runner**: A dedicated UI test target providing reliable tap/type/swipe and UI hierarchy inspection via `XCUIApplication` APIs, replacing the AppleScript approach.
2. **Element-based interaction**: Tap by accessibility label or test tag instead of coordinates.
3. **Screenshot diff**: Automated visual regression testing.
