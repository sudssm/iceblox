# iOS App Structure

## Overview

The iOS app is built with **SwiftUI** targeting **iOS 17+**, using the standard Xcode project layout. It follows Apple's recommended app architecture with SwiftUI's declarative UI framework. Camera capture is explicitly foreground-only: the app may flush queued hashes and refresh alert subscriptions when backgrounded, but camera capture stops until the app returns to the foreground.

## Project Layout

```
ios/
├── IceBloxApp.xcodeproj/          # Xcode project file
│   └── project.pbxproj
├── IceBloxApp/
│   ├── IceBloxApp.swift           # App entry point (@main), landscape lock, splash→camera flow
│   ├── ContentView.swift          # Root view, wires all managers, session lifecycle, stop control, session summary card
│   ├── SplashScreenView.swift     # Splash screen with app name and Start Camera button
│   ├── Assets.xcassets/           # Asset catalog (icons, colors)
│   │   ├── AppIcon.appiconset/    # 1024×1024 app icon
│   │   ├── AccentColor.colorset/
│   │   └── Contents.json
│   ├── PrivacyInfo.xcprivacy      # App privacy manifest (required by Apple)
│   ├── Views/
│   │   ├── StatusBarView.swift        # Top status bar (connectivity, GPS warning, nearby sightings, last detected)
│   │   ├── DebugOverlayView.swift     # Bounding boxes, plate text, hash, FPS (debug builds)
│   │   ├── DebugLogPanel.swift        # Translucent log panel at bottom of debug overlay
│   │   ├── MapView.swift              # Map view showing nearby sightings and reports with offline caching
│   │   ├── ReportICEView.swift        # ICE vehicle report form (photo, description, plate, map, submit)
│   │   ├── CameraPickerView.swift     # UIViewControllerRepresentable wrapping UIImagePickerController
│   │   └── SettingsView.swift         # Settings screen with push notification + debug mode toggles
│   ├── Camera/
│   │   ├── CameraManager.swift        # AVCaptureSession setup, frame delegate, thermal mgmt
│   │   ├── CameraPreviewView.swift    # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   │   ├── FrameProcessor.swift       # Orchestrates detect → OCR → normalize → dedup → hash → queue → zoom retry on failed OCR
│   │   ├── PreviewFreezer.swift       # Frozen-frame overlay for zoom retry UX (UIImageView over preview layer)
│   │   ├── SimulatorCamera.swift      # Timer-driven frame generator for simulator testing (simulator-only)
│   │   └── ZoomController.swift       # Optical zoom detection, eligibility check, zoom-capture-restore
│   ├── Detection/
│   │   ├── PlateDetector.swift        # Core ML inference, bounding box extraction
│   │   └── PlateOCR.swift             # ONNX Runtime CCT-XS inference + fixed-slot decode on cropped regions
│   ├── Processing/
│   │   ├── PlateNormalizer.swift      # Uppercase, strip, validate length
│   │   ├── PlateHasher.swift          # HMAC-SHA256 via CryptoKit, pepper from generated Pepper.swift
│   │   ├── DeduplicationCache.swift   # Time-windowed set of recently seen plates
│   │   └── LookalikeExpander.swift   # BFS expansion of confusable characters (REQ-M-12a)
│   ├── Networking/
│   │   ├── APIClient.swift            # URLSession POST to server, batch construction
│   │   ├── AlertClient.swift          # Subscribe endpoint client, 10-min timer, GPS truncation
│   │   ├── MapClient.swift            # GET /api/v1/map-sightings client for map view
│   │   ├── ReportClient.swift         # Multipart form-data POST to /api/v1/reports (ICE vehicle reports)
│   │   ├── RetryManager.swift         # Exponential backoff, 429 handling
│   │   └── ConnectivityMonitor.swift  # NWPathMonitor wrapper, triggers queue flush
│   ├── Persistence/
│   │   ├── OfflineQueue.swift         # SQLite-backed FIFO queue (hash, timestamp, lat, lng)
│   │   └── OfflineQueueEntry.swift    # Data model for queue entries
│   ├── Location/
│   │   └── LocationManager.swift      # CLLocationManager, permission handling, GPS warning
│   ├── Config/
│   │   ├── AppConfig.swift            # Confidence thresholds, batch size, dedup window, server URL (compile-time flag), zoom retry constants
│   │   └── Pepper.swift               # Generated at build time from root .env (gitignored)
│   ├── Settings/
│   │   └── UserSettings.swift         # ObservableObject singleton: push notification + user debug mode toggles persisted via UserDefaults
│   ├── Debug/
│   │   └── DebugLog.swift             # Singleton logger: ring buffer + @Published entries for UI
│   └── Models/
│       ├── plate_detector.mlpackage   # YOLOv8-nano Core ML model (bundled at build time)
│       └── plate_ocr.onnx            # CCT-XS ONNX OCR model (bundled at build time)
└── IceBloxAppTests/
    ├── IceBloxAppTests.swift          # Unit tests
    ├── AlertClientTests.swift         # AlertClient GPS truncation, request/response tests
    ├── PushNotificationTests.swift    # Device token hex conversion, AppConfig endpoint tests
    ├── LookalikeExpanderTests.swift   # Lookalike character expansion tests (REQ-M-12a)
    ├── ZoomControllerTests.swift      # Zoom eligibility, safe zoom ratio, best candidate selection tests
    └── OfflineQueueTests.swift        # Schema validation and migration tests for offline queue
```

## Architecture

- **Pattern**: MVVM (Model-View-ViewModel)
- **UI Framework**: SwiftUI
- **Minimum Target**: iOS 17.0
- **Language**: Swift 5.9+
- **Orientation**: All orientations supported (auto-rotation)

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI | Declarative, modern, first-class Apple support |
| Architecture | MVVM | Natural fit with SwiftUI's data binding |
| Min iOS Version | 17.0 | Access to latest APIs, reasonable device coverage |
| Dependency Management | Swift Package Manager | Built into Xcode, no third-party tooling needed |
| Offline Queue | Raw SQLite | Lightweight, no Core Data overhead for simple schema |
| Detection Model | Core ML `.mlpackage` (YOLOv8-nano) | Platform-native, NMS baked into export |
| OCR | ONNX Runtime (CCT-XS `.onnx` + fixed-slot decode) | Specialized plate model, on-device, no network required |
| Background camera behavior | Foreground-only | Standard iOS apps cannot keep this camera pipeline running after backgrounding |

## Build & Run

```bash
# Open in Xcode
open ios/IceBloxApp.xcodeproj

# Build from command line
xcodebuild -project ios/IceBloxApp.xcodeproj \
  -scheme IceBloxApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Run tests
xcodebuild -project ios/IceBloxApp.xcodeproj \
  -scheme IceBloxApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

## App Store Distribution

Prerequisites for App Store submission:

1. **Apple Developer Account** — $99/year membership required
2. **Development Team** — Set `DEVELOPMENT_TEAM` in build settings to your Apple Team ID
3. **App Icon** — 1024×1024 PNG in `AppIcon.appiconset`
4. **Privacy Manifest** — `PrivacyInfo.xcprivacy` declaring camera + location usage
5. **App Store Connect** — Create listing with screenshots, description, privacy policy URL
6. **TestFlight** — Upload archive for beta testing before submission
7. **ML Model** — Bundle `plate_detector.mlmodel` (not committed to repo; see model training docs)

### Makefile Targets

The root `Makefile` provides two targets for App Store distribution:

**`make package-ios`** — Archive and export a release `.ipa` for App Store upload.

- Requires `APPLE_TEAM_ID` (set in `.env` or as an env var)
- Generates an `ExportOptions.plist` with `app-store-connect` method and automatic signing
- Passes `OTHER_SWIFT_FLAGS="-DPRODUCTION_SERVER"` to bake in the production server URL at compile time
- After archiving, patches embedded framework `Info.plist` `MinimumOSVersion` values to match the app's (fixes Apple error 90208)
- Runs `xcodebuild archive`, patches frameworks, then `xcodebuild -exportArchive`
- Output: `ios/build/export/IceBloxApp.ipa`

**`make publish-ios`** — Upload the `.ipa` to App Store Connect via `xcrun altool`.

- Requires `APP_STORE_KEY_ID`, `APP_STORE_ISSUER_ID`, and `APP_STORE_KEY_P8` (set in `.env` or as env vars)
- Writes the `.p8` key to `~/.appstoreconnect/private_keys/` for `altool` authentication
- Requires a prior `make package-ios` run (checks for the `.ipa` file)

All credentials are read from the root `.env` file or environment variables — none are committed to the repository.

## Build Learnings

| Topic | Detail |
|-------|--------|
| **Adding new files** | New `.swift` files must be added to `project.pbxproj` in four places: PBXBuildFile, PBXFileReference, PBXGroup (for directory membership), and PBXSourcesBuildPhase. Without this, Xcode compiles but cannot find the new types. The `xcodeproj` Ruby gem can automate this; otherwise manual editing with UUIDs matching the project's existing format is required. |
| **Simulator camera** | iOS Simulator has no rear camera — `AVCaptureSession` errors with code `-12782`. `SimulatorCamera.swift` provides a timer-driven frame generator (gated by `#if targetEnvironment(simulator)`) that feeds a bundled or placeholder image through the pipeline at ~10 FPS. For runtime E2E injection, the app can start on the splash screen, transition into camera mode, then pick up files copied into `Library/Application Support/test_images/` inside the app container while it is already running. Optional same-basename `.txt` sidecars (for example `target.jpg` + `target.txt`) can inject a deterministic plate string through the post-detection pipeline for simulator-only E2E. A second E2E-only trigger file can stop the active session, and the app writes a plain-text session summary artifact back into `Application Support/` so the shell harness can validate stop-summary behavior without XCUITest. |
| **Thread safety for @Published** | `@Published` properties must be updated on the main thread. Use `NSLock` for thread-safe buffer mutation, then dispatch to main for the `@Published` assignment. Check `Thread.isMainThread` to avoid redundant dispatches. |
| **Debug gating** | Use `#if DEBUG` to gate developer-only debug code (logging to console, triple-tap debug toggle). The debug overlay bounding boxes are available in all builds via the user debug mode setting (REQ-M-18). The detection feed, log panel, and FPS header are gated behind developer debug mode. |
| **Server URL** | `AppConfig.swift` uses a compile-time `PRODUCTION_SERVER` flag to select the default server URL. When built with `-DPRODUCTION_SERVER` (as `make package-ios` does), the default is the Railway production URL. Otherwise, the default is `http://localhost:8080`. Environment variables `E2E_SERVER_BASE_URL` and `SERVER_BASE_URL` can override the default at runtime. This avoids source-file patching during builds. |

## Dependencies

Apple frameworks:
- SwiftUI, UIKit (UI)
- AVFoundation (camera capture)
- CoreML, Vision (plate detection)
- CryptoKit (HMAC-SHA256)
- CoreLocation (GPS)
- Network (NWPathMonitor)
- SQLite3 (offline queue)

External:
- `onnxruntime-swift-package-manager` (1.20.0) — ONNX Runtime for CCT-XS OCR inference
