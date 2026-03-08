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
- **iOS**: Vision framework (`VNRecognizeTextRequest`) with `.accurate` recognition level
- **Android**: ML Kit Text Recognition

#### REQ-M-10: Plate Text Normalization

After OCR, the app MUST normalize plate text:
1. Convert to uppercase
2. Remove all whitespace
3. Remove hyphens and dashes
4. Remove any non-alphanumeric characters
5. Trim to a maximum of 8 characters

If the normalized result is fewer than 2 characters or more than 8 characters, it MUST be discarded as an invalid read.

#### REQ-M-11: OCR Confidence Threshold

The app MUST apply a configurable confidence threshold (default: 0.6) for OCR results. Results below this threshold MUST be discarded. On iOS, this maps to `VNRecognizedText.confidence`. On Android, this maps to `Text.TextBlock.confidence`.

### Hashing

#### REQ-M-12: HMAC-SHA256 Hashing

The app MUST compute HMAC-SHA256 of the normalized plate text using a shared pepper. The pepper MUST be:
- Hardcoded in the app binary at build time
- Identical across all devices (shared with the server for hash comparison)
- Never logged, displayed, or transmitted
- Obfuscated in the binary (not stored as a plaintext string literal)

Output: 64-character lowercase hex string.

#### REQ-M-13: No Plaintext Persistence

After hashing, the app MUST immediately discard the plaintext plate text from memory. Normalized plate text MUST NOT be:
- Written to disk
- Written to logs (including crash logs)
- Stored in any cache other than the deduplication window (REQ-M-8)
- Transmitted over the network

### Server Communication

#### REQ-M-14: Batch Upload

The app MUST send hashed plates to the server via HTTPS POST (see server spec for endpoint schema). The app MUST batch uploads:
- Send a batch when the queue reaches 10 plates, OR
- Send a batch every 30 seconds if the queue is non-empty, OR
- Send a batch immediately when connectivity is restored after an offline period

Whichever condition is met first triggers the send.

#### REQ-M-14a: Match Response Handling

The server response includes a per-plate `match` boolean (see server spec REQ-S-4). The app MUST:
- Increment the session target counter for each plate where `match` is `true`
- Display the updated target count in the status bar
- NOT store which specific hashes matched (only the running count)
- NOT alert the user or provide any visual/audio feedback on matches

#### REQ-M-15: Offline Queue

When the device has no network connectivity, the app MUST queue hashed plates in local storage. The queue MUST:
- Persist across app restarts (stored in a local database)
- Store a maximum of 1,000 entries (oldest entries are dropped when full)
- Store only: hash, timestamp (UTC), and location (if available)
- NOT store plaintext plate text or images

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

#### REQ-M-42: Pepper Obfuscation

The HMAC pepper is hardcoded at build time. To resist casual extraction from the binary:
- The pepper MUST NOT appear as a contiguous string literal
- The app SHOULD use XOR obfuscation or split the key across multiple constants
- This is a deterrent, not a cryptographic guarantee — the threat model accepts that a determined attacker with the binary can extract the pepper

#### REQ-M-43: No Third-Party Analytics

The app MUST NOT include third-party analytics SDKs (e.g., Firebase Analytics, Amplitude). Diagnostic data (crash logs, performance metrics) MUST be collected only via platform-native mechanisms (Xcode Organizer / Play Console) and MUST NOT contain plate data.

### Reliability

#### REQ-M-50: Crash Recovery

On restart after a crash, the app MUST:
- Resume camera capture and detection automatically
- Retain the offline queue (hashed plates awaiting upload)
- Not lose any queued hashes

#### REQ-M-51: Background Behavior

When the app is backgrounded, it MUST:
- Stop camera capture and detection immediately
- Attempt to flush the offline queue (send pending hashes)
- Not consume CPU for frame processing

When foregrounded again, it MUST resume capture within 1 second.

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
│  ● Online │ Last: 2s ago │ Plates: 47 │ Targets: 2  │
└──────────────────────────────────────────────────────┘
```

- **Status bar** (bottom, always visible):
  - Connectivity indicator (● Online / ● Offline)
  - Time since last plate detected ("Last: 2s ago", or "Last: --" if none)
  - Total plates detected this session
  - Total target plates detected this session (from server match responses)
- Camera preview fills the entire screen
- Minimal UI — this is a "set and forget" dashboard app

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
| OCR | Vision (`VNRecognizeTextRequest`) |
| Hashing | CryptoKit (`HMAC<SHA256>`) |
| Pepper storage | Build-time constant (obfuscated) |
| Local database | Core Data or SQLite (for offline queue) |
| Networking | URLSession |
| Push notifications | UserNotifications (`UNUserNotificationCenter`) |

### Android (Kotlin)

| Component | Framework |
|---|---|
| Camera capture | CameraX |
| Plate detection | TFLite (YOLOv8-nano `.tflite`) |
| OCR | ML Kit Text Recognition |
| Hashing | `javax.crypto.Mac` with `HmacSHA256` |
| Pepper storage | Build-time constant (obfuscated) |
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
| Status bar content | Last detected timestamp, total plates, total targets |
| Detection feedback | None (no sound, no vibration) |
| HMAC pepper provisioning | Hardcoded at build time, obfuscated in binary |
| device_id | Hardware ID (`identifierForVendor` / `ANDROID_ID`) |
| Training data (Phase 1) | HuggingFace license-plate-object-detection (8,823 images), fine-tuned from COCO |
| Targets counter styling | No special color treatment |

## Open Questions

None — all questions resolved. See `Resolved Decisions` above.

## Related Specs

- [`license_plate_detection.md`](./license_plate_detection.md) — Phase 1 model training data, pipeline, and validation criteria
- [`../../future/yolo_model_improvements.md`](../../future/yolo_model_improvements.md) — Phase 2 (expanded data) and Phase 3 (custom collection) plans

---

## Implementation Plan — iOS

### Architecture

Single-screen SwiftUI app with an `AVCaptureSession` pipeline running on a background queue. Processing pipeline uses a serial `DispatchQueue` to avoid frame contention. Offline queue is backed by a lightweight SQLite store (via SwiftData or raw SQLite — no Core Data overhead needed for this simple schema).

### Project Structure

```
ios/CamerasApp/
├── CamerasApp.swift                    # App entry point, landscape lock, splash→camera flow
├── ContentView.swift                   # Root view, wires all managers
├── SplashScreenView.swift              # Splash screen with app name and Start Camera button
├── Views/
│   ├── StatusBarView.swift             # Bottom status bar (online, last detected, counts)
│   └── DebugOverlayView.swift          # Bounding boxes, plate text, hash, FPS, detection feed
├── Camera/
│   ├── CameraManager.swift             # AVCaptureSession setup, frame delegate
│   ├── CameraPreviewView.swift         # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   └── FrameProcessor.swift            # Orchestrates detect → OCR → normalize → hash → queue
├── Detection/
│   ├── PlateDetector.swift             # Core ML inference, bounding box extraction
│   └── PlateOCR.swift                  # Vision VNRecognizeTextRequest on cropped regions
├── Processing/
│   ├── PlateNormalizer.swift           # Uppercase, strip, validate length
│   ├── PlateHasher.swift              # HMAC-SHA256 via CryptoKit, pepper obfuscation
│   └── DeduplicationCache.swift        # Time-windowed set of recently seen normalized plates
├── Networking/
│   ├── APIClient.swift                 # URLSession POST to server, batch construction
│   ├── RetryManager.swift              # Exponential backoff, 429 handling
│   └── ConnectivityMonitor.swift       # NWPathMonitor wrapper, triggers queue flush
├── Persistence/
│   ├── OfflineQueue.swift              # SQLite-backed FIFO queue (hash, timestamp, lat, lng)
│   └── OfflineQueueEntry.swift         # Data model
├── Location/
│   └── LocationManager.swift           # CLLocationManager, permission handling, GPS warning
├── Config/
│   └── AppConfig.swift                 # Confidence thresholds, batch size, dedup window, server URL
├── Models/
│   └── plate_detector.mlpackage        # YOLOv8-nano Core ML model (bundled)
└── Info.plist                          # Camera, location usage descriptions
```

### Implementation Order

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project setup | REQ-M-3, REQ-M-4, C-5 | Auto-rotation support, Info.plist permissions (camera, location), min iOS 16 |
| 2 | Camera capture | REQ-M-1, REQ-M-2 | AVCaptureSession with 1080p preset, rear camera, preview layer |
| 3 | UI shell | REQ-M-3, UI spec | Splash screen with Start Camera button → full-screen camera preview + status bar |
| 4 | Plate detection | REQ-M-5, REQ-M-6, REQ-M-7 | Core ML inference on camera frames, confidence filter, bounding boxes |
| 5 | OCR | REQ-M-9, REQ-M-10, REQ-M-11 | Vision text recognition on cropped plate regions, normalization, validation |
| 6 | Hashing | REQ-M-12, REQ-M-13, REQ-M-42 | CryptoKit HMAC, pepper obfuscation, immediate plaintext discard |
| 7 | Deduplication | REQ-M-8 | Time-windowed cache keyed by normalized text |
| 8 | Frame processor | REQ-M-30 | Wire pipeline: frame → detect → OCR → normalize → dedup → hash → queue |
| 9 | Offline queue | REQ-M-15 | SQLite persistence, max 1000 entries, oldest eviction |
| 10 | Location | REQ-M-16 | CLLocationManager, attach GPS to each queue entry, "No GPS" warning |
| 11 | Network layer | REQ-M-14, REQ-M-14a, REQ-M-17, REQ-M-17a | Batch POST, match response parsing, exponential backoff, 429 handling |
| 12 | Status bar | UI spec | Wire live data: connectivity, last detected, plates count, targets count |
| 13 | Debug overlay | REQ-M-18, REQ-M-19, REQ-M-20 | Bounding boxes, text, hash, FPS, debug image capture |
| 14 | Thermal mgmt | REQ-M-32 | ProcessInfo.thermalState observer, reduce FPS when throttled |
| 15 | Background/crash | REQ-M-50, REQ-M-51 | Stop capture on background, flush queue, resume on foreground |
| 16 | Privacy audit | REQ-M-40, REQ-M-41, REQ-M-43 | Verify no plaintext leaks in logs, no analytics SDKs, no image export |
| 17 | Push notifications | REQ-M-60, REQ-M-61, REQ-M-62, REQ-M-63 | UNUserNotificationCenter permission, APNs token registration, notification handling |

### Key Technical Notes

- **Frame processing**: Use `AVCaptureVideoDataOutputSampleBufferDelegate`. Process every Nth frame (skip frames to hit 10-15 fps detection) rather than every frame.
- **Core ML threading**: Run inference on a dedicated `DispatchQueue` to keep the camera preview smooth.
- **Memory**: Reuse `CVPixelBuffer` and avoid UIImage conversions in the hot path.
- **Pepper obfuscation**: Store as two `[UInt8]` arrays XOR'd together. Reconstruct at runtime: `zip(a, b).map(^)`.

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

Single-activity Jetpack Compose app. CameraX provides the preview and frame analysis. TFLite runs on a background thread via `ImageAnalysis.Analyzer`. Room database for the offline queue. MVVM with a `MainViewModel` coordinating the pipeline.

### Project Structure

```
android/app/src/main/java/com/cameras/app/
├── MainActivity.kt                      # Activity, landscape lock, permission requests, splash→camera flow
├── MainViewModel.kt                     # Pipeline state, counts, connectivity, coordinates
├── ui/
│   ├── CameraScreen.kt                  # Compose: camera preview + status bar (includes StatusBar, TestImagePreview composables)
│   ├── SplashScreen.kt                  # Splash screen with app name and Start Camera button
│   ├── DebugOverlay.kt                  # Bounding boxes, plate text, hash, FPS, detection feed
│   └── theme/                           # Material 3 theme, colors, typography
├── camera/
│   ├── CameraPreview.kt                 # Compose CameraX preview wrapper
│   ├── FrameAnalyzer.kt                 # ImageAnalysis.Analyzer → detect → OCR → hash → queue
│   └── TestFrameFeeder.kt              # Test mode: loads images, feeds them through analyzeBitmap() on a timer
├── detection/
│   ├── PlateDetector.kt                 # TFLite interpreter, YOLOv8-nano inference, NMS
│   └── PlateOCR.kt                      # ML Kit Text Recognition on cropped bitmaps
├── processing/
│   ├── PlateNormalizer.kt               # Uppercase, strip, validate
│   ├── PlateHasher.kt                   # javax.crypto.Mac HMAC-SHA256, pepper obfuscation
│   └── DeduplicationCache.kt            # Time-windowed set
├── network/
│   ├── ApiClient.kt                     # OkHttp/Retrofit, POST /api/v1/plates
│   ├── RetryManager.kt                  # Exponential backoff, 429 handling
│   └── ConnectivityMonitor.kt           # ConnectivityManager.NetworkCallback
├── persistence/
│   ├── OfflineQueueDatabase.kt          # Room database definition
│   ├── OfflineQueueDao.kt               # Insert, query oldest, delete, count
│   └── OfflineQueueEntry.kt             # Entity: hash, timestamp, latitude, longitude
├── location/
│   └── LocationProvider.kt              # FusedLocationProviderClient, permission handling
├── config/
│   └── AppConfig.kt                     # Confidence thresholds, batch size, server URL
└── assets/
    └── plate_detector.tflite            # YOLOv8-nano TFLite model (bundled)

android/app/src/main/
├── AndroidManifest.xml                  # Permissions: CAMERA, ACCESS_FINE_LOCATION, INTERNET

android/app/src/debug/
└── assets/
    └── test_images/                     # Test plate images for test mode (debug builds only)
```

### Implementation Order

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project setup | REQ-M-3, REQ-M-4, C-5 | Auto-rotation in manifest, permissions, min API 31 |
| 2 | Camera capture | REQ-M-1, REQ-M-2 | CameraX preview + ImageAnalysis, 1080p resolution |
| 3 | UI shell | REQ-M-3, UI spec | Compose: splash screen with Start Camera button → full-screen preview + status bar |
| 4 | Plate detection | REQ-M-5, REQ-M-6, REQ-M-7 | TFLite interpreter, YOLOv8-nano inference, NMS, confidence filter |
| 5 | OCR | REQ-M-9, REQ-M-10, REQ-M-11 | ML Kit on cropped bitmaps, normalization, validation |
| 6 | Hashing | REQ-M-12, REQ-M-13, REQ-M-42 | javax.crypto.Mac HMAC, pepper obfuscation, plaintext discard |
| 7 | Deduplication | REQ-M-8 | Time-windowed cache |
| 8 | Frame analyzer | REQ-M-30 | Wire pipeline in ImageAnalysis.Analyzer callback |
| 9 | Offline queue | REQ-M-15 | Room database, max 1000 entries, oldest eviction |
| 10 | Location | REQ-M-16 | FusedLocationProviderClient, permission flow, GPS warning |
| 11 | Network layer | REQ-M-14, REQ-M-14a, REQ-M-17, REQ-M-17a | OkHttp POST, batch, match parsing, backoff, 429 |
| 12 | Status bar | UI spec | Wire ViewModel state to Compose UI |
| 13 | Debug overlay | REQ-M-18, REQ-M-19, REQ-M-20 | Canvas overlay on preview, debug image capture |
| 14 | Thermal mgmt | REQ-M-32 | PowerManager thermal status listener, reduce analysis FPS |
| 15 | Background/crash | REQ-M-50, REQ-M-51 | Lifecycle-aware: stop analysis on STOPPED, flush queue, resume on STARTED |
| 16 | Privacy audit | REQ-M-40, REQ-M-41, REQ-M-43 | Verify no leaks, no analytics SDKs, ProGuard/R8 rules |
| 17 | Push notifications | REQ-M-60, REQ-M-61, REQ-M-62, REQ-M-63 | Firebase setup, FCM service, token registration, notification channel, POST_NOTIFICATIONS permission |

### Key Technical Notes

- **TFLite NMS**: YOLOv8 TFLite export does **not** include NMS. Must implement post-processing manually: filter by confidence → non-max suppression on bounding boxes.
- **CameraX frame skipping**: Use `ImageAnalysis.Builder().setBackpressureStrategy(STRATEGY_KEEP_ONLY_LATEST)` — automatically drops frames when the analyzer is busy.
- **Room threading**: Use `suspend` DAO functions with coroutines. Queue insert on the analyzer thread; batch reads on the network thread.
- **Pepper obfuscation**: Same XOR approach as iOS. Store as two `ByteArray` constants, reconstruct at runtime.

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
