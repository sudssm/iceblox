# Mobile App Specification

## Purpose

A dashboard-mounted mobile app for private security and community watch that continuously detects and reads license plates using the device camera, hashes the plate text on-device, and sends hashes to a server for comparison. No plaintext plate data or images ever leave the device in production mode.

## Environment

- **Mounting**: Dashboard-mounted, landscape orientation, rear camera facing forward through windshield
- **Power**: Assumed connected to car power (USB/12V) — battery optimization is secondary to performance
- **Connectivity**: Intermittent — app must handle offline periods gracefully
- **Lighting**: Variable — daylight, night (headlights/streetlights), rain, glare

---

## Functional Requirements

### Camera Capture

#### REQ-M-1: Continuous Camera Capture

The app MUST continuously capture frames from the rear-facing camera at a minimum of 15 fps for processing. The camera preview MUST be displayed on screen in landscape orientation.

#### REQ-M-2: Camera Resolution

The app MUST use a resolution sufficient for plate detection at distances of 3–20 meters. A minimum of 1080p capture resolution is REQUIRED. The app MAY downscale frames for the detection model while keeping full resolution available for OCR crops.

#### REQ-M-3: Auto-Start

When the app is opened, it MUST immediately begin camera capture and plate detection without requiring user interaction.

#### REQ-M-4: Camera Orientation Lock

The app MUST lock to landscape orientation. It MUST NOT rotate to portrait.

### License Plate Detection

#### REQ-M-5: On-Device Plate Detection

The app MUST use an on-device ML model to detect license plate regions in camera frames. Detection MUST NOT require network connectivity.

#### REQ-M-6: Detection Model

The app MUST use a **YOLOv8-nano** model for license plate detection, converted to platform-native formats:
- **iOS**: Core ML (`.mlmodel` converted via `coremltools`)
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

### Primary Screen (Landscape Only)

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
| Plate detection | Core ML (YOLOv8-nano `.mlmodel`) |
| OCR | Vision (`VNRecognizeTextRequest`) |
| Hashing | CryptoKit (`HMAC<SHA256>`) |
| Pepper storage | Build-time constant (obfuscated) |
| Local database | Core Data or SQLite (for offline queue) |
| Networking | URLSession |

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

---

## Constraints

- C-1: No network calls except to the configured server endpoint
- C-2: No user accounts or authentication in v1. `device_id` is the hardware identifier (`identifierForVendor` on iOS, `Settings.Secure.ANDROID_ID` on Android)
- C-3: The app does not receive the target plate list. It learns only whether individual submitted plates matched (boolean per plate in server response)
- C-4: The ML detection model must be bundled with the app (no model downloads)
- C-5: Minimum deployment targets: iOS 16+ / Android API 31+ (Android 12)

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
| Training data (Phase 1) | Roboflow US-EU (350 images) + augmentation, fine-tuned from COCO |
| Targets counter styling | No special color treatment |

## Open Questions

None — all questions resolved. See `Resolved Decisions` above.

## Related Specs

- [`license_plate_detection.md`](./license_plate_detection.md) — Phase 1 model training data, pipeline, and validation criteria
- [`../../future/yolo_model_improvements.md`](../../future/yolo_model_improvements.md) — Phase 2 (expanded data) and Phase 3 (custom collection) plans
