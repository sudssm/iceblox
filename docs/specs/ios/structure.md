# iOS App Structure

## Overview

The iOS app is built with **SwiftUI** targeting **iOS 17+**, using the standard Xcode project layout. It follows Apple's recommended app architecture with SwiftUI's declarative UI framework.

## Project Layout

```
ios/
├── CamerasApp.xcodeproj/          # Xcode project file
│   └── project.pbxproj
├── CamerasApp/
│   ├── CamerasApp.swift           # App entry point (@main), landscape lock
│   ├── ContentView.swift          # Root view, wires all managers
│   ├── Assets.xcassets/           # Asset catalog (icons, colors)
│   │   ├── AppIcon.appiconset/    # 1024×1024 app icon
│   │   ├── AccentColor.colorset/
│   │   └── Contents.json
│   ├── PrivacyInfo.xcprivacy      # App privacy manifest (required by Apple)
│   ├── Views/
│   │   ├── CameraPreviewView.swift    # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   │   ├── StatusBarView.swift        # Bottom status bar (connectivity, last detected, counts)
│   │   └── DebugOverlayView.swift     # Bounding boxes, plate text, hash, FPS (debug builds)
│   ├── Camera/
│   │   ├── CameraManager.swift        # AVCaptureSession setup, frame delegate, thermal mgmt
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
│   └── Models/
│       └── plate_detector.mlmodel     # YOLOv8-nano Core ML model (bundled at build time)
└── CamerasAppTests/
    └── CamerasAppTests.swift          # Unit tests
```

## Architecture

- **Pattern**: MVVM (Model-View-ViewModel)
- **UI Framework**: SwiftUI
- **Minimum Target**: iOS 17.0
- **Language**: Swift 5.9+
- **Orientation**: Landscape only (dashboard-mounted)

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI | Declarative, modern, first-class Apple support |
| Architecture | MVVM | Natural fit with SwiftUI's data binding |
| Min iOS Version | 17.0 | Access to latest APIs, reasonable device coverage |
| Dependency Management | Swift Package Manager | Built into Xcode, no third-party tooling needed |
| Offline Queue | Raw SQLite | Lightweight, no Core Data overhead for simple schema |
| Detection Model | Core ML (YOLOv8-nano) | Platform-native, NMS baked into export |
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

## Dependencies

None (stdlib + Apple frameworks only):
- SwiftUI, UIKit (UI)
- AVFoundation (camera capture)
- CoreML, Vision (detection + OCR)
- CryptoKit (HMAC-SHA256)
- CoreLocation (GPS)
- Network (NWPathMonitor)
- SQLite3 (offline queue)
