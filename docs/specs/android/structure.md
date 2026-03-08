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
- **Target SDK**: 34 (Android 14)
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

# Install on connected device/emulator
./gradlew installDebug

# Run tests
./gradlew test

# Run lint
./gradlew lint
```

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
