# Android Debug Overlay Enhancements

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
- `MATCHED`: gold text (distinct from SENT green for visual clarity)

The feed retains the most recent 20 entries and auto-scrolls to show newest entries at top.

### DBG-3: Upload State Tracking

The app MUST track each detected plate through the upload lifecycle:
1. When a plate is detected and queued for upload: state = `QUEUED`
2. When the server responds with `matched: false`: state = `SENT`
3. When the server responds with `matched: true`: state = `MATCHED`

State transitions are driven by callbacks from `ApiClient` to `MainViewModel`.

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

## Implementation Plan

### Step 1: Add raw detection StateFlow to FrameAnalyzer

**File:** `android/.../camera/FrameAnalyzer.kt`

Add a `_rawDetections` StateFlow that emits ALL detections from `PlateDetector.detect()` before OCR filtering. Each entry carries the bounding box, confidence, and source image dimensions.

### Step 2: Add detection feed to MainViewModel

**File:** `android/.../MainViewModel.kt`

- Add `DetectionFeedEntry` tracking: plate text, hash prefix, state, timestamp
- Add `_detectionFeed` StateFlow (list of recent entries, capped at 20)
- On plate detected: add entry with state `QUEUED`
- Add `onPlateSent(hash, matched)` callback for ApiClient to update state

### Step 3: Add upload callback to ApiClient

**File:** `android/.../network/ApiClient.kt`

Add an `onPlateSent: (String, Boolean) -> Unit` callback parameter. Call it after each successful 200 response with the plate hash and matched boolean.

### Step 4: Update DebugOverlay

**File:** `android/.../ui/DebugOverlay.kt`

- Accept `rawDetections` and `feedEntries` as new parameters
- Draw yellow bounding boxes for raw detections (with confidence label)
- Draw green bounding boxes for OCR'd plates (existing behavior)
- Render detection feed as a column on the right side with state labels

### Step 5: Wire new data through CameraScreen

**File:** `android/.../ui/CameraScreen.kt`

Collect `rawDetections` and `detectionFeed` from ViewModel and pass to DebugOverlay.
