# iOS Debug Overlay Enhancements

## Purpose

Enhance the debug overlay (REQ-M-19) to make E2E testing observable. Currently, bounding boxes only appear for plates that pass the full detect+OCR+normalize pipeline, which means nothing is visible when the ML model detects regions but OCR fails. Additionally, there is no way to see whether detected plates were successfully uploaded to the server.

## Requirements

See [Mobile App Spec — Debug Overlay Enhancements](../mobile-app/spec.md#debug-overlay-enhancements-dbg-1–dbg-4) for the shared DBG-1 through DBG-4 requirements and UI layout. This file covers iOS-specific implementation details only.

## iOS-Specific: DBG-3 Callback

State transitions are driven by a callback from `APIClient` to `FrameProcessor`.

## iOS-Specific: DBG-4 Debug Log Panel

- Panel: `frame(maxHeight: 140)`, `background(.black.opacity(0.75))`, rounded top corners
- Entries: 9pt monospace, `lineLimit(2)`, color-coded by level
  - DEBUG: gray
  - WARNING: yellow
  - ERROR: red
- Each entry formatted as: `HH:mm:ss D/Tag: message`
- Auto-scrolls to show newest entries via `ScrollViewReader` + `onChange(of: entries.count)`
- Backed by a `DebugLog` singleton (`final class DebugLog: ObservableObject`) with a 50-entry ring buffer
- Thread safety: `NSLock` + main thread dispatch for `@Published` updates
- `DebugLog.shared.d/w/e(tag, message)` methods print to console (in DEBUG) and append to ring buffer
- All key pipeline events logged: model load, detection counts, upload results, connectivity changes

#### Files

- `ios/IceBloxApp/Debug/DebugLog.swift` — Singleton with `LogEntry` model, `LogLevel` enum, ring buffer
- `ios/IceBloxApp/Views/DebugLogPanel.swift` — SwiftUI view with `ScrollViewReader` + `LazyVStack`
- `ios/IceBloxApp/Views/DebugOverlayView.swift` — Hosts `DebugLogPanel` in `VStack { Spacer(); panel }` at bottom
- `ios/IceBloxApp/ContentView.swift` — Passes `debugLog.entries` to overlay

#### Build Notes

- New Swift files must be added to `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase) for Xcode to compile them. The `xcodeproj` Ruby gem can automate this; without it, manual pbxproj editing is required — use UUIDs matching the existing format in the project file.

## Implementation Plan

### Step 1: Add raw detections and detection feed to FrameProcessor

**File:** `ios/IceBloxApp/Camera/FrameProcessor.swift`

- Add `RawDetectionBox` struct with boundingBox, confidence, imageWidth, imageHeight
- Add `DetectionState` enum (queued, sent, matched) and `DetectionFeedEntry` struct
- Add `@Published var rawDetections: [RawDetectionBox]` that emits ALL detections before OCR
- Add `@Published var detectionFeed: [DetectionFeedEntry]` (capped at 20)
- Add `onPlateSent(hash:matched:)` method to update feed entry state
- In `processFrame()`, map all raw detector results to RawDetectionBox before OCR filtering

### Step 2: Add upload callback to APIClient

**File:** `ios/IceBloxApp/Networking/APIClient.swift`

Add `var onPlateSent: ((String, Bool) -> Void)?` callback. Call it after each successful 200 response with the plate hash and matched boolean.

### Step 3: Update DebugOverlayView

**File:** `ios/IceBloxApp/Views/DebugOverlayView.swift`

- Accept `rawDetections` and `feedEntries` as new parameters
- Draw yellow bounding boxes for raw detections (with confidence label)
- Draw green bounding boxes for OCR'd plates (existing behavior)
- Render detection feed as a column on the right side with state-colored labels
- Add raw detection count to header

### Step 4: Wire new data through ContentView

**File:** `ios/IceBloxApp/ContentView.swift`

- Set `apiClient.onPlateSent` to call `frameProcessor.onPlateSent` in `setupPipeline()`
- Pass `rawDetections` and `detectionFeed` from FrameProcessor to DebugOverlayView
