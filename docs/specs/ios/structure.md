# iOS App Structure

## Overview

The iOS app is built with **SwiftUI** targeting **iOS 17+**, using the standard Xcode project layout. It follows Apple's recommended app architecture with SwiftUI's declarative UI framework.

## Project Layout

```
ios/
├── CamerasApp.xcodeproj/          # Xcode project file
│   └── project.pbxproj
├── CamerasApp/
│   ├── CamerasApp.swift           # App entry point (@main), landscape lock, splash→camera flow
│   ├── ContentView.swift          # Root view, wires all managers
│   ├── SplashScreenView.swift     # Splash screen with app name and Start Camera button
│   ├── Assets.xcassets/           # Asset catalog (icons, colors)
│   │   ├── AppIcon.appiconset/    # 1024×1024 app icon
│   │   ├── AccentColor.colorset/
│   │   └── Contents.json
│   ├── PrivacyInfo.xcprivacy      # App privacy manifest (required by Apple)
│   ├── Views/
│   │   ├── StatusBarView.swift        # Bottom status bar (connectivity, last detected, counts)
│   │   ├── DebugOverlayView.swift     # Bounding boxes, plate text, hash, FPS (debug builds)
│   │   └── DebugLogPanel.swift        # Translucent log panel at bottom of debug overlay
│   ├── Camera/
│   │   ├── CameraManager.swift        # AVCaptureSession setup, frame delegate, thermal mgmt
│   │   ├── CameraPreviewView.swift    # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   │   └── FrameProcessor.swift       # Orchestrates detect → OCR → normalize → dedup → hash → queue
│   ├── Detection/
│   │   ├── PlateDetector.swift        # Core ML inference, bounding box extraction
│   │   └── PlateOCR.swift             # Vision VNRecognizeTextRequest on cropped regions
│   ├── Processing/
│   │   ├── PlateNormalizer.swift      # Uppercase, strip, validate length
│   │   ├── PlateHasher.swift          # HMAC-SHA256 via CryptoKit, pepper obfuscation
│   │   └── DeduplicationCache.swift   # Time-windowed set of recently seen plates
│   ├── Networking/
│   │   ├── APIClient.swift            # URLSession POST to server, batch construction
│   │   ├── RetryManager.swift         # Exponential backoff, 429 handling
│   │   └── ConnectivityMonitor.swift  # NWPathMonitor wrapper, triggers queue flush
│   ├── Persistence/
│   │   ├── OfflineQueue.swift         # SQLite-backed FIFO queue (hash, timestamp, lat, lng)
│   │   └── OfflineQueueEntry.swift    # Data model for queue entries
│   ├── Location/
│   │   └── LocationManager.swift      # CLLocationManager, permission handling, GPS warning
│   ├── Config/
│   │   └── AppConfig.swift            # Confidence thresholds, batch size, dedup window, server URL
│   ├── Debug/
│   │   └── DebugLog.swift             # Singleton logger: ring buffer + @Published entries for UI
│   └── Models/
│       └── plate_detector.mlpackage   # YOLOv8-nano Core ML model (bundled at build time)
└── CamerasAppTests/
    └── CamerasAppTests.swift          # Unit tests
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
| OCR | Vision framework | On-device, no network required |

## Build & Run

```bash
# Open in Xcode
open ios/CamerasApp.xcodeproj

# Build from command line
xcodebuild -project ios/CamerasApp.xcodeproj \
  -scheme CamerasApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Run tests
xcodebuild -project ios/CamerasApp.xcodeproj \
  -scheme CamerasApp \
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

## Build Learnings

| Topic | Detail |
|-------|--------|
| **Adding new files** | New `.swift` files must be added to `project.pbxproj` in four places: PBXBuildFile, PBXFileReference, PBXGroup (for directory membership), and PBXSourcesBuildPhase. Without this, Xcode compiles but cannot find the new types. The `xcodeproj` Ruby gem can automate this; otherwise manual editing with UUIDs matching the project's existing format is required. |
| **Simulator camera** | iOS Simulator has no rear camera — `AVCaptureSession` errors with code `-12782`. Use a physical device for camera testing. Grant camera permission automatically with `xcrun simctl privacy <device> grant camera com.cameras.app`. |
| **Thread safety for @Published** | `@Published` properties must be updated on the main thread. Use `NSLock` for thread-safe buffer mutation, then dispatch to main for the `@Published` assignment. Check `Thread.isMainThread` to avoid redundant dispatches. |
| **Debug gating** | Use `#if DEBUG` to gate debug-only code (logging to console, debug UI). This strips debug code from release builds at compile time. |
| **Server URL** | `AppConfig.swift` hardcodes `http://localhost:8080`. Works on Simulator (shared network namespace) but physical devices need the host machine's LAN IP. |

## Dependencies

None (stdlib + Apple frameworks only):
- SwiftUI, UIKit (UI)
- AVFoundation (camera capture)
- CoreML, Vision (detection + OCR)
- CryptoKit (HMAC-SHA256)
- CoreLocation (GPS)
- Network (NWPathMonitor)
- SQLite3 (offline queue)
