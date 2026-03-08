# iOS App Structure

## Overview

The iOS app is built with **SwiftUI** targeting **iOS 17+**, using the standard Xcode project layout. It follows Apple's recommended app architecture with SwiftUI's declarative UI framework.

## Project Layout

```
ios/
├── CamerasApp.xcodeproj/          # Xcode project file
│   └── project.pbxproj
├── CamerasApp/
│   ├── CamerasApp.swift           # App entry point (@main)
│   ├── ContentView.swift          # Root view
│   ├── Assets.xcassets/           # Asset catalog (icons, colors, images)
│   │   ├── Contents.json
│   │   └── AccentColor.colorset/
│   ├── Views/                     # SwiftUI views
│   ├── Models/                    # Data models
│   ├── ViewModels/                # View models (MVVM)
│   ├── Services/                  # API clients, camera services
│   └── Utilities/                 # Extensions, helpers
└── CamerasAppTests/               # Unit tests
    └── CamerasAppTests.swift
```

## Architecture

- **Pattern**: MVVM (Model-View-ViewModel)
- **UI Framework**: SwiftUI
- **Minimum Target**: iOS 17.0
- **Language**: Swift 5.9+

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI | Declarative, modern, first-class Apple support |
| Architecture | MVVM | Natural fit with SwiftUI's data binding |
| Min iOS Version | 17.0 | Access to latest APIs, reasonable device coverage |
| Dependency Management | Swift Package Manager | Built into Xcode, no third-party tooling needed |

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

## Dependencies

None currently. Future dependencies will be managed via Swift Package Manager and declared in the Xcode project.
