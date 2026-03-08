# Implementation Todo

This file tracks the gap between **written specs** and **written code**. Every item here corresponds to a section of a spec's implementation plan. When an item is completed, check it off and note the commit or PR.

Items are ordered by dependency — earlier items unblock later ones. Within a component (server, iOS, Android), the order follows the implementation plan in each spec.

---

## YOLO Model Training

Spec: [`specs/mobile-app/license_plate_detection.md`](specs/mobile-app/license_plate_detection.md)

- [x] Create `models/training/` directory and `train.py` script
- [x] Download license plate dataset (HuggingFace, 8,823 images)
- [x] Train YOLOv8-nano (fine-tune from COCO pretrained weights)
- [x] Validate against quality gates (mAP@0.5 ≥ 0.80, recall ≥ 0.75)
- [x] Export to Core ML (`.mlpackage`) and TFLite (`.tflite`)
- [x] Copy model artifacts to iOS and Android asset directories
- [x] Create `models/Makefile` with build/export/deploy targets
- [x] Create `models/CHANGELOG.md` with v1 metrics (after training completes)

---

## Server (Go)

Spec: [`specs/server/spec.md`](specs/server/spec.md)

- [x] **Project scaffold** — `go mod init`, directory structure, `main.go` with flag parsing
- [x] **Config** — CLI flags (`--port`, `--plates-file`, `--pepper`, `--db-dsn`)
- [x] **Database** — PostgreSQL schema (`plates`, `sightings` tables), migrations, pgx driver (REQ-S-8)
- [x] **Target loader** — Load `plates.txt`, compute HMAC hashes, seed DB, build in-memory hash→plate_id map, SIGHUP reload with DB re-seed (REQ-S-5)
- [ ] **Hash matcher** — Constant-time comparison via `crypto/subtle`, return matched label (REQ-S-2)
- [x] **Sighting persistence** — Record matched plates to `sightings` table with plate_id, timestamp, GPS, hardware_id (REQ-S-3)
- [ ] **Rate limiter** — Token bucket per device_id, 429 + Retry-After response (REQ-S-6)
- [x] **POST /api/v1/plates** — Parse plate with timestamp and X-Device-ID header, validate, match, record sighting, return matched boolean (REQ-S-1, REQ-S-4)
- [x] **GET /healthz** — Status endpoint (REQ-S-7)
- [x] **Integration** — Wire handlers, DB init, graceful shutdown
- [x] **Tests** — Unit tests for handler, health; integration tests with mock recorder; DB integration tests for persistence
- [x] **Example seed file** — `testdata/test_plates.txt` with known plates for E2E testing

---

## iOS Mobile App (Swift)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — iOS

### Project Setup
- [x] **Landscape lock** — Set `UISupportedInterfaceOrientations` to landscape only + AppDelegate enforcement (REQ-M-4)
- [x] **Info.plist permissions** — Camera + location usage descriptions
- [x] **Min deployment target** — iOS 17.0 (exceeds C-5 requirement of iOS 16)

### Camera
- [x] **AVCaptureSession setup** — Rear camera, 1080p preset, video data output delegate (REQ-M-1, REQ-M-2)
- [x] **Camera preview** — UIViewRepresentable wrapping AVCaptureVideoPreviewLayer (REQ-M-3)
- [x] **Auto-start** — Begin capture on app launch without user interaction (REQ-M-3)

### UI
- [x] **Full-screen camera preview** — Landscape, camera fills screen
- [x] **Status bar** — Connectivity, last detected, plates count, targets count, GPS warning — wired to live pipeline state
- [x] **Wire live data** — StatusBarView connected to FrameProcessor, APIClient, ConnectivityMonitor, LocationManager

### Detection Pipeline
- [x] **Core ML model bundled** — plate_detector.mlpackage: YOLOv8-nano trained on license plate dataset, exported with NMS pipeline (5.9 MB)
- [x] **Core ML model loading** — PlateDetector.swift: compile `.mlpackage`, cache `VNCoreMLModel` at startup (REQ-M-5, REQ-M-6)
- [x] **Frame-to-inference bridge** — Extract `CVPixelBuffer` from `CMSampleBuffer`, `VNImageRequestHandler`, `VNCoreMLRequest` (REQ-M-6)
- [x] **Detection result parsing** — `VNRecognizedObjectObservation` bounding boxes, Vision→pixel coordinate conversion (REQ-M-6)
- [x] **Confidence threshold** — Filter detections below 0.7 (REQ-M-7)
- [x] **OCR** — PlateOCR.swift: Vision `VNRecognizeTextRequest` `.accurate` on cropped regions (REQ-M-9)
- [x] **OCR confidence filter** — Discard results below 0.6 (REQ-M-11)
- [x] **Plate normalization** — PlateNormalizer.swift: uppercase, strip, validate 2-8 chars (REQ-M-10)
- [x] **Deduplication** — DeduplicationCache.swift: 60-second time-windowed set (REQ-M-8)
- [x] **Frame processor** — FrameProcessor.swift: frame → detect → OCR → normalize → dedup → hash → queue (REQ-M-30)
- [x] **Build verification** — Full pipeline compiles and all 29 unit tests pass

### Hashing & Privacy
- [x] **HMAC-SHA256** — PlateHasher.swift: CryptoKit `HMAC<SHA256>`, XOR-obfuscated pepper (REQ-M-12, REQ-M-42)
- [x] **Plaintext discard** — Normalized text not stored after hashing, no logging (REQ-M-13, REQ-M-40)

### Persistence & Networking
- [x] **Offline queue** — OfflineQueue.swift: SQLite-backed FIFO, max 1000 entries, oldest eviction (REQ-M-15)
- [x] **Location services** — LocationManager.swift: CLLocationManager, GPS attach, "No GPS" warning (REQ-M-16)
- [x] **Batch upload** — APIClient.swift: URLSession POST, 10-plate or 30-second trigger (REQ-M-14)
- [x] **Match response handling** — Parse per-plate `matched` boolean, update target counter (REQ-M-14a)
- [x] **Retry logic** — RetryManager.swift: exponential backoff, max 10 retries (REQ-M-17)
- [x] **429 handling** — Read Retry-After header, pause uploads (REQ-M-17a)
- [x] **Connectivity monitor** — ConnectivityMonitor.swift: NWPathMonitor, flush queue on reconnect (REQ-M-14)

### Debug Mode
- [x] **Debug toggle** — Triple-tap gesture, `#if DEBUG` gated (REQ-M-18)
- [x] **Debug overlay** — DebugOverlayView.swift: bounding boxes, plate text, truncated hash, FPS, queue depth (REQ-M-19)
- [x] **Raw detection boxes** — Yellow bounding boxes for all PlateDetector results (pre-OCR) with confidence labels (DBG-1)
- [x] **Detection feed** — Right-side scrollable feed showing recent plates with QUEUED/SENT/MATCHED state (DBG-2, DBG-3)
- [ ] **Debug image capture** — Save to sandbox, delete on toggle off (REQ-M-20)

### Reliability & Performance
- [x] **Thermal management** — CameraManager observes `ProcessInfo.thermalState`, increases frame skip (REQ-M-32)
- [x] **Background behavior** — Stop capture + flush queue on background, resume on foreground (REQ-M-51)
- [x] **Crash recovery** — SQLite queue persists across restarts (REQ-M-50)
- [ ] **Memory audit** — Verify < 200 MB RAM, buffer reuse (REQ-M-31)
- [ ] **Privacy audit** — Verify no plaintext in logs, no analytics SDKs, no image export in production (REQ-M-40, REQ-M-41, REQ-M-43)

### App Store Distribution
- [x] **Fix orientation** — Changed to landscape per REQ-M-4 (AppDelegate + Info.plist)
- [ ] **App icon** — Add 1024×1024 PNG to `AppIcon.appiconset`
- [x] **Privacy manifest** — PrivacyInfo.xcprivacy declaring location data usage
- [x] **Location usage description** — Added `NSLocationWhenInUseUsageDescription` to build settings
- [ ] **Development team** — Set `DEVELOPMENT_TEAM` to Apple Team ID (requires Apple Developer account)
- [ ] **App Store Connect listing** — Screenshots, description, privacy policy URL, category, age rating
- [ ] **TestFlight build** — Archive and upload for beta testing

---

## Android Mobile App (Kotlin)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — Android

### Project Setup
- [x] **Landscape lock** — `android:screenOrientation="landscape"` in manifest (REQ-M-4)
- [x] **Manifest permissions** — CAMERA, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, INTERNET
- [x] **Min SDK** — API 28 / Android 9.0 (C-5)
- [x] **Dependencies** — CameraX, ML Kit, Room, OkHttp, TFLite, Play Services Location

### Camera
- [x] **CameraX setup** — Preview + ImageAnalysis use cases, 1080p, rear camera (REQ-M-1, REQ-M-2)
- [x] **Camera preview** — Compose `PreviewView` wrapper (REQ-M-3)
- [x] **Auto-start** — Begin capture on activity create (REQ-M-3)

### UI
- [x] **Full-screen camera preview** — Landscape Compose layout
- [x] **Status bar** — Connectivity, last detected, plates count, targets count, GPS warning — wired to live pipeline state
- [x] **Wire ViewModel** — MainViewModel with StateFlow, CameraScreen observes via collectAsState

### Detection Pipeline
- [x] **TFLite model loading** — Load `.tflite` from assets, create `Interpreter` with thread count options, allocate reusable input `ByteBuffer` (640×640×3×float32) and output tensor buffer (REQ-M-5, REQ-M-6)
- [x] **Frame-to-inference bridge** — Convert `ImageProxy` to `Bitmap`, resize to 640×640, normalize pixels to `[0,1]` float range, pack into reusable `ByteBuffer`, call `interpreter.run()` (REQ-M-6)
- [x] **Raw output parsing** — Parse `[1, 5, 8400]` tensor into per-candidate `[cx, cy, w, h, confidence]`, convert from center-format to corner-format `[x1, y1, x2, y2]`, scale from 640×640 model space to original bitmap coordinates (REQ-M-6)
- [x] **Post-processing / NMS** — Filter by confidence ≥ 0.7, apply greedy NMS with IoU threshold ~0.45 to suppress overlapping boxes (REQ-M-7)
- [x] **OCR** — ML Kit Text Recognition on cropped bitmaps (REQ-M-9)
- [x] **OCR confidence filter** — Discard results below 0.6 (REQ-M-11)
- [x] **Plate normalization** — Uppercase, strip, validate 2-8 chars (REQ-M-10)
- [x] **Deduplication** — 60-second time-windowed cache via DeduplicationCache (REQ-M-8)
- [x] **Frame analyzer** — FrameAnalyzer wired in ImageAnalysis.Analyzer, full pipeline via MainViewModel callback (REQ-M-30)

### Hashing & Privacy
- [x] **HMAC-SHA256** — `javax.crypto.Mac` with XOR-obfuscated pepper matching iOS (REQ-M-12, REQ-M-42)
- [x] **Plaintext discard** — Normalized text not stored after hashing, no logging (REQ-M-13, REQ-M-40)

### Persistence & Networking
- [x] **Offline queue** — Room database, max 1000 entries, oldest eviction (REQ-M-15)
- [x] **Location services** — FusedLocationProviderClient, GPS warning in status bar (REQ-M-16)
- [x] **Batch upload** — OkHttp POST, 10-plate or 30-second trigger (REQ-M-14)
- [x] **Match response handling** — Parse per-plate `matched` boolean, update target counter (REQ-M-14a)
- [x] **Retry logic** — Exponential backoff on failure (REQ-M-17)
- [x] **429 handling** — Read Retry-After, pause uploads (REQ-M-17a)
- [x] **Connectivity monitor** — ConnectivityManager.NetworkCallback, flush on reconnect (REQ-M-14)

### Debug Mode
- [x] **Debug toggle** — Triple-tap gesture, debug builds only via `BuildConfig.DEBUG` (REQ-M-18)
- [x] **Debug overlay** — DebugOverlay.kt: Canvas overlay with bounding boxes, text, hash, FPS, queue depth (REQ-M-19)
- [x] **Raw detection boxes** — Yellow bounding boxes for all PlateDetector results (pre-OCR) with confidence labels (DBG-1)
- [x] **Detection feed** — Right-side scrollable feed showing recent plates with QUEUED/SENT/MATCHED state (DBG-2, DBG-3)
- [ ] **Debug image capture** — Save to app-internal storage, delete on toggle off (REQ-M-20)

### Reliability & Performance
- [x] **Thermal management** — PowerManager thermal status listener, reduce frame skip count (REQ-M-32)
- [x] **Background behavior** — Lifecycle-aware: stop on STOPPED, resume on STARTED via LifecycleEventObserver (REQ-M-51)
- [x] **Crash recovery** — Room queue persists across process death (REQ-M-50)
- [ ] **Memory audit** — Verify < 200 MB, bitmap recycling (REQ-M-31)
- [ ] **Privacy audit** — No plaintext leaks, no analytics, ProGuard rules (REQ-M-40, REQ-M-41, REQ-M-43)
