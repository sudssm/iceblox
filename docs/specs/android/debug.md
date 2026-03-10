# Android Debug Overlay Enhancements

## Purpose

Enhance the debug overlay (REQ-M-19) to make E2E testing observable. Currently, bounding boxes only appear for plates that pass the full detect+OCR+normalize pipeline, which means nothing is visible when the ML model detects regions but OCR fails. Additionally, there is no way to see whether detected plates were successfully uploaded to the server.

## Requirements

See [Mobile App Spec — Debug Overlay Enhancements](../mobile-app/spec.md#debug-overlay-enhancements-dbg-1–dbg-4) for the shared DBG-1 through DBG-4 requirements and UI layout. This file covers Android-specific implementation details only.

## Android-Specific: DBG-3 Callback

State transitions are driven by callbacks from `ApiClient` to `MainViewModel`.

## Android-Specific: DBG-4 Debug Log Panel

- Panel: `fillMaxWidth()`, `heightIn(max = 150.dp)`, `background(Color.Black.copy(alpha = 0.75f))`, rounded top corners
- Entries: 8.sp monospace, `maxLines = 2`, color-coded by level
  - DEBUG: LightGray
  - WARNING: Yellow
  - ERROR: Red
- Each entry formatted as: `HH:mm:ss D/Tag: message`
- Auto-scrolls via `LaunchedEffect(entries.size)` + `scrollState.animateScrollTo()`
- Backed by a `DebugLog` singleton (`object DebugLog`) with a 50-entry `ArrayDeque` ring buffer
- Thread safety: `@Synchronized` on add, exposed as `StateFlow<List<LogEntry>>`
- `DebugLog.d/w/e(tag, message)` methods delegate to `android.util.Log` AND append to ring buffer
- Throwable overloads: `d/w/e(tag, message, throwable)` — appends exception message to the log entry
- All existing `Log.d/w/e` calls replaced with `DebugLog.d/w/e` to route through the panel

#### Files

- `android/.../debug/DebugLog.kt` — Singleton with `LogEntry` data class, `LogLevel` enum, ring buffer, `StateFlow`
- `android/.../ui/DebugLogPanel.kt` — Composable with `Column` + `verticalScroll` + auto-scroll
- `android/.../ui/DebugOverlay.kt` — Hosts `DebugLogPanel` at `Alignment.BottomCenter`
- `android/.../ui/CameraScreen.kt` — Collects `DebugLog.entries` via `collectAsState()`, passes to overlay

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
