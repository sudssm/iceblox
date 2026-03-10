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
        │   │   │   ├── CameraCaptureBinder.kt # Shared CameraX bind/unbind helper for UI + service
        │   │   │   ├── CameraPreview.kt    # Compose CameraX preview wrapper
        │   │   │   ├── FrameAnalyzer.kt    # ImageAnalysis.Analyzer → detect → OCR → normalize → zoom retry on failed OCR
        │   │   │   ├── PreviewFreezer.kt   # Frozen-frame overlay state for zoom retry UX
        │   │   │   ├── TestFrameFeeder.kt  # Test mode: loads images, feeds them through analyzeBitmap() on a timer
        │   │   │   └── ZoomController.kt   # Optical zoom detection, safe zoom ratio calculation, zoom-capture-restore
        │   │   ├── config/
        │   │   │   └── AppConfig.kt        # Confidence thresholds, batch sizes, server URL, notification config, zoom retry constants
        │   │   ├── detection/
        │   │   │   ├── PlateDetector.kt    # TFLite interpreter, YOLOv8-nano inference, NMS
        │   │   │   └── PlateOCR.kt         # ONNX Runtime CCT-XS inference + fixed-slot decode on cropped bitmaps
        │   │   ├── location/
        │   │   │   └── LocationProvider.kt # FusedLocationProviderClient, permission handling
        │   │   ├── network/
        │   │   │   ├── AlertClient.kt      # Subscribe endpoint client, coroutine timer, GPS truncation
        │   │   │   ├── ApiClient.kt        # OkHttp POST /api/v1/plates + /api/v1/devices, batch, 429 handling
        │   │   │   ├── ConnectivityMonitor.kt # ConnectivityManager.NetworkCallback
        │   │   │   ├── DeviceTokenManager.kt # FCM token registration with retry
        │   │   │   ├── ReportClient.kt     # OkHttp multipart POST to /api/v1/reports (ICE vehicle reports)
        │   │   │   └── RetryManager.kt     # Exponential backoff, rate limit tracking
        │   │   ├── notification/
        │   │   │   ├── NotificationHelper.kt # Notification channel creation, alert display
        │   │   │   └── PushNotificationService.kt # FirebaseMessagingService: onNewToken, onMessageReceived
        │   │   ├── persistence/
        │   │   │   ├── OfflineQueueDao.kt  # Room DAO: insert, dequeue, delete, count
        │   │   │   ├── OfflineQueueDatabase.kt # Room database singleton
        │   │   │   └── OfflineQueueEntry.kt # Room entity: hash, timestamp, lat, lng, session_id
        │   │   ├── processing/
        │   │   │   ├── DeduplicationCache.kt # 60-second time-windowed set
        │   │   │   ├── LookalikeExpander.kt # BFS expansion of confusable characters (REQ-M-12a)
        │   │   │   ├── PlateHasher.kt      # HMAC-SHA256 via javax.crypto.Mac, pepper from BuildConfig
        │   │   │   └── PlateNormalizer.kt  # Uppercase, strip, validate 2-8 chars
        │   │   ├── settings/
        │   │   │   └── UserSettings.kt       # SharedPreferences-backed push notification toggle
        │   │   ├── service/
        │   │   │   └── BackgroundCaptureService.kt # Foreground service that keeps analysis running when app backgrounds
        │   │   ├── debug/
        │   │   │   └── DebugLog.kt           # Singleton logger: ring buffer + StateFlow for UI
        │   │   └── ui/
        │   │       ├── CameraScreen.kt     # Compose: camera preview + status bar + stop control + session summary (includes StatusBar, TestImagePreview, SessionSummaryOverlay composables)
        │   │       ├── SplashScreen.kt     # Splash screen with app name and Start Camera button
        │   │       ├── ReportICEScreen.kt  # ICE vehicle report form (photo capture, description, plate, Google Map, submit)
        │   │       ├── SettingsScreen.kt  # Settings screen with push notification toggle
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
                ├── ExampleUnitTest.kt      # Tests: normalizer, NMS, hasher, dedup, retry, AppConfig
                ├── AlertClientTest.kt      # AlertClient GPS truncation, timer, subscribe tests
                ├── DeviceTokenManagerTest.kt # Token registration request tests
                ├── NotificationHelperTest.kt # Notification channel and display tests
                ├── LookalikeExpanderTest.kt # Lookalike character expansion tests (REQ-M-12a)
                ├── DetectionFeedUpdateTest.kt # Concurrent StateFlow update tests for detection feed
                └── ZoomControllerTest.kt  # Safe zoom ratio calculation and best candidate selection tests
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

### Play Store

- **Target SDK**: 35 (current Play Store minimum)
- **Upload format**: Android App Bundle (`.aab`) via `./gradlew bundleRelease`
- **App icon**: 512x512 PNG for Play Store listing (separate from adaptive icon)
- **Required listing assets**: feature graphic (1024x500), 2+ phone screenshots, privacy policy URL
- **Content rating**: IARC questionnaire in Play Console
- **Data safety**: camera (on-device only), location (sent to server), hashed plate data (sent to server)

## Build Learnings

| Topic | Detail |
|-------|--------|
| **No local Java runtime** | This dev machine has no system Java. Android builds (`./gradlew assembleDebug`) require a JDK. Android Studio bundles one at `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/`. For CI or CLI builds, install via `brew install openjdk`. |
| **Background capture** | Android background capture runs in a `LifecycleService` foreground service with `foregroundServiceType="camera"`. The activity stops that service on foreground so CameraX preview can rebind cleanly without competing for the camera. |
| **DebugLog replaces android.util.Log** | All `Log.d/w/e` calls are replaced with `DebugLog.d/w/e`. This routes logs through both `android.util.Log` (for logcat) and a 50-entry ring buffer (for the in-app panel). Throwable overloads (`d/w/e(tag, msg, throwable)`) append the exception message. |
| **Thread safety for StateFlow** | `DebugLog` uses `@Synchronized` on the buffer mutation and emits via `MutableStateFlow`. `CaptureRepository` uses `MutableStateFlow.update {}` for atomic read-modify-write on the detection feed (prevents lost updates from concurrent add/markSent calls). Compose collects via `collectAsState()` — no main-thread dispatch needed since Compose recomposition handles the thread hop. |
| **Debug gating** | Debug overlay is gated behind `BuildConfig.DEBUG` — stripped from release builds by ProGuard/R8. |
| **TFLite output tensor format** | YOLOv8 TFLite outputs `[1, 5, 8400]` for single-class (not `[1, 8400, 5]`). NMS must be implemented manually — unlike Core ML which bakes NMS into the export. |
| **keytool location** | System `keytool` may not be in PATH. Use Android Studio's bundled JDK: `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool`. |

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
