# iOS Debug Overlay Enhancements

## Purpose

Enhance the debug overlay (REQ-M-19) to make E2E testing observable. Currently, bounding boxes only appear for plates that pass the full detect+OCR+normalize pipeline, which means nothing is visible when the ML model detects regions but OCR fails. Additionally, there is no way to see whether detected plates were successfully uploaded to the server.

## Requirements

### DBG-1: Raw Detection Bounding Boxes

The debug overlay MUST draw bounding boxes for ALL raw detections from the PlateDetector, not just plates that pass OCR and normalization. This ensures the overlay is useful even when the model detects plate-like regions but OCR cannot read them (e.g., too small, blurry, wrong class).

- Raw detection boxes: yellow, with confidence percentage label
- Successfully OCR'd plate boxes: green, with plate text and truncated hash (existing behavior)

### DBG-2: Detection Feed

The debug overlay MUST display a scrollable feed on the right side of the screen showing recently detected plates and their upload state.

Each feed entry shows:
- Plate text (normalized)
- Truncated hash (first 8 characters)
- Upload state: `QUEUED`, `SENT`, or `MATCHED`

State colors:
- `QUEUED`: white text
- `SENT`: green text
- `MATCHED`: bright green/bold text

The feed retains the most recent 20 entries and auto-scrolls to show newest entries at top.

### DBG-3: Upload State Tracking

The app MUST track each detected plate through the upload lifecycle:
1. When a plate is detected and queued for upload: state = `QUEUED`
2. When the server responds with `matched: false`: state = `SENT`
3. When the server responds with `matched: true`: state = `MATCHED`

State transitions are driven by a callback from `APIClient` to `FrameProcessor`.

## UI Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  FPS: 28  │  Queue: 3  │  ● Online                              │
│                                                                  │
│        ┌─────────────┐                       ┌────────────────┐  │
│        │  ABC 1234   │  ← plate text         │ AB12345 [SENT] │  │
│        │ ┌─────────┐ │                       │ XY98765 [SENT] │  │
│        │ │ (plate) │ │  ← green box          │ TEST123 [QUED] │  │
│        │ └─────────┘ │                       │                │  │
│        │  a3f8b2c1   │  ← hash               │                │  │
│        └─────────────┘                       └────────────────┘  │
│                                                                  │
│     ┌───────────┐  ← yellow box (raw detection, no OCR)         │
│     │  0.82     │                                                │
│     └───────────┘                                                │
│                                                                  │
│  [DEBUG MODE]                                                    │
└──────────────────────────────────────────────────────────────────┘
```

### DBG-4: Debug Log Panel

The debug overlay MUST display a translucent log panel at the bottom of the screen showing recent device logs when debug mode is active.

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

- `ios/CamerasApp/Debug/DebugLog.swift` — Singleton with `LogEntry` model, `LogLevel` enum, ring buffer
- `ios/CamerasApp/Views/DebugLogPanel.swift` — SwiftUI view with `ScrollViewReader` + `LazyVStack`
- `ios/CamerasApp/Views/DebugOverlayView.swift` — Hosts `DebugLogPanel` in `VStack { Spacer(); panel }` at bottom
- `ios/CamerasApp/ContentView.swift` — Passes `debugLog.entries` to overlay

#### Build Notes

- New Swift files must be added to `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase) for Xcode to compile them. The `xcodeproj` Ruby gem can automate this; without it, manual pbxproj editing is required — use UUIDs matching the existing format in the project file.

## Implementation Plan

### Step 1: Add raw detections and detection feed to FrameProcessor

**File:** `ios/CamerasApp/Camera/FrameProcessor.swift`

- Add `RawDetectionBox` struct with boundingBox, confidence, imageWidth, imageHeight
- Add `DetectionState` enum (queued, sent, matched) and `DetectionFeedEntry` struct
- Add `@Published var rawDetections: [RawDetectionBox]` that emits ALL detections before OCR
- Add `@Published var detectionFeed: [DetectionFeedEntry]` (capped at 20)
- Add `onPlateSent(hash:matched:)` method to update feed entry state
- In `processFrame()`, map all raw detector results to RawDetectionBox before OCR filtering

### Step 2: Add upload callback to APIClient

**File:** `ios/CamerasApp/Networking/APIClient.swift`

Add `var onPlateSent: ((String, Bool) -> Void)?` callback. Call it after each successful 200 response with the plate hash and matched boolean.

### Step 3: Update DebugOverlayView

**File:** `ios/CamerasApp/Views/DebugOverlayView.swift`

- Accept `rawDetections` and `feedEntries` as new parameters
- Draw yellow bounding boxes for raw detections (with confidence label)
- Draw green bounding boxes for OCR'd plates (existing behavior)
- Render detection feed as a column on the right side with state-colored labels
- Add raw detection count to header

### Step 4: Wire new data through ContentView

**File:** `ios/CamerasApp/ContentView.swift`

- Set `apiClient.onPlateSent` to call `frameProcessor.onPlateSent` in `setupPipeline()`
- Pass `rawDetections` and `detectionFeed` from FrameProcessor to DebugOverlayView
