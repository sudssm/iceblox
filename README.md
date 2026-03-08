# Cameras

A privacy-focused license plate detection system for private security and community watch. A dashboard-mounted mobile app continuously scans for license plates, OCRs them on-device, and sends hashed plate identifiers to a server for comparison against a target list.

The system is designed so that neither party learns what it shouldn't: the app never sees the target plates, and the server never sees non-target plates in plaintext.

## How It Works

1. The mobile app captures camera frames and detects license plates on-device
2. Plate text is normalized and hashed (HMAC-SHA256) with a shared secret
3. Only the hash is sent to the server (or queued locally if offline)
4. The server compares the hash against pre-computed target hashes
5. Non-matching hashes are discarded from memory and never persisted

## Project Structure

```
├── android/          # Android app (Kotlin, Jetpack Compose)
├── ios/              # iOS app (Swift, SwiftUI)
└── docs/             # Specifications and documentation
    ├── development-philosophy.md
    └── specs/
        ├── overview.md           # System architecture and privacy model
        ├── android/structure.md  # Android project layout and build commands
        ├── ios/structure.md      # iOS project layout and build commands
        ├── server/spec.md        # Server API spec
        └── mobile-app/           # Mobile app feature specs
```

## Tech Stack

| | Android | iOS |
|---|---|---|
| Language | Kotlin 2.1 | Swift 5.9+ |
| UI | Jetpack Compose, Material 3 | SwiftUI |
| Architecture | MVVM | MVVM |
| Min Version | API 28 (Android 9.0) | iOS 17.0 |
| Build System | Gradle (Kotlin DSL) | Xcode / Swift Package Manager |

## Quick Start

### iOS

**Prerequisites:** Xcode 15+ with iOS 18 SDK

```bash
# Open in Xcode
open ios/CamerasApp.xcodeproj

# Or build and run from the command line
xcodebuild -project ios/CamerasApp.xcodeproj \
  -scheme CamerasApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build

# Install and launch on simulator
xcrun simctl boot "iPhone 16 Pro"
xcrun simctl install "iPhone 16 Pro" \
  Build/Products/Debug-iphonesimulator/CamerasApp.app
xcrun simctl launch "iPhone 16 Pro" com.cameras.app

# Run tests
xcodebuild -project ios/CamerasApp.xcodeproj \
  -scheme CamerasApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

### Android

**Prerequisites:** Android Studio or Android SDK with API 28+, JDK 11+

```bash
cd android

# Build debug APK
./gradlew assembleDebug

# Install on connected device/emulator
./gradlew installDebug

# Run tests
./gradlew test

# Run lint
./gradlew lint
```

## Documentation

See [`docs/`](docs/) for full specifications and architecture details:

- [System Overview](docs/specs/overview.md) — architecture, privacy model, data flow
- [Android Structure](docs/specs/android/structure.md) — project layout, dependencies, build commands
- [iOS Structure](docs/specs/ios/structure.md) — project layout, dependencies, build commands
- [Development Philosophy](docs/development-philosophy.md) — Spec-Driven Development methodology
