# Implementation Todo

This file tracks the gap between **written specs** and **written code**. Every item here corresponds to a section of a spec's implementation plan. When an item is completed, check it off and note the commit or PR.

Items are ordered by dependency — earlier items unblock later ones. Within a component (server, iOS, Android), the order follows the implementation plan in each spec.

---

## YOLO Model Training

Spec: [`specs/mobile-app/license_plate_detection.md`](specs/mobile-app/license_plate_detection.md)

- [ ] Create `models/training/` directory and `train.py` script
- [ ] Download Roboflow US-EU license plate dataset
- [ ] Train YOLOv8-nano (fine-tune from COCO pretrained weights)
- [ ] Validate against quality gates (mAP@0.5 ≥ 0.80, recall ≥ 0.75)
- [ ] Export to Core ML (`.mlmodel`) and TFLite (`.tflite`)
- [ ] Copy model artifacts to iOS and Android asset directories
- [ ] Create `models/CHANGELOG.md` with v1 metrics

---

## Server (Go)

Spec: [`specs/server/spec.md`](specs/server/spec.md)

- [ ] **Project scaffold** — `go mod init`, directory structure, `main.go` with flag parsing
- [ ] **Config** — CLI flags (`--port`, `--targets-file`, `--log-file`), env var overrides
- [ ] **Target loader** — Load seed JSON at startup, in-memory hash set, SIGHUP reload (REQ-S-5)
- [ ] **Hash matcher** — Constant-time comparison via `crypto/subtle`, return matched label (REQ-S-2)
- [ ] **JSONL logger** — Append match entries to file, periodic non-match count to stdout (REQ-S-3)
- [ ] **Rate limiter** — Token bucket per device_id, 429 + Retry-After response (REQ-S-6)
- [ ] **POST /api/v1/plates** — Parse batch, validate, call matcher, build response (REQ-S-1, REQ-S-4)
- [ ] **GET /healthz** — Status + targets_loaded count (REQ-S-7)
- [ ] **Integration** — Wire handlers, TLS config, graceful shutdown
- [ ] **Tests** — Unit tests per package, integration test with seed file + HTTP requests
- [ ] **Example seed file** — `targets.json` with sample hashed plates for testing

---

## iOS Mobile App (Swift)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — iOS

### Project Setup
- [ ] **Landscape lock** — Set `UISupportedInterfaceOrientations` to landscape only (REQ-M-4)
- [ ] **Info.plist permissions** — Camera usage description, location usage description
- [ ] **Min deployment target** — iOS 16 (C-5)

### Camera
- [ ] **AVCaptureSession setup** — Rear camera, 1080p preset, video data output delegate (REQ-M-1, REQ-M-2)
- [ ] **Camera preview** — UIViewRepresentable wrapping AVCaptureVideoPreviewLayer (REQ-M-3)
- [ ] **Auto-start** — Begin capture on app launch without user interaction (REQ-M-3)

### UI
- [ ] **Full-screen camera preview** — Landscape, camera fills screen
- [ ] **Status bar** — Connectivity, last detected, plates count, targets count (always visible)
- [ ] **Wire live data** — Connect status bar to real pipeline state

### Detection Pipeline
- [ ] **Core ML model integration** — Load YOLOv8-nano `.mlmodel`, run inference on frames (REQ-M-5, REQ-M-6)
- [ ] **Confidence threshold** — Filter detections below 0.7 (REQ-M-7)
- [ ] **OCR** — Vision `VNRecognizeTextRequest` on cropped plate regions (REQ-M-9)
- [ ] **OCR confidence filter** — Discard results below 0.6 (REQ-M-11)
- [ ] **Plate normalization** — Uppercase, strip, validate 2-8 chars (REQ-M-10)
- [ ] **Deduplication** — 60-second time-windowed cache (REQ-M-8)
- [ ] **Frame processor** — Wire full pipeline: frame → detect → OCR → normalize → dedup → hash → queue (REQ-M-30)

### Hashing & Privacy
- [ ] **HMAC-SHA256** — CryptoKit `HMAC<SHA256>`, obfuscated pepper (REQ-M-12, REQ-M-42)
- [ ] **Plaintext discard** — Zero out plate text after hashing, no logging (REQ-M-13, REQ-M-40)

### Persistence & Networking
- [ ] **Offline queue** — SQLite-backed FIFO, max 1000 entries, oldest eviction (REQ-M-15)
- [ ] **Location services** — CLLocationManager, attach GPS to each entry, "No GPS" warning (REQ-M-16)
- [ ] **Batch upload** — URLSession POST, 10-plate or 30-second trigger (REQ-M-14)
- [ ] **Match response handling** — Parse per-plate boolean, update target counter (REQ-M-14a)
- [ ] **Retry logic** — Exponential backoff on failure (REQ-M-17)
- [ ] **429 handling** — Read Retry-After, pause uploads (REQ-M-17a)
- [ ] **Connectivity monitor** — NWPathMonitor, flush queue on reconnect (REQ-M-14)

### Debug Mode
- [ ] **Debug toggle** — Triple-tap gesture, debug builds only (REQ-M-18)
- [ ] **Debug overlay** — Bounding boxes, plate text, truncated hash, FPS, queue depth (REQ-M-19)
- [ ] **Debug image capture** — Save to sandbox, delete on toggle off (REQ-M-20)

### Reliability & Performance
- [ ] **Thermal management** — Monitor `ProcessInfo.thermalState`, reduce FPS when throttled (REQ-M-32)
- [ ] **Background behavior** — Stop capture on background, flush queue, resume on foreground (REQ-M-51)
- [ ] **Crash recovery** — Queue persists across restarts (REQ-M-50)
- [ ] **Memory audit** — Verify < 200 MB RAM, buffer reuse (REQ-M-31)
- [ ] **Privacy audit** — No plaintext in logs, no analytics SDKs, no image export in production (REQ-M-40, REQ-M-41, REQ-M-43)

---

## Android Mobile App (Kotlin)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — Android

### Project Setup
- [x] **Landscape lock** — `android:screenOrientation="landscape"` in manifest (REQ-M-4)
- [x] **Manifest permissions** — CAMERA (ACCESS_FINE_LOCATION, INTERNET still pending)
- [x] **Min SDK** — API 28 / Android 9.0 (C-5)
- [ ] **Dependencies** — ~~CameraX~~ done, ML Kit, Room, OkHttp, TFLite still needed

### Camera
- [x] **CameraX setup** — Preview + ImageAnalysis use cases, 1080p, rear camera (REQ-M-1, REQ-M-2)
- [x] **Camera preview** — Compose `PreviewView` wrapper (REQ-M-3)
- [x] **Auto-start** — Begin capture on activity create (REQ-M-3)

### UI
- [x] **Full-screen camera preview** — Landscape Compose layout
- [x] **Status bar** — Capture status and frame count (placeholder; connectivity, plates, targets pending)
- [ ] **Wire ViewModel** — Connect status bar to pipeline state via StateFlow

### Detection Pipeline
- [ ] **TFLite model integration** — Load YOLOv8-nano `.tflite`, run inference in Analyzer (REQ-M-5, REQ-M-6)
- [ ] **Post-processing / NMS** — Bounding box extraction, non-max suppression, confidence filter (REQ-M-7)
- [ ] **OCR** — ML Kit Text Recognition on cropped bitmaps (REQ-M-9)
- [ ] **OCR confidence filter** — Discard results below 0.6 (REQ-M-11)
- [ ] **Plate normalization** — Uppercase, strip, validate 2-8 chars (REQ-M-10)
- [ ] **Deduplication** — 60-second time-windowed cache (REQ-M-8)
- [ ] **Frame analyzer** — Wire pipeline in ImageAnalysis.Analyzer (REQ-M-30)

### Hashing & Privacy
- [ ] **HMAC-SHA256** — `javax.crypto.Mac`, obfuscated pepper (REQ-M-12, REQ-M-42)
- [ ] **Plaintext discard** — Zero out plate text after hashing, no logging (REQ-M-13, REQ-M-40)

### Persistence & Networking
- [ ] **Offline queue** — Room database, max 1000 entries, oldest eviction (REQ-M-15)
- [ ] **Location services** — FusedLocationProviderClient, GPS warning (REQ-M-16)
- [ ] **Batch upload** — OkHttp POST, 10-plate or 30-second trigger (REQ-M-14)
- [ ] **Match response handling** — Parse per-plate boolean, update target counter (REQ-M-14a)
- [ ] **Retry logic** — Exponential backoff on failure (REQ-M-17)
- [ ] **429 handling** — Read Retry-After, pause uploads (REQ-M-17a)
- [ ] **Connectivity monitor** — ConnectivityManager.NetworkCallback, flush on reconnect (REQ-M-14)

### Debug Mode
- [ ] **Debug toggle** — Triple-tap gesture, debug builds only via `BuildConfig.DEBUG` (REQ-M-18)
- [ ] **Debug overlay** — Canvas overlay with bounding boxes, text, hash, FPS (REQ-M-19)
- [ ] **Debug image capture** — Save to app-internal storage, delete on toggle off (REQ-M-20)

### Reliability & Performance
- [ ] **Thermal management** — PowerManager thermal status listener, reduce FPS (REQ-M-32)
- [ ] **Background behavior** — Lifecycle-aware: stop on STOPPED, resume on STARTED (REQ-M-51)
- [ ] **Crash recovery** — Room queue persists across process death (REQ-M-50)
- [ ] **Memory audit** — Verify < 200 MB, bitmap recycling (REQ-M-31)
- [ ] **Privacy audit** — No plaintext leaks, no analytics, ProGuard rules (REQ-M-40, REQ-M-41, REQ-M-43)
