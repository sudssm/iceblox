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

- [x] **Project scaffold** — `go mod init`, directory structure, `main.go` with flag parsing
- [x] **Config** — CLI flags (`--port`, `--log-file`)
- [ ] **Target loader** — Load seed JSON at startup, in-memory hash set, SIGHUP reload (REQ-S-5)
- [ ] **Hash matcher** — Constant-time comparison via `crypto/subtle`, return matched label (REQ-S-2)
- [x] **JSONL logger** — Append plate submissions to file (REQ-S-3)
- [ ] **Rate limiter** — Token bucket per device_id, 429 + Retry-After response (REQ-S-6)
- [x] **POST /api/v1/plates** — Parse single plate, validate, log, return ok (REQ-S-1)
- [x] **GET /healthz** — Status endpoint (REQ-S-7)
- [x] **Integration** — Wire handlers, graceful shutdown
- [x] **Tests** — Unit tests for handler, logger, health; end-to-end smoke test
- [ ] **Example seed file** — `targets.json` with sample hashed plates for testing

---

## iOS Mobile App (Swift)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — iOS

### Project Setup
- [x] **Portrait lock** — Set `UISupportedInterfaceOrientations` to portrait only + AppDelegate enforcement
- [x] **Info.plist permissions** — Camera usage description (location usage description pending)
- [x] **Min deployment target** — iOS 17.0 (exceeds C-5 requirement of iOS 16)

### Camera
- [x] **AVCaptureSession setup** — Rear camera, 1080p preset, video data output delegate (REQ-M-1, REQ-M-2)
- [x] **Camera preview** — UIViewRepresentable wrapping AVCaptureVideoPreviewLayer (REQ-M-3)
- [x] **Auto-start** — Begin capture on app launch without user interaction (REQ-M-3)

### UI
- [x] **Full-screen camera preview** — Portrait, camera fills screen
- [x] **Status bar** — Connectivity, last detected, plates count, targets count (always visible, placeholder values)
- [ ] **Wire live data** — Connect status bar to real pipeline state

### Detection Pipeline
- [x] **Core ML model loading** — Compile `.mlmodel`, create and cache `VNCoreMLModel` instance at startup (REQ-M-5, REQ-M-6)
- [x] **Frame-to-inference bridge** — Extract `CVPixelBuffer` from `CMSampleBuffer`, create `VNImageRequestHandler`, run `VNCoreMLRequest` on a dedicated serial queue (REQ-M-6). NMS is baked into the Core ML export — no manual implementation needed
- [x] **Detection result parsing** — Extract `VNRecognizedObjectObservation` bounding boxes, convert Vision coordinates (bottom-left origin, normalized) to pixel coordinates for cropping (REQ-M-6)
- [x] **Confidence threshold** — Filter detections with `confidence` below 0.7 (REQ-M-7)
- [x] **OCR** — Vision `VNRecognizeTextRequest` on cropped plate regions (REQ-M-9)
- [x] **OCR confidence filter** — Discard results below 0.6 (REQ-M-11)
- [x] **Plate normalization** — Uppercase, strip, validate 2-8 chars (REQ-M-10)
- [ ] **Deduplication** — 60-second time-windowed cache (REQ-M-8)
- [x] **Frame processor** — Wire full pipeline: frame → detect → OCR → normalize → dedup → hash → queue (REQ-M-30)

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
- [x] **Background behavior** — Stop capture on background, resume on foreground (REQ-M-51, queue flush pending)
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
- [ ] **Dependencies** — ~~CameraX~~ done, ~~ML Kit~~ done, ~~TFLite~~ done, Room, OkHttp still needed

### Camera
- [x] **CameraX setup** — Preview + ImageAnalysis use cases, 1080p, rear camera (REQ-M-1, REQ-M-2)
- [x] **Camera preview** — Compose `PreviewView` wrapper (REQ-M-3)
- [x] **Auto-start** — Begin capture on activity create (REQ-M-3)

### UI
- [x] **Full-screen camera preview** — Landscape Compose layout
- [x] **Status bar** — Capture status and frame count (placeholder; connectivity, plates, targets pending)
- [ ] **Wire ViewModel** — Connect status bar to pipeline state via StateFlow

### Detection Pipeline
- [x] **TFLite model loading** — Load `.tflite` from assets, create `Interpreter` with thread count options, allocate reusable input `ByteBuffer` (640×640×3×float32) and output tensor buffer (REQ-M-5, REQ-M-6)
- [x] **Frame-to-inference bridge** — Convert `ImageProxy` to `Bitmap`, resize to 640×640, normalize pixels to `[0,1]` float range, pack into reusable `ByteBuffer`, call `interpreter.run()` (REQ-M-6)
- [x] **Raw output parsing** — Parse `[1, 5, 8400]` tensor into per-candidate `[cx, cy, w, h, confidence]`, convert from center-format to corner-format `[x1, y1, x2, y2]`, scale from 640×640 model space to original bitmap coordinates (REQ-M-6)
- [x] **Post-processing / NMS** — Filter by confidence ≥ 0.7, apply greedy NMS with IoU threshold ~0.45 to suppress overlapping boxes (REQ-M-7). TFLite export does NOT include NMS — this must be implemented manually (unlike iOS Core ML)
- [x] **OCR** — ML Kit Text Recognition on cropped bitmaps (REQ-M-9)
- [x] **OCR confidence filter** — Discard results below 0.6 (REQ-M-11)
- [x] **Plate normalization** — Uppercase, strip, validate 2-8 chars (REQ-M-10)
- [ ] **Deduplication** — 60-second time-windowed cache (REQ-M-8)
- [x] **Frame analyzer** — Wire pipeline in ImageAnalysis.Analyzer (REQ-M-30)

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
