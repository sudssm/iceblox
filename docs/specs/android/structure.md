# Android App Structure

## Overview

The Android app is built with **Kotlin** and **Jetpack Compose** targeting **API 28+ (Android 9.0+)**, using the standard Gradle project layout with version catalogs.

## Project Layout

```
android/
├── build.gradle.kts               # Root build file
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
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── java/com/cameras/app/
        │   │   ├── MainActivity.kt         # Activity entry point
        │   │   ├── CamerasApp.kt           # Application class
        │   │   ├── ui/
        │   │   │   └── theme/
        │   │   │       ├── Theme.kt        # Material 3 theme
        │   │   │       ├── Color.kt        # Color definitions
        │   │   │       └── Type.kt         # Typography
        │   │   ├── views/                  # Composable screens
        │   │   ├── models/                 # Data models
        │   │   ├── viewmodels/             # ViewModels
        │   │   ├── services/               # API clients, camera services
        │   │   └── utils/                  # Extensions, helpers
        │   └── res/
        │       ├── values/
        │       │   ├── strings.xml
        │       │   ├── colors.xml
        │       │   └── themes.xml
        │       └── drawable/
        └── test/
            └── java/com/cameras/app/
                └── ExampleUnitTest.kt
```

## Architecture

- **Pattern**: MVVM (Model-View-ViewModel)
- **UI Framework**: Jetpack Compose with Material 3
- **Minimum SDK**: 28 (Android 9.0)
- **Target SDK**: 35 (Android 15)
- **Language**: Kotlin 2.0+

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | Jetpack Compose | Modern declarative UI, Google's recommended approach |
| Architecture | MVVM | Works well with Compose state and ViewModels |
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
RELEASE_KEY_ALIAS=cameras-release
RELEASE_KEY_PASSWORD=...
```

To generate the keystore:

```bash
keytool -genkeypair -v \
  -keystore android/release.keystore \
  -alias cameras-release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <password> -keypass <password> \
  -dname "CN=CamerasApp, O=Cameras, L=, ST=, C=US"
```

The keystore file (`release.keystore`) is gitignored. Store it and its credentials securely outside of version control.

### R8 / ProGuard

Release builds enable R8 minification and resource shrinking. ProGuard rules for third-party libraries (CameraX, Compose, ML Kit, OkHttp, Room) are maintained in `app/proguard-rules.pro`.

### Play Store

- **Target SDK**: 35 (current Play Store minimum)
- **Upload format**: Android App Bundle (`.aab`) via `./gradlew bundleRelease`
- **App icon**: 512x512 PNG for Play Store listing (separate from adaptive icon)
- **Required listing assets**: feature graphic (1024x500), 2+ phone screenshots, privacy policy URL
- **Content rating**: IARC questionnaire in Play Console
- **Data safety**: camera (on-device only), location (sent to server), hashed plate data (sent to server)

## Dependencies

Core dependencies (managed via version catalog):
- `androidx.core:core-ktx` — Kotlin extensions for Android
- `androidx.lifecycle:lifecycle-runtime-ktx` — Lifecycle-aware components
- `androidx.activity:activity-compose` — Compose integration with Activity
- `androidx.compose.*` — Compose UI toolkit
- `androidx.compose.material3` — Material Design 3

Testing:
- `junit` — Unit testing
- `androidx.test.ext:junit` — AndroidX test extensions
- `androidx.compose.ui:ui-test-junit4` — Compose UI testing
