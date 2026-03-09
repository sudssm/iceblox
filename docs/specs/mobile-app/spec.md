# Mobile App Specification

## Purpose

A dashboard-mounted mobile app for private security and community watch that continuously detects and reads license plates using the device camera, hashes the plate text on-device, and sends hashes to a server for comparison. No plaintext plate data or images ever leave the device in production mode.

## Environment

- **Mounting**: Dashboard-mounted, rear camera facing forward through windshield. Supports any device orientation (landscape or portrait) with automatic rotation handling.
- **Power**: Assumed connected to car power (USB/12V) — battery optimization is secondary to performance
- **Connectivity**: Intermittent — app must handle offline periods gracefully
- **Lighting**: Variable — daylight, night (headlights/streetlights), rain, glare

---

## Functional Requirements

### Camera Capture

#### REQ-M-1: Continuous Camera Capture

The app MUST continuously capture frames from the rear-facing camera at a minimum of 15 fps for processing. The camera preview MUST be displayed full-screen in the current device orientation.

#### REQ-M-2: Camera Resolution

The app MUST use a resolution sufficient for plate detection at distances of 3–20 meters. A minimum of 1080p capture resolution is REQUIRED. The app MAY downscale frames for the detection model while keeping full resolution available for OCR crops.

#### REQ-M-3: Splash Screen and Camera Start

When the app is opened, it MUST display a splash screen with the app name and a "Start Camera" button. Camera capture and plate detection MUST begin when the user taps the button. This provides an explicit user-initiated start rather than immediately activating the camera on launch.

#### REQ-M-3a: Recording Session Lifecycle

The app MUST model scanning as an explicit recording session with four UI states:
- **Idle**: splash screen visible, no camera capture or frame analysis running
- **Recording**: camera preview, detection pipeline, uploads, and live counters active
- **Stopping**: user has requested stop; no new detections are accepted while shutdown and final upload work runs
- **Summary**: session statistics are displayed; the camera preview and detection pipeline remain stopped

Tapping "Start Camera" MUST create a new session, reset session-scoped counters, and record a session start timestamp.

#### REQ-M-3b: Stop Recording Control

While a recording session is active, the camera view MUST display a persistent "Stop Recording" button.

- Placement: bottom-center, directly above the status bar
- Visibility: rendered above the camera preview and not hidden by debug UI
- Interaction: one tap ends the active session

When tapped, the app MUST immediately stop accepting new frames for plate detection and transition to the `Stopping` state.

#### REQ-M-3c: Session Summary

When a recording session ends, the app MUST present a session summary before returning to idle. The summary MUST include:
- Total plates seen this session
- Total ICE vehicles identified this session
- Session duration

Metric definitions:
- **Total plates seen**: count of unique normalized plates that passed deduplication and were enqueued during the session
- **Total ICE vehicles identified**: count of `match=true` server responses for hashes first enqueued during the session
- **Session duration**: elapsed wall-clock time from session start to the user tapping "Stop Recording", displayed in minutes and seconds

If uploads from the stopped session are still pending when the summary is shown, the UI MUST indicate that the ICE vehicle count reflects only confirmed matches received so far.

#### REQ-M-3d: Session Reset After Summary

When the user dismisses the session summary, the app MUST return to the idle splash screen. Starting a new session MUST reset:
- Last-detected timestamp
- Session plate count
- Session ICE vehicle count
- Session duration timer

#### REQ-M-4: Auto-Rotation Support

The app MUST support all device orientations (portrait, portrait upside-down, landscape left, landscape right) and rotate the UI automatically. The camera capture pipeline MUST compensate for device orientation so that frames are always correctly oriented for the detection model:
- **iOS**: Update the `AVCaptureConnection` video orientation/rotation angle when the device orientation changes.
- **Android**: Apply the `ImageProxy.imageInfo.rotationDegrees` rotation to the bitmap before passing it to the detector.

#### REQ-M-4a: Keep Screen On

The app MUST prevent the device screen from dimming or locking while the app is in the foreground. This is required for unattended dashboard-mounted operation.

- **iOS**: Set `UIApplication.shared.isIdleTimerDisabled = true`
- **Android**: Set `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON` on the activity window

### License Plate Detection

#### REQ-M-5: On-Device Plate Detection

The app MUST use an on-device ML model to detect license plate regions in camera frames. Detection MUST NOT require network connectivity.

#### REQ-M-6: Detection Model

The app MUST use a **YOLOv8-nano** model for license plate detection, converted to platform-native formats:
- **iOS**: Core ML (`.mlpackage` exported via `ultralytics`)
- **Android**: TFLite (`.tflite` converted via `ultralytics` export)

The detection model MUST:
- Identify rectangular plate regions and output bounding box coordinates
- Handle US plate formats only (standard passenger, commercial, temporary)
- Operate at a minimum of 10 fps on mid-range devices (iPhone 12 / Pixel 6 equivalent)
- Handle plates at angles up to 30 degrees from perpendicular

The detection model SHOULD:
- Handle partial occlusion (bumper stickers, dirt, plate frames)
- Distinguish front vs. rear plates when both are visible

#### REQ-M-7: Detection Confidence Threshold

The app MUST apply a configurable confidence threshold (default: 0.7) before passing detected regions to OCR. Detections below this threshold MUST be discarded.

#### REQ-M-8: Deduplication Window

The app MUST deduplicate detected plates within a configurable time window (default: 60 seconds). If the same plate text is detected multiple times within the window, only the first occurrence MUST be processed (hashed and queued). "Same plate" is determined by normalized text equality.

### OCR

#### REQ-M-9: On-Device OCR

The app MUST perform OCR on detected plate regions entirely on-device. OCR MUST NOT require network connectivity.

**Platform implementations:**
- **iOS**: ONNX Runtime CCT-XS recognition model (`.onnx`) with native fixed-slot decoding
- **Android**: ONNX Runtime CCT-XS recognition model (`.onnx`) with native fixed-slot decoding

See [`license_plate_ocr.md`](./license_plate_ocr.md) for model architecture, conversion pipeline, and validation criteria.

#### REQ-M-10: Plate Text Normalization

After OCR, the app MUST normalize plate text:
1. Convert to uppercase
2. Remove all whitespace
3. Remove hyphens and dashes
4. Remove any non-alphanumeric characters
5. Trim to a maximum of 8 characters

If the normalized result is fewer than 2 characters or more than 8 characters, it MUST be discarded as an invalid read.

#### REQ-M-11: OCR Confidence Threshold

The app MUST apply a configurable confidence threshold (default: 0.6) for OCR results. Results below this threshold MUST be discarded. Confidence is computed as the average softmax probability of non-padding characters from the CCT-XS fixed-slot model output.

### Hashing

#### REQ-M-12: HMAC-SHA256 Hashing

The app MUST compute HMAC-SHA256 of the normalized plate text using a shared pepper. The pepper MUST be:
- Injected into the app binary at build time from the root `.env` file (single source of truth shared by server, iOS, Android, and E2E tests)
- Identical across all devices (shared with the server for hash comparison)
- Never logged, displayed, or transmitted

Output: 64-character lowercase hex string.

#### REQ-M-12a: Lookalike Character Expansion

The CCT-XS OCR model (64×128px input, ~18px per character) frequently confuses visually similar characters. To compensate, the app MUST expand each OCR'd plate into all "lookalike" variants before hashing.

**Lookalike character groups:**

| Group | Characters | Rationale |
|-------|-----------|-----------|
| G1 | `0, O, D, Q, 8, B` | Round/oval/loop shapes merge at 18px |
| G2 | `1, I, L` | Vertical strokes |
| G3 | `5, S` | Similar curves |
| G4 | `2, Z` | Angular strokes |
| G5 | `A, 4` | Triangular top + crossbar |

**Expansion algorithm (BFS by substitution distance):**
1. Identify positions in the plate text that contain a confusable character
2. Start with the original text (substitutions = 0)
3. Generate all 1-substitution variants, then 2-substitution, etc.
4. Stop when reaching `maxVariants` cap (default: 64)
5. Each variant is paired with its substitution count (number of character positions changed from the original OCR reading)

This BFS ordering ensures the most likely variants (fewest substitutions) are always included when the cap is hit.

**Queue and upload behavior:**
- Each variant MUST be hashed independently and queued as a separate offline queue entry with its substitution count
- The substitution count MUST be sent to the server with each plate hash submission
- The plate counter MUST increment by 1 per original OCR reading (not per variant)

**Debug feed format:**
- Feed entry MUST show `"ABC1234 (+5)"` format where 5 is the number of additional variants (total minus 1)
- The hash prefix shown MUST be from the original (0-substitution) variant

#### REQ-M-13: No Plaintext Persistence

After hashing, the app MUST immediately discard the plaintext plate text from memory. Normalized plate text MUST NOT be:
- Written to disk
- Written to logs (including crash logs)
- Stored in any cache other than the deduplication window (REQ-M-8)
- Transmitted over the network

### Server Communication

#### REQ-M-14: Batch Upload

The app MUST send hashed plates to the server via HTTPS POST using the batch API format (see server spec REQ-S-1). Each upload sends a `{"plates": [...]}` array and receives a positionally aligned `{"results": [...]}` array. The app MUST batch uploads:
- Send a batch when the queue reaches 65 plates, OR
- Send a batch every 30 seconds if the queue is non-empty, OR
- Send a batch immediately when connectivity is restored after an offline period
- **(Android)**: Additionally, send a batch within 1 second of any plate being queued (if below batch size). This deadline flush ensures plates reach the server promptly without waiting for the full 30-second timer.

Whichever condition is met first triggers the send. When the queue contains more entries than the batch size, the app MUST send consecutive batches in a loop until the queue is drained or an error occurs.

#### REQ-M-14a: Match Response Handling

The server response includes a `results` array with a per-plate `matched` boolean (see server spec REQ-S-4). The `results` array is positionally aligned with the `plates` array in the request. The app MUST:
- Iterate over the `results` array and correlate each result with the corresponding queued entry by position
- Increment the originating session target counter for each plate where `matched` is `true`
- Display the updated target count in the status bar
- Map each variant hash back to its original plate's primary hash prefix (using an in-memory variant→primary mapping) and update the corresponding debug feed entry to MATCHED
- NOT alert the user or provide any visual/audio feedback on matches

#### REQ-M-14b: Final Flush on Session Stop

When the user taps "Stop Recording", the app MUST trigger an immediate upload attempt for queued hashes after halting new detections. If the upload attempt fails or the device is offline:
- Queued hashes MUST remain in the offline queue
- Normal retry behavior from REQ-M-17 and REQ-M-17a MUST still apply
- The session summary MAY be shown before all uploads complete, but it MUST indicate when match totals are still provisional

#### REQ-M-15: Offline Queue

When the device has no network connectivity, the app MUST queue hashed plates in local storage. The queue MUST:
- Persist across app restarts (stored in a local database)
- Store a maximum of 1,000 entries (oldest entries are dropped when full)
- Store only: hash, timestamp (UTC), location (if available), and local session identifier metadata
- NOT store plaintext plate text or images
- Entries older than 10 minutes MUST be pruned at the start of each batch upload cycle (stale entries are unlikely to be useful and could cause unbounded queue growth after extended offline periods)

#### REQ-M-15a: Session Attribution for Queued Plates

Each queued hash MUST be tagged with a local session identifier that is never transmitted to the server. The app MUST use this identifier to:
- Attribute match responses to the session in which the hash was captured
- Prevent delayed responses from a prior session from incrementing counters in a newer session
- Preserve correct attribution across app restarts until the queued entry is acknowledged or dropped

#### REQ-M-16: Location Attachment

Each hashed plate record MUST include the device's GPS coordinates at the time of detection. Location is required for the monitoring app to function (geo-queries depend on it).

- The app MUST request location permission on first launch
- If location permission is granted, every plate record MUST include latitude and longitude
- If location permission is denied, the app MUST still operate (detect, hash, upload) but SHOULD display a persistent warning in the status bar ("No GPS — location required for full functionality")
- Location accuracy: `kCLLocationAccuracyBest` on iOS / `PRIORITY_HIGH_ACCURACY` on Android

#### REQ-M-17: Retry Logic

If a batch upload fails, the app MUST retry with exponential backoff (initial delay: 5s, max delay: 5 minutes, max retries: 10). Failed batches MUST remain in the offline queue.

#### REQ-M-17a: Rate Limit Handling

If the server responds with `429 Too Many Requests`, the app MUST:
- Read the `Retry-After` header (seconds)
- Pause all uploads for the specified duration
- Keep plates in the offline queue during the backoff period
- Resume normal upload behavior after the backoff expires

### Push Notifications

#### REQ-M-60: Push Notification Permission

The app MUST request push notification permission from the user.

**Platform implementations:**
- **iOS**: Request authorization via `UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge])`. On grant, call `application.registerForRemoteNotifications()`.
- **Android**: On API 33+ (Android 13), request `POST_NOTIFICATIONS` runtime permission. Create a notification channel (`plate_alerts`, importance high) on app startup for Android 8.0+.

Push notifications are optional — the app MUST function normally if permission is denied.

#### REQ-M-61: Device Token Registration

After obtaining a push notification token, the app MUST send it to the server:

```
POST /api/v1/devices
Content-Type: application/json
X-Device-ID: <device identifier>

{
  "token": "<push token>",
  "platform": "ios" | "android"
}
```

The app MUST re-register whenever the token refreshes:
- **iOS**: `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` — convert `Data` to hex string (MUST NOT use `.description`)
- **Android**: `FirebaseMessagingService.onNewToken()` — token is a string

#### REQ-M-62: Notification Display

The app MUST handle incoming push notifications:
- **Foreground**: Display as a system banner notification (iOS: return `.banner, .sound` from `willPresent`; Android: build and post via `NotificationManager`)
- **Background / Not running**: Handled automatically by the system (iOS) or built by the app via `onMessageReceived` (Android, data-only messages)

#### REQ-M-63: Notification Privacy

Push notification payloads MUST NOT contain plaintext plate text, hashes, or target identifiers. Notification content is limited to a generic alert message (e.g., "Target plate detected") and a sighting reference ID.

### Proximity Alerts

#### REQ-M-64: Proximity Alert Subscription

The app MUST register with the server for proximity alerts by calling `POST /api/v1/subscribe` (see server spec REQ-S-13):
- On app boot, after location is available
- Every 10 minutes while the app is in the foreground
- Once when the app enters background (to refresh the server-side 1-hour TTL)

This ensures push notifications continue to be delivered for up to 1 hour after the app is closed.

#### REQ-M-65: GPS Truncation for Privacy

Before sending location to the subscribe endpoint, the app MUST truncate latitude and longitude to 2 decimal places. This provides approximately 1.1 km (~0.7 mile) location precision, balancing utility with user privacy — the server never learns the device's exact location.

#### REQ-M-66: Subscribe Request Format

Each subscription request MUST include:
- Truncated latitude and longitude (per REQ-M-65)
- `radius_miles`: Search radius in miles (default: 100, configured via `AppConfig`)
- `X-Device-ID` header (same device identifier used for plate uploads)

#### REQ-M-67: Recent Sightings Display

The app MUST process the `recent_sightings` array in the subscribe response. For v1:
- Log each sighting's location and timestamp to `DebugLog` without including plaintext plate text
- Maintain a counter of nearby sightings visible in the status bar or debug overlay

Full UI for displaying a sighting list/map is deferred to a future spec.

#### REQ-M-68: Background Subscription Persistence

When the app enters background, it MUST perform a final subscribe call to refresh the server-side subscription TTL. Combined with REQ-M-60/REQ-M-62 (push notification infrastructure), this ensures that:
- Users receive push notifications for nearby ICE vehicle detections even after closing the app
- The subscription persists for 1 hour after the last subscribe call
- No background processing or wake-ups are required on the device

### Debug Mode

#### REQ-M-18: Debug Mode Toggle

The app MUST include a debug mode, toggled via a hidden gesture (e.g., triple-tap on the camera preview). Debug mode MUST NOT be accessible in production builds distributed via app stores.

#### REQ-M-19: Debug Mode Features

When debug mode is active, the app MUST:
- Display bounding boxes around detected plates on the camera preview
- Display the recognized plate text above each bounding box
- Display the HMAC hash below each bounding box (truncated to first 8 characters)
- Display a frame rate counter (detection fps)
- Display the current queue depth (pending uploads)
- Display network connectivity status

The app MAY:
- Capture and store still images of detected plates to the app's sandboxed storage
- Export debug logs

#### REQ-M-20: Debug Image Storage

In debug mode, captured still images MUST be:
- Stored only in the app's sandboxed directory (not the photo library)
- Deleted when debug mode is toggled off
- Never transmitted to the server

---

## Non-Functional Requirements

### Performance

#### REQ-M-30: Detection Latency

End-to-end latency from frame capture to hash computation MUST be under 500ms on target devices (iPhone 12+ / Pixel 6+).

#### REQ-M-31: Memory Usage

The app MUST NOT exceed 200 MB of RAM usage during continuous operation. The detection pipeline MUST reuse buffers to avoid memory pressure.

#### REQ-M-32: Thermal Management

If the device reaches thermal throttling state, the app MUST reduce frame processing rate (e.g., to 5 fps) rather than crashing or being killed by the OS.

### Privacy

#### REQ-M-40: No Plaintext Exfiltration

Plaintext plate text MUST never leave the device via any channel: network, logs, crash reports, analytics, clipboard, or inter-process communication.

#### REQ-M-41: No Image Exfiltration

Camera frames and still images MUST never leave the device. In production mode, images MUST NOT be saved to disk at all.

#### REQ-M-42: Pepper Provisioning

The HMAC pepper is sourced from the root `.env` file and injected at build time:
- **iOS**: An Xcode build phase script reads `.env` and generates `Config/Pepper.swift` (gitignored) containing the pepper value. `PlateHasher` reads from the generated constant.
- **Android**: `build.gradle.kts` reads `../.env` and injects the pepper as `BuildConfig.PEPPER`. `PlateHasher` reads from `BuildConfig`.
- The pepper appears as a string literal in the compiled binary. The threat model accepts that a determined attacker with the binary can extract the pepper — obfuscation was previously used (XOR split) but was removed in favor of a single-source-of-truth `.env` approach that simplifies pepper rotation across all components.

#### REQ-M-43: No Third-Party Analytics

The app MUST NOT include third-party analytics SDKs (e.g., Firebase Analytics, Amplitude). Diagnostic data (crash logs, performance metrics) MUST be collected only via platform-native mechanisms (Xcode Organizer / Play Console) and MUST NOT contain plate data.

### Reliability

#### REQ-M-50: Crash Recovery

On restart after a crash, the app MUST:
- Resume camera capture and detection automatically
- Retain the offline queue (hashed plates awaiting upload)
- Not lose any queued hashes

#### REQ-M-51: Background Behavior

Background behavior is platform-specific:

- **iOS**: When the app is backgrounded, it MUST stop camera capture and detection immediately, attempt to flush the offline queue, and stop consuming CPU for frame processing. Continuous camera capture on iOS REQUIRES the app to remain in the foreground.
- **Android**: When the app is backgrounded, it MUST continue camera capture, detection, deduplication, hashing, queueing, location attachment, and batch upload using an Android foreground service. The app MUST display a persistent notification while background capture is active, and that notification MUST include a user-visible stop action.

When foregrounded again, the app MUST resume the visible camera preview within 1 second.

---

## UI

### Primary Screen

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│                  Camera Preview                      │
│                  (full screen)                       │
│                                                      │
│                                                      │
│                [Stop Recording]                      │
│              12 uploads queued ✕                     │
│  ● Online │ Last: 2s ago │ Plates: 47 │ Targets: 2  │
└──────────────────────────────────────────────────────┘
```

- **Bottom-center control**:
  - "Stop Recording" button, always visible during an active session
  - Positioned directly above the upload queue banner (if visible) and the status bar
  - Tapping ends the current session and opens the session summary
- **Upload queue banner** (conditional, between stop button and status bar):
  - Shown only when the offline queue is non-empty (`queueDepth > 0`)
  - Displays `"N uploads queued"` in amber/yellow monospace text on a semi-transparent black pill-shaped background
  - Includes a dismiss button (✕) that clears the entire offline queue
  - Also shown on the splash screen (bottom-center) when there are queued entries from a previous session
- **Status bar** (bottom, always visible):
  - Connectivity indicator (● Online / ● Offline)
  - Time since last plate detected ("Last: 2s ago", or "Last: --" if none)
  - Total plates detected this session
  - Total target plates detected this session (from server match responses)
- Camera preview fills the entire screen
- Minimal UI — this is a "set and forget" dashboard app

### Session Summary

```
┌────────────────────────────────────────────┐
│           Session Summary                  │
│                                            │
│  Plates seen: 47                           │
│  ICE vehicles: 2                           │
│  Duration: 12m 08s                         │
│                                            │
│  Pending sync: 3 uploads                   │
│                                            │
│              [Done]                        │
└────────────────────────────────────────────┘
```

- Presented as a modal sheet/dialog after the user stops recording
- Shows only session-scoped metrics
- `Pending sync` is shown only when uploads from the stopped session have not all been acknowledged yet
- Dismissing the summary returns the user to the splash screen

### Debug Overlay (Debug Mode Only)

```
┌──────────────────────────────────────────────────────┐
│  FPS: 28  │  Queue: 3  │  ● Online                  │
│                                                      │
│        ┌─────────────┐                               │
│        │  ABC 1234   │  ← recognized text            │
│        │ ┌─────────┐ │                               │
│        │ │ (plate) │ │  ← bounding box               │
│        │ └─────────┘ │                               │
│        │  a3f8b2c1   │  ← hash (truncated)           │
│        └─────────────┘                               │
│                                                      │
│  [DEBUG MODE]                                        │
└──────────────────────────────────────────────────────┘
```

---

## Platform-Specific Implementation Notes

### iOS (Swift)

| Component | Framework |
|---|---|
| Camera capture | AVFoundation (`AVCaptureSession`) |
| Plate detection | Core ML (YOLOv8-nano `.mlpackage`) |
| OCR | ONNX Runtime (CCT-XS `.onnx` + fixed-slot decode) |
| Hashing | CryptoKit (`HMAC<SHA256>`) |
| Pepper storage | Build-time constant (generated from root `.env` by Xcode build phase) |
| Local database | Core Data or SQLite (for offline queue) |
| Networking | URLSession |
| Push notifications | UserNotifications (`UNUserNotificationCenter`) |

### Android (Kotlin)

| Component | Framework |
|---|---|
| Camera capture | CameraX |
| Plate detection | TFLite (YOLOv8-nano `.tflite`) |
| OCR | ONNX Runtime (CCT-XS `.onnx` + fixed-slot decode) |
| Hashing | `javax.crypto.Mac` with `HmacSHA256` |
| Pepper storage | Build-time constant (injected from root `.env` via `BuildConfig`) |
| Local database | Room (for offline queue) |
| Networking | OkHttp / Retrofit |
| Push notifications | Firebase Cloud Messaging (`firebase-messaging`) |

---

## Constraints

- C-1: No network calls except to the configured server endpoint and platform push notification services (APNs managed by iOS; FCM managed by Firebase SDK)
- C-2: No user accounts or authentication in v1. `device_id` is the hardware identifier (`identifierForVendor` on iOS, `Settings.Secure.ANDROID_ID` on Android)
- C-3: The app does not receive the target plate list. It learns only whether individual submitted plates matched (boolean per plate in server response)
- C-4: The ML detection model must be bundled with the app (no model downloads)
- C-5: Minimum deployment targets: iOS 17+ / Android API 28+ (Android 9.0)

---

## Resolved Decisions

| Question | Decision |
|---|---|
| ML model | YOLOv8-nano, exported to Core ML (iOS) and TFLite (Android) |
| Plate formats | US only |
| Status bar content | Last detected timestamp, total plates, total targets; stop button sits directly above the status bar |
| Detection feedback | None (no sound, no vibration) |
| HMAC pepper provisioning | Injected at build time from root `.env` (single source of truth) |
| device_id | Hardware ID (`identifierForVendor` / `ANDROID_ID`) |
| Training data (Phase 1) | HuggingFace license-plate-object-detection (8,823 images), fine-tuned from COCO |
| Targets counter styling | No special color treatment |
| Session stop behavior | Stop immediately halts capture/detection, triggers a final flush attempt, then shows a summary |
| Session summary semantics | Plates = unique queued reads, ICE = confirmed matches attributed to that session, duration = start-to-stop elapsed time |
| OCR model | fast-plate-ocr CCT-XS (global, 65+ countries), deployed as ONNX to both platforms with native fixed-slot decoding |
| Lookalike handling | Client-side expansion with substitution count (not canonical collapse). Expansion preserves substitution distance for confidence scoring; collapse loses this signal. |

## Open Questions

None — all questions resolved. See `Resolved Decisions` above.

## Related Specs

- [`license_plate_detection.md`](./license_plate_detection.md) — Phase 1 model training data, pipeline, and validation criteria
- [`license_plate_ocr.md`](./license_plate_ocr.md) — CCT-XS OCR model architecture, export pipeline, and validation criteria
- [`../../future/yolo_model_improvements.md`](../../future/yolo_model_improvements.md) — Phase 2 (expanded data) and Phase 3 (custom collection) plans

---

## Implementation Plan — iOS

### Architecture

Single-screen SwiftUI app with an `AVCaptureSession` pipeline running on a background queue. Processing pipeline uses a serial `DispatchQueue` to avoid frame contention. Offline queue is backed by a lightweight SQLite store (via SwiftData or raw SQLite — no Core Data overhead needed for this simple schema). iOS capture is foreground-only: if the app is backgrounded, the camera session stops and only brief queue flush / subscription refresh work may continue under normal iOS lifecycle rules.

### Project Structure

```
ios/IceBloxApp/
├── IceBloxApp.swift                    # App entry point, landscape lock, splash→camera flow
├── ContentView.swift                   # Root view, wires all managers, session lifecycle, stop control, session summary card
├── SplashScreenView.swift              # Splash screen with app name and Start Camera button
├── Views/
│   ├── StatusBarView.swift             # Bottom status bar (online, last detected, counts)
│   └── DebugOverlayView.swift          # Bounding boxes, plate text, hash, FPS, detection feed
├── Camera/
│   ├── CameraManager.swift             # AVCaptureSession setup, frame delegate
│   ├── CameraPreviewView.swift         # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   ├── FrameProcessor.swift            # Orchestrates detect → OCR → normalize → hash → queue
│   └── SimulatorCamera.swift           # Timer-driven frame generator for simulator testing (simulator-only)
├── Detection/
│   ├── PlateDetector.swift             # Core ML inference, bounding box extraction
│   └── PlateOCR.swift                  # ONNX Runtime CCT-XS inference + fixed-slot decode on cropped regions
├── Processing/
│   ├── PlateNormalizer.swift           # Uppercase, strip, validate length
│   ├── PlateHasher.swift              # HMAC-SHA256 via CryptoKit, pepper from generated Pepper.swift
│   ├── DeduplicationCache.swift        # Time-windowed set of recently seen normalized plates
│   └── LookalikeExpander.swift        # BFS expansion of confusable characters (REQ-M-12a)
├── Networking/
│   ├── APIClient.swift                 # URLSession POST to server, batch construction
│   ├── AlertClient.swift               # Subscribe endpoint client, 10-min timer, GPS truncation
│   ├── RetryManager.swift              # Exponential backoff, 429 handling
│   └── ConnectivityMonitor.swift       # NWPathMonitor wrapper, triggers queue flush
├── Persistence/
│   ├── OfflineQueue.swift              # SQLite-backed FIFO queue (hash, timestamp, lat, lng)
│   └── OfflineQueueEntry.swift         # Data model
├── Location/
│   └── LocationManager.swift           # CLLocationManager, permission handling, GPS warning
├── Config/
│   ├── AppConfig.swift                 # Confidence thresholds, batch size, dedup window, server URL
│   └── Pepper.swift                    # Generated at build time from root .env (gitignored)
├── Models/
│   ├── plate_detector.mlpackage        # YOLOv8-nano Core ML model (bundled)
│   └── plate_ocr.onnx                 # CCT-XS ONNX OCR model (bundled)
└── Info.plist                          # Camera, location usage descriptions
```

### Implementation Order

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project setup | REQ-M-3, REQ-M-4, C-5 | Auto-rotation support, Info.plist permissions (camera, location), min iOS 16 |
| 2 | Camera capture | REQ-M-1, REQ-M-2 | AVCaptureSession with 1080p preset, rear camera, preview layer |
| 3 | UI shell | REQ-M-3, REQ-M-3a, REQ-M-3b, UI spec | Splash screen with Start Camera button → full-screen camera preview + stop control + status bar |
| 4 | Plate detection | REQ-M-5, REQ-M-6, REQ-M-7 | Core ML inference on camera frames, confidence filter, bounding boxes |
| 5 | OCR | REQ-M-9, REQ-M-10, REQ-M-11 | ONNX Runtime CCT-XS inference + fixed-slot decode on cropped plate regions, normalization, validation |
| 6 | Hashing | REQ-M-12, REQ-M-13, REQ-M-42 | CryptoKit HMAC, pepper obfuscation, immediate plaintext discard |
| 7 | Deduplication | REQ-M-8 | Time-windowed cache keyed by normalized text |
| 8 | Frame processor | REQ-M-30 | Wire pipeline: frame → detect → OCR → normalize → dedup → hash → queue |
| 9 | Offline queue | REQ-M-15, REQ-M-15a | SQLite persistence, max 1000 entries, oldest eviction, local session attribution |
| 10 | Location | REQ-M-16 | CLLocationManager, attach GPS to each queue entry, "No GPS" warning |
| 11 | Network layer | REQ-M-14, REQ-M-14a, REQ-M-14b, REQ-M-17, REQ-M-17a | Batch POST, match response parsing, final flush on stop, exponential backoff, 429 handling |
| 12 | Session UX | REQ-M-3c, REQ-M-3d | Session summary sheet, reset to idle after dismissal |
| 13 | Status bar | UI spec | Wire live data: connectivity, last detected, plates count, targets count |
| 14 | Debug overlay | REQ-M-18, REQ-M-19, REQ-M-20 | Bounding boxes, text, hash, FPS, debug image capture |
| 15 | Thermal mgmt | REQ-M-32 | ProcessInfo.thermalState observer, reduce FPS when throttled |
| 16 | Background/crash | REQ-M-50, REQ-M-51 | Enforce foreground-only capture on iOS, flush queue on background, resume preview on foreground |
| 17 | Privacy audit | REQ-M-40, REQ-M-41, REQ-M-43 | Verify no plaintext leaks in logs, no analytics SDKs, no image export |
| 18 | Push notifications | REQ-M-60, REQ-M-61, REQ-M-62, REQ-M-63 | UNUserNotificationCenter permission, APNs token registration, notification handling |
| 19 | Alert client | REQ-M-64, REQ-M-65, REQ-M-66 | AlertClient.swift: POST /api/v1/subscribe, 10-min timer, GPS truncation to 2 decimal places |
| 20 | Sightings handling | REQ-M-67 | Parse recent_sightings response, log to DebugLog, increment counter |
| 21 | Alert lifecycle | REQ-M-64, REQ-M-68 | Start timer on active, subscribe+stop on background (refresh TTL for post-close notifications) |

### Key Technical Notes

- **Frame processing**: Use `AVCaptureVideoDataOutputSampleBufferDelegate`. Process every Nth frame (skip frames to hit 10-15 fps detection) rather than every frame.
- **Core ML threading**: Run inference on a dedicated `DispatchQueue` to keep the camera preview smooth.
- **Memory**: Reuse `CVPixelBuffer` and avoid UIImage conversions in the hot path.
- **Pepper injection**: An Xcode "Generate Pepper" build phase reads `PEPPER` from `../.env` and generates `Config/Pepper.swift` (gitignored). `PlateHasher` reads `Pepper.value` at runtime.

#### Model Invocation Flow (Core ML)

Camera frame to Core ML inference:

1. `CameraManager` receives `CMSampleBuffer` via `captureOutput(_:didOutput:from:)` delegate callback on a dedicated serial `DispatchQueue`
2. Extract `CVPixelBuffer` from the sample buffer via `CMSampleBufferGetImageBuffer` — no `UIImage` conversion needed
3. Create a `VNCoreMLModel` wrapping the compiled `plate_detector.mlpackage` (load once at startup, reuse — `VNCoreMLModel(for:)` is expensive)
4. Create a `VNCoreMLRequest` with the cached Vision model
5. Create a `VNImageRequestHandler(cvPixelBuffer:)` — Vision handles resizing to 640x640 internally
6. Call `handler.perform([request])`
7. Results are `[VNRecognizedObjectObservation]`, each with:
   - `boundingBox`: normalized `CGRect` (origin at **bottom-left**, Vision coordinate system — must convert to UIKit top-left origin for cropping)
   - `confidence`: `Float` — filter at ≥ 0.7 per REQ-M-7
8. Convert `boundingBox` from Vision coordinates to pixel coordinates on the original frame, then crop the `CVPixelBuffer` at each bounding box for OCR

**NMS**: The Core ML export uses `nms=True` (see `license_plate_detection.md`), so non-max suppression runs inside the model. No manual NMS implementation needed on iOS.

**Coordinate conversion**: Vision's `boundingBox` is normalized with bottom-left origin. To convert to pixel coordinates: `x = boundingBox.origin.x * imageWidth`, `y = (1 - boundingBox.origin.y - boundingBox.height) * imageHeight`, with width/height scaled similarly.

---

## Implementation Plan — Android

### Architecture

Single-activity Jetpack Compose app. CameraX provides the preview and frame analysis. TFLite runs on a background thread via `ImageAnalysis.Analyzer`. Room database for the offline queue. A foreground capture service owns background camera analysis when the app is not visible, while the foreground activity binds the preview UI to the same shared pipeline state.

### Project Structure

```
android/app/src/main/java/com/iceblox/app/
├── IceBloxApplication.kt               # Application-scoped capture repository
├── MainActivity.kt                      # Activity, permission requests, splash→camera flow, notification channel
├── MainViewModel.kt                     # Pipeline state, counts, connectivity, coordinates, session lifecycle
├── capture/
│   └── CaptureRepository.kt             # Shared pipeline state used by UI + background service
├── ui/
│   ├── CameraScreen.kt                  # Compose: camera preview + status bar + stop control + session summary (includes StatusBar, TestImagePreview, SessionSummaryOverlay composables)
│   ├── SplashScreen.kt                  # Splash screen with app name and Start Camera button
│   ├── DebugOverlay.kt                  # Bounding boxes, plate text, hash, FPS, detection feed
│   └── theme/                           # Material 3 theme, colors, typography
├── camera/
│   ├── CameraPreview.kt                 # Compose CameraX preview wrapper
│   ├── FrameAnalyzer.kt                 # ImageAnalysis.Analyzer → detect → OCR → hash → queue
│   └── TestFrameFeeder.kt              # Test mode: loads images, feeds them through analyzeBitmap() on a timer
├── detection/
│   ├── PlateDetector.kt                 # TFLite interpreter, YOLOv8-nano inference, NMS
│   └── PlateOCR.kt                      # ONNX Runtime CCT-XS inference + fixed-slot decode on cropped bitmaps
├── processing/
│   ├── PlateNormalizer.kt               # Uppercase, strip, validate
│   ├── PlateHasher.kt                   # javax.crypto.Mac HMAC-SHA256, pepper from BuildConfig
│   ├── DeduplicationCache.kt            # Time-windowed set
│   └── LookalikeExpander.kt            # BFS expansion of confusable characters (REQ-M-12a)
├── network/
│   ├── ApiClient.kt                     # OkHttp, POST /api/v1/plates + /api/v1/devices
│   ├── AlertClient.kt                   # Subscribe endpoint client, coroutine timer, GPS truncation
│   ├── RetryManager.kt                  # Exponential backoff, 429 handling
│   └── ConnectivityMonitor.kt           # ConnectivityManager.NetworkCallback
├── notification/
│   └── PushNotificationService.kt       # FirebaseMessagingService: onNewToken, onMessageReceived
├── persistence/
│   ├── OfflineQueueDatabase.kt          # Room database definition
│   ├── OfflineQueueDao.kt               # Insert, query oldest, delete, count
│   └── OfflineQueueEntry.kt             # Entity: hash, timestamp, latitude, longitude
├── location/
│   └── LocationProvider.kt              # FusedLocationProviderClient, permission handling
├── config/
│   └── AppConfig.kt                     # Confidence thresholds, batch size, server URL, notification config
├── service/
│   └── BackgroundCaptureService.kt      # Foreground service for background camera capture
└── assets/
    ├── plate_detector.tflite            # YOLOv8-nano TFLite model (bundled)
    └── plate_ocr.onnx                  # CCT-XS ONNX OCR model (bundled)

android/app/src/main/
├── AndroidManifest.xml                  # Permissions: CAMERA, ACCESS_FINE_LOCATION, INTERNET, POST_NOTIFICATIONS

android/app/src/debug/
└── assets/
    └── test_images/                     # Test plate images for test mode (debug builds only)
```

### Implementation Order

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project setup | REQ-M-3, REQ-M-4, C-5 | Auto-rotation in manifest, permissions, min API 31 |
| 2 | Camera capture | REQ-M-1, REQ-M-2 | CameraX preview + ImageAnalysis, 1080p resolution |
| 3 | UI shell | REQ-M-3, REQ-M-3a, REQ-M-3b, UI spec | Compose: splash screen with Start Camera button → full-screen preview + stop control + status bar |
| 4 | Plate detection | REQ-M-5, REQ-M-6, REQ-M-7 | TFLite interpreter, YOLOv8-nano inference, NMS, confidence filter |
| 5 | OCR | REQ-M-9, REQ-M-10, REQ-M-11 | ONNX Runtime CCT-XS inference + fixed-slot decode on cropped bitmaps, normalization, validation |
| 6 | Hashing | REQ-M-12, REQ-M-13, REQ-M-42 | javax.crypto.Mac HMAC, pepper obfuscation, plaintext discard |
| 7 | Deduplication | REQ-M-8 | Time-windowed cache |
| 8 | Frame analyzer | REQ-M-30 | Wire pipeline in ImageAnalysis.Analyzer callback |
| 9 | Offline queue | REQ-M-15, REQ-M-15a | Room database, max 1000 entries, oldest eviction, local session attribution |
| 10 | Location | REQ-M-16 | FusedLocationProviderClient, permission flow, GPS warning |
| 11 | Network layer | REQ-M-14, REQ-M-14a, REQ-M-14b, REQ-M-17, REQ-M-17a | OkHttp POST, batch, match parsing, final flush on stop, backoff, 429 |
| 12 | Session UX | REQ-M-3c, REQ-M-3d | Session summary dialog, reset to idle after dismissal |
| 13 | Status bar | UI spec | Wire ViewModel state to Compose UI |
| 14 | Debug overlay | REQ-M-18, REQ-M-19, REQ-M-20 | Canvas overlay on preview, debug image capture |
| 15 | Thermal mgmt | REQ-M-32 | PowerManager thermal status listener, reduce analysis FPS |
| 16 | Background/crash | REQ-M-50, REQ-M-51 | Start camera foreground service on background, keep analysis/upload running, and reattach preview on foreground |
| 17 | Privacy audit | REQ-M-40, REQ-M-41, REQ-M-43 | Verify no leaks, no analytics SDKs, ProGuard/R8 rules |
| 18 | Push notifications | REQ-M-60, REQ-M-61, REQ-M-62, REQ-M-63 | Firebase setup, FCM service, token registration, notification channel, POST_NOTIFICATIONS permission |
| 19 | Alert client | REQ-M-64, REQ-M-65, REQ-M-66 | AlertClient.kt: POST /api/v1/subscribe, coroutine timer (600s delay), GPS truncation |
| 20 | Sightings handling | REQ-M-67 | Parse recent_sightings response, log to DebugLog, increment counter |
| 21 | Alert lifecycle | REQ-M-64, REQ-M-68 | Start timer with the foreground/background capture lifecycle and subscribe on stop to refresh TTL |

### Key Technical Notes

- **TFLite NMS**: YOLOv8 TFLite export does **not** include NMS. Must implement post-processing manually: filter by confidence → non-max suppression on bounding boxes.
- **CameraX frame skipping**: Use `ImageAnalysis.Builder().setBackpressureStrategy(STRATEGY_KEEP_ONLY_LATEST)` — automatically drops frames when the analyzer is busy.
- **Room threading**: Use `suspend` DAO functions with coroutines. Queue insert on the analyzer thread; batch reads on the network thread.
- **Pepper injection**: `build.gradle.kts` reads `PEPPER` from `../.env` and injects it as `BuildConfig.PEPPER`. `PlateHasher` reads the value at runtime.

#### Model Invocation Flow (TFLite)

Camera frame to TFLite inference:

1. `FrameAnalyzer.analyze(ImageProxy)` receives the frame from CameraX on a background thread
2. Convert `ImageProxy` to `Bitmap` (via `ImageProxy.toBitmap()` or manual YUV→RGB conversion for better performance)
3. Resize the bitmap to 640x640 (model's expected input size)
4. Normalize pixel values to `[0, 1]` float range and pack into a `ByteBuffer` — shape: `[1, 640, 640, 3]`, `float32`. Use `ByteBuffer.allocateDirect()` with `ByteOrder.nativeOrder()`, allocated once and reused across frames to avoid GC pressure
5. Allocate output tensor buffer(s) — YOLOv8-nano raw output shape is `[1, 4+num_classes, 8400]` (8400 candidate detections, each with 4 bbox coords + class confidence scores). YOLOv8 does **not** have a separate objectness score (unlike YOLOv5).
6. Call `interpreter.run(inputBuffer, outputBuffer)`
7. Post-process the raw output:
   a. Transpose output to `[8400, 5]` for easier iteration (single-class: 4 bbox + 1 class confidence)
   b. For each candidate, extract `[cx, cy, w, h, confidence]` where `cx/cy/w/h` are in 640x640 model coordinate space
   c. Filter candidates by confidence ≥ 0.7
   d. Convert `[cx, cy, w, h]` to `[x1, y1, x2, y2]`: `x1 = cx - w/2`, `y1 = cy - h/2`, `x2 = cx + w/2`, `y2 = cy + h/2`
   e. Scale coordinates from 640x640 back to original bitmap dimensions
   f. Apply greedy non-max suppression (IoU threshold ~0.45): sort by confidence descending, accept top box, suppress all boxes with IoU > threshold, repeat
8. Crop the original (pre-resize) bitmap at each surviving bounding box for OCR

**NMS implementation**: Unlike Core ML, TFLite export does NOT include NMS — this is the biggest platform difference. Implement standard greedy NMS: IoU = area_of_intersection / area_of_union. Typical IoU threshold is 0.45.

**Interpreter setup**: Create the `Interpreter` once at startup. Use `Interpreter.Options()` to set thread count (2–4). Optionally enable GPU delegate (`GpuDelegate`) or NNAPI delegate for hardware acceleration on supported devices.

**Input buffer reuse**: The `ByteBuffer` for model input is ~4.9 MB (640 × 640 × 3 × 4 bytes). Allocate once via `ByteBuffer.allocateDirect()` and call `rewind()` before each frame to avoid repeated allocation.
