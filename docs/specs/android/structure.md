# Android App Structure

## Overview

The Android app is built with **Kotlin** and **Jetpack Compose** targeting **API 28+ (Android 9.0+)**, using the standard Gradle project layout with version catalogs.

## Project Layout

```
android/
├── build.gradle.kts               # Root build file (KSP, Google Services plugins)
├── settings.gradle.kts             # Project settings & dependency resolution
├── gradle.properties               # Gradle configuration
├── gradle/
│   ├── wrapper/
│   │   ├── gradle-wrapper.jar
│   │   └── gradle-wrapper.properties
│   └── libs.versions.toml          # Version catalog
├── gradlew                         # Gradle wrapper (unix)
├── gradlew.bat                     # Gradle wrapper (windows)
└── app/
    ├── build.gradle.kts            # App module build file
    ├── google-services.json        # Firebase configuration (FCM)
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── java/com/iceblox/app/
        │   │   ├── IceBloxApplication.kt   # Application-scoped capture repository
        │   │   ├── MainActivity.kt         # Activity entry point, permission requests, splash→camera flow, notification channel, service handoff
        │   │   ├── MainViewModel.kt        # Foreground UI state wrapper around shared capture repository, session lifecycle
        │   │   ├── capture/
        │   │   │   └── CaptureRepository.kt # Shared pipeline state used by UI + background service
        │   │   ├── camera/
        │   │   │   ├── BrightnessManager.kt # Screen dimming during scanning, tap-to-restore (REQ-M-4a)
        │   │   │   ├── CameraCaptureBinder.kt # Shared CameraX bind/unbind helper for UI + service
        │   │   │   ├── CameraPreview.kt    # Compose CameraX preview wrapper
        │   │   │   ├── FrameAnalyzer.kt    # ImageAnalysis.Analyzer → detect → OCR → normalize → zoom retry on failed OCR
        │   │   │   ├── FrameDiffer.kt      # 64x64 grayscale frame diff to skip static frames (REQ-M-4b)
        │   │   │   ├── PreviewFreezer.kt   # Frozen-frame overlay state for zoom retry UX
        │   │   │   ├── TestFrameFeeder.kt  # Test mode: loads images, feeds them through analyzeBitmap() on a timer
        │   │   │   └── ZoomController.kt   # Optical zoom detection, safe zoom ratio calculation, zoom-capture-restore
        │   │   ├── config/
        │   │   │   └── AppConfig.kt        # Confidence thresholds, batch sizes, server URL, notification config, zoom retry constants, battery optimization config
        │   │   ├── detection/
        │   │   │   ├── PlateDetector.kt    # TFLite interpreter, YOLOv8-nano inference, NMS
        │   │   │   └── PlateOCR.kt         # ONNX Runtime CCT-XS inference + fixed-slot decode on cropped bitmaps
        │   │   ├── location/
        │   │   │   └── LocationProvider.kt # FusedLocationProviderClient, permission handling, distance filter (REQ-M-4d)
        │   │   ├── motion/
        │   │   │   └── MotionStateManager.kt # Activity Recognition Transition API, stationary detection, auto-pause (REQ-M-4c)
        │   │   ├── network/
        │   │   │   ├── AlertClient.kt      # Subscribe endpoint client, coroutine timer, GPS truncation
        │   │   │   ├── ApiClient.kt        # OkHttp POST /api/v1/plates + /api/v1/devices, batch, 429 handling
        │   │   │   ├── ConnectivityMonitor.kt # ConnectivityManager.NetworkCallback
        │   │   │   ├── DeviceTokenManager.kt # FCM token registration with retry
        │   │   │   ├── MapClient.kt        # OkHttp GET /api/v1/map-sightings for map view
        │   │   │   ├── ReportClient.kt     # OkHttp multipart POST to /api/v1/reports (ICE vehicle reports)
        │   │   │   └── RetryManager.kt     # Exponential backoff, rate limit tracking
        │   │   ├── notification/
        │   │   │   ├── NotificationHelper.kt # Notification channel creation, alert display
        │   │   │   └── PushNotificationService.kt # FirebaseMessagingService: onNewToken, onMessageReceived
        │   │   ├── persistence/
        │   │   │   ├── OfflineQueueDao.kt  # Room DAO: insert, dequeue, delete, count
        │   │   │   ├── OfflineQueueDatabase.kt # Room database singleton
        │   │   │   └── OfflineQueueEntry.kt # Room entity: hash, timestamp, lat, lng, session_id, confidence, is_primary
        │   │   ├── processing/
        │   │   │   ├── DeduplicationCache.kt # Session-scoped text + hash dedup
        │   │   │   ├── LookalikeExpander.kt # BFS expansion of confusable characters (REQ-M-12a)
        │   │   │   ├── PlateHasher.kt      # HMAC-SHA256 via javax.crypto.Mac, pepper from BuildConfig
        │   │   │   └── PlateNormalizer.kt  # Uppercase, strip, validate 2-8 chars
        │   │   ├── settings/
        │   │   │   └── UserSettings.kt       # SharedPreferences-backed push notification + user debug mode toggles
        │   │   ├── service/
        │   │   │   └── BackgroundCaptureService.kt # Foreground service that keeps analysis running when app backgrounds
        │   │   ├── debug/
        │   │   │   └── DebugLog.kt           # Singleton logger: ring buffer + StateFlow for UI
        │   │   └── ui/
        │   │       ├── CameraScreen.kt     # Compose: camera preview + status bar + stop control + session summary (includes StatusBar, TestImagePreview, SessionSummaryOverlay composables)
        │   │       ├── SplashScreen.kt     # Splash screen with app name and Start Camera button
        │   │       ├── MapViewScreen.kt    # Map view showing nearby sightings and reports with offline caching
        │   │       ├── ReportICEScreen.kt  # ICE vehicle report form (photo capture, description, plate, Google Map, submit)
        │   │       ├── SettingsScreen.kt  # Settings screen with push notification + debug mode toggles
        │   │       ├── DebugOverlay.kt      # Bounding boxes, plate text, hash, FPS, detection feed
        │   │       ├── DebugLogPanel.kt     # Translucent log panel at bottom of debug overlay
        │   │       └── theme/
        │   │           ├── Theme.kt        # Material 3 theme
        │   │           ├── Color.kt        # Color definitions
        │   │           └── Type.kt         # Typography
        │   └── res/
        │       ├── values/
        │       │   ├── strings.xml
        │       │   ├── colors.xml
        │       │   └── themes.xml
        │       └── drawable/
        ├── debug/
        │   └── assets/
        │       └── test_images/             # Test plate images for test mode (debug builds only)
        └── test/
            └── java/com/iceblox/app/
                ├── ExampleUnitTest.kt      # Tests: normalizer, NMS, hasher, retry, AppConfig
                ├── DeduplicationCacheTest.kt # Session-scoped text + hash dedup tests (REQ-M-8)
                ├── AlertClientTest.kt      # AlertClient GPS truncation, timer, subscribe tests
                ├── DeviceTokenManagerTest.kt # Token registration request tests
                ├── NotificationHelperTest.kt # Notification channel and display tests
                ├── LookalikeExpanderTest.kt # Lookalike character expansion tests (REQ-M-12a)
                ├── DetectionFeedUpdateTest.kt # Concurrent StateFlow update tests for detection feed
                ├── ZoomControllerTest.kt  # Safe zoom ratio calculation and best candidate selection tests
                ├── OfflineQueueMigrationTest.kt # Room migration tests for offline queue schema changes
                ├── BrightnessManagerTest.kt # Brightness dim/restore/teardown state tests
                ├── FrameDifferTest.kt     # Frame differ grayscale diff and skip counter tests
                └── MotionStateManagerTest.kt # Motion state manager initial state and resume tests
```

## Architecture

- **Pattern**: MVVM with an application-scoped shared repository
- **UI Framework**: Jetpack Compose with Material 3
- **Minimum SDK**: 28 (Android 9.0)
- **Target SDK**: 35 (Android 15)
- **Language**: Kotlin 2.0+

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | Jetpack Compose | Modern declarative UI, Google's recommended approach |
| Architecture | MVVM + shared repository | Keeps preview UI and background service on the same capture/session state |
| Min SDK | 28 | Covers 95%+ of active devices |
| Build System | Gradle with Kotlin DSL | Type-safe build scripts, version catalogs |
| Dependency Management | Version Catalogs | Centralized dependency versions in `libs.versions.toml` |

## Build & Run

```bash
# Build debug APK
cd android
./gradlew assembleDebug

# Build release AAB (for Play Store)
./gradlew bundleRelease

# Build release APK (for sideloading)
./gradlew assembleRelease

# Install on connected device/emulator
./gradlew installDebug

# Run tests
./gradlew test

# Run lint
./gradlew lint
```

## Release & Distribution

### Signing

Release builds are signed using a keystore configured in `app/build.gradle.kts`. Keystore credentials are read from `local.properties` (gitignored) with the following keys:

```properties
RELEASE_STORE_FILE=../release.keystore
RELEASE_STORE_PASSWORD=...
RELEASE_KEY_ALIAS=iceblox-release
RELEASE_KEY_PASSWORD=...
```

To generate the keystore:

```bash
keytool -genkeypair -v \
  -keystore android/release.keystore \
  -alias iceblox-release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <password> -keypass <password> \
  -dname "CN=IceBlox, O=IceBlox, L=, ST=, C=US"
```

The keystore file (`release.keystore`) is gitignored. Store it and its credentials securely outside of version control.

### R8 / ProGuard

Release builds enable R8 minification and resource shrinking. ProGuard rules for third-party libraries (CameraX, Compose, ONNX Runtime, OkHttp, Room) are maintained in `app/proguard-rules.pro`.

### CI Release

A GitHub Actions workflow (`.github/workflows/release.yml`) automates the release AAB build. It triggers on version tags (`v*`) and `workflow_dispatch`.

**Steps:**
1. Set up JDK 17 (Temurin), Android SDK, and Gradle
2. Decode the release keystore from `RELEASE_KEYSTORE_BASE64` secret
3. Create `.env` (pepper, maps API key) and `local.properties` (signing credentials) from secrets
4. Run unit tests (`make android-unit-test`)
5. Build release AAB (`make android-release-bundle`)
6. Upload the AAB as a build artifact

**Required GitHub Secrets:** `RELEASE_KEYSTORE_BASE64`, `PEPPER`, `ANDROID_MAPS_API_KEY`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD`.

The `make android-release-bundle` target runs `./gradlew bundleRelease` from the `android/` directory.

**`make publish-android`** — Build a signed release AAB and print the path for manual upload to Google Play Console. Depends on `android-release-bundle`.

### Play Store

- **Target SDK**: 35 (current Play Store minimum)
- **Upload format**: Android App Bundle (`.aab`) via `./gradlew bundleRelease` or `make android-release-bundle`
- **App icon**: 512x512 PNG for Play Store listing (separate from adaptive icon)
- **Required listing assets**: feature graphic (1024x500), 2+ phone screenshots, privacy policy URL
- **Content rating**: IARC questionnaire in Play Console
- **Data safety**: camera (on-device only), location (sent to server), hashed plate data (sent to server)

## Build Learnings

| Topic | Detail |
|-------|--------|
| **No local Java runtime** | This dev machine has no system Java. Android builds (`./gradlew assembleDebug`) require a JDK. Android Studio bundles one at `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/`. For CI or CLI builds, install via `brew install openjdk`. |
| **Background capture** | Android background capture runs in a `LifecycleService` foreground service with `foregroundServiceType="camera"`. The activity starts the service in `onUserLeaveHint` (user-initiated backgrounding such as pressing Home) and stops it in `onResume` (when it regains foreground), so CameraX preview can rebind cleanly without competing for the camera. Using `onUserLeaveHint` rather than `onPause` avoids false triggers from system-initiated pauses (configuration changes, notification shade, recent apps), which previously caused crashes during sleep/wake and screen rotation. The service calls `startForeground()` in `onCreate()` to satisfy Android's foreground service timing requirement. Navigation state (`showCamera`, `showReport`, `showMap`, `showSettings`) is preserved across configuration changes via `onSaveInstanceState`/`savedInstanceState`. |
| **DebugLog replaces android.util.Log** | All `Log.d/w/e` calls are replaced with `DebugLog.d/w/e`. This routes logs through both `android.util.Log` (for logcat) and a 50-entry ring buffer (for the in-app panel). Throwable overloads (`d/w/e(tag, msg, throwable)`) append the exception message. |
| **Thread safety for StateFlow** | `DebugLog` uses `@Synchronized` on the buffer mutation and emits via `MutableStateFlow`. `CaptureRepository` uses `MutableStateFlow.update {}` for atomic read-modify-write on the detection feed (prevents lost updates from concurrent add/markSent calls). Compose collects via `collectAsState()` — no main-thread dispatch needed since Compose recomposition handles the thread hop. |
| **Debug gating** | Developer debug mode (triple-tap toggle) is gated behind `BuildConfig.DEBUG` — stripped from release builds by ProGuard/R8. The debug overlay bounding boxes are available in all builds via the user debug mode setting (REQ-M-18). The detection feed, log panel, and FPS header are gated behind developer debug mode (`showFeedAndLogs`). |
| **TFLite output tensor format** | YOLOv8 TFLite outputs `[1, 5, 8400]` for single-class (not `[1, 8400, 5]`). NMS must be implemented manually — unlike Core ML which bakes NMS into the export. |
| **keytool location** | System `keytool` may not be in PATH. Use Android Studio's bundled JDK: `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool`. |
| **Server URL** | `build.gradle.kts` uses a Gradle project property `SERVER_URL` to set the default server URL at build time via `BuildConfig.SERVER_BASE_URL`. Debug builds default to `http://10.0.2.2:8080` (emulator localhost) when no property is provided. Release builds hardcode `https://iceblox.up.railway.app` regardless of the property. Pass `-PSERVER_URL=<url>` to override for debug builds (e.g., `./gradlew assembleDebug -PSERVER_URL=http://localhost:8080` for physical device testing). `AppConfig.kt` reads the value from `BuildConfig` at runtime. This avoids source-file patching during builds. |

## Dependencies

Core dependencies (managed via version catalog in `gradle/libs.versions.toml`):
- `androidx.core:core-ktx` — Kotlin extensions for Android
- `androidx.lifecycle:lifecycle-runtime-ktx` — Lifecycle-aware components
- `androidx.lifecycle:lifecycle-service` — `LifecycleService` for the background capture foreground service
- `androidx.lifecycle:lifecycle-viewmodel-compose` — ViewModel integration with Compose
- `androidx.activity:activity-compose` — Compose integration with Activity
- `androidx.compose.*` — Compose UI toolkit
- `androidx.compose.material3` — Material Design 3
- `androidx.camera:camera-*` (1.4.1) — CameraX: camera2, lifecycle, view
- `org.tensorflow:tensorflow-lite` (2.16.1) — TFLite runtime for YOLOv8-nano inference
- `com.microsoft.onnxruntime:onnxruntime-android` (1.20.0) — ONNX Runtime for CCT-XS OCR inference
- `androidx.room:room-runtime` + `room-ktx` (2.6.1) — SQLite offline queue persistence
- `com.squareup.okhttp3:okhttp` (4.12.0) — HTTP client for server communication
- `com.google.android.gms:play-services-location` (21.3.0) — Fused location provider
- `com.google.firebase:firebase-bom` (33.7.0) — Firebase Bill of Materials
- `com.google.firebase:firebase-messaging` — Firebase Cloud Messaging for push notifications
- `com.google.maps.android:maps-compose` (6.2.1) — Google Maps Compose integration for report location picker

Build plugins:
- KSP (2.1.0-1.0.29) — Kotlin Symbol Processing for Room annotation processing
- Google Services (4.4.2) — Firebase/Google services configuration processing

Testing:
- `junit` — Unit testing
- `org.robolectric:robolectric` — Android unit testing without emulator
- `com.squareup.okhttp3:mockwebserver` — Mock HTTP server for network tests
- `androidx.test.ext:junit` — AndroidX test extensions
- `androidx.compose.ui:ui-test-junit4` — Compose UI testing
