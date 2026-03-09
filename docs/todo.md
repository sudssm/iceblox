# Implementation Todo

This file tracks the gap between **written specs** and **written code**. Every item here corresponds to a section of a spec's implementation plan. When an item is completed, check it off and note the commit or PR.

Items are ordered by dependency — earlier items unblock later ones. Within a component (server, iOS, Android), the order follows the implementation plan in each spec.

---

## YOLO Model Training

Spec: [`specs/mobile-app/license_plate_detection.md`](specs/mobile-app/license_plate_detection.md)

- [x] Download license plate dataset (HuggingFace, 8,823 images)
- [x] Train YOLOv8-nano (fine-tune from COCO pretrained weights)
- [x] Validate against quality gates (mAP@0.5 ≥ 0.80, recall ≥ 0.75)
- [x] Create `models/CHANGELOG.md` with v1 metrics (after training completes)

---

## Server (Go)

Spec: [`specs/server/spec.md`](specs/server/spec.md)

- [ ] **Hash matcher** — Constant-time comparison via `crypto/subtle`, return matched label (REQ-S-2). Currently uses O(1) map lookup which is not timing-attack resistant.
- [ ] **Rate limiter** — Token bucket per device_id, 429 + Retry-After response (REQ-S-6). Not yet implemented.
- [x] **Device token store** — `device_tokens` table, CRUD operations in `db.go` (REQ-S-9)
- [x] **POST /api/v1/devices** — Device token registration endpoint with upsert (REQ-S-9)
- [x] **APNs client** — HTTP/2 push provider, ES256 JWT signing, `.p8` key loading, token caching (REQ-S-11)
- [x] **FCM client** — HTTP v1 API, RS256 JWT → OAuth2 token exchange, token caching (REQ-S-12)
- [x] **Push notifier** — Dispatch notifications to all registered devices on match, async goroutine, stale token cleanup (REQ-S-10)

---

## iOS Mobile App (Swift)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — iOS

### Project Setup
- [x] **Landscape lock** — Set `UISupportedInterfaceOrientations` to landscape only + AppDelegate enforcement (REQ-M-4)
- [x] **Keep screen on** — `isIdleTimerDisabled = true` in ContentView `onAppear` (REQ-M-4a)
- [x] **Info.plist permissions** — Camera + location usage descriptions
- [x] **Min deployment target** — iOS 17.0 (exceeds C-5 requirement of iOS 16)

### Camera
- [x] **AVCaptureSession setup** — Rear camera, 1080p preset, video data output delegate (REQ-M-1, REQ-M-2)
- [x] **Camera preview** — UIViewRepresentable wrapping AVCaptureVideoPreviewLayer (REQ-M-3)
- [x] **Splash screen** — SplashScreenView with app name and Start Camera button; camera starts on tap (REQ-M-3)

### UI
- [x] **Full-screen camera preview** — Landscape, camera fills screen
- [x] **Status bar** — Connectivity, last detected, plates count, targets count, GPS warning — wired to live pipeline state
- [x] **Wire live data** — StatusBarView connected to FrameProcessor, APIClient, ConnectivityMonitor, LocationManager
- [x] **Recording session state** — Session lifecycle with per-session timestamps and counters, managed in ContentView.swift (REQ-M-3a, REQ-M-3d)
- [x] **Stop Recording button** — Persistent bottom-center control (above status bar) that halts new detections immediately (REQ-M-3b)
- [x] **Session summary sheet** — Show plates seen, ICE vehicles identified, duration, and pending-sync note after stop (REQ-M-3c, REQ-M-14b)

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
- [x] **Batch upload** — APIClient.swift: URLSession POST, 10-plate or 30-second trigger, sends device timestamp in ISO 8601 (REQ-M-14)
- [x] **Match response handling** — Parse per-plate `matched` boolean, update target counter (REQ-M-14a)
- [x] **Session attribution metadata** — Persist local session identifiers with queued hashes and route late match responses to the originating session (REQ-M-14a, REQ-M-15a)
- [x] **Final flush on stop** — Trigger immediate upload attempt when user ends a session and surface provisional stats if uploads remain pending (REQ-M-14b)
- [x] **Retry logic** — RetryManager.swift: exponential backoff, max 10 retries (REQ-M-17)
- [x] **429 handling** — Read Retry-After header, pause uploads (REQ-M-17a)
- [x] **Connectivity monitor** — ConnectivityMonitor.swift: NWPathMonitor, flush queue on reconnect (REQ-M-14)
- [x] **Plate normalization ASCII filter** — Added `.isASCII` filter to match overview spec and Android (REQ-M-10)

### Debug Mode
- [x] **Debug toggle** — Triple-tap gesture, `#if DEBUG` gated (REQ-M-18)
- [x] **Debug overlay** — DebugOverlayView.swift: bounding boxes, plate text, truncated hash, FPS, queue depth (REQ-M-19)
- [x] **Raw detection boxes** — Yellow bounding boxes for all PlateDetector results (pre-OCR) with confidence labels (DBG-1)
- [x] **Detection feed** — Right-side scrollable feed showing recent plates with QUEUED/SENT/MATCHED state (DBG-2, DBG-3)
- [x] **Debug log panel** — Translucent log panel at bottom of overlay showing DebugLog entries, color-coded by level, auto-scrolling (DBG-4)
- [ ] **Debug image capture** — Save to sandbox, delete on toggle off (REQ-M-20)

### Push Notifications
- [x] **Notification permission** — Request via `UNUserNotificationCenter`, register for remote notifications (REQ-M-60)
- [x] **APNs token registration** — Convert device token to hex string, POST to `/api/v1/devices` (REQ-M-61)
- [x] **Notification handling** — `UNUserNotificationCenterDelegate`, foreground banner display (REQ-M-62)

- [ ] **Memory audit** — Verify < 200 MB RAM, buffer reuse (REQ-M-31)
- [ ] **Privacy audit** — Verify no plaintext in logs, no analytics SDKs, no image export in production (REQ-M-40, REQ-M-41, REQ-M-43)
- [ ] **App icon** — Add 1024×1024 PNG to `AppIcon.appiconset`
- [ ] **Development team** — Set `DEVELOPMENT_TEAM` to Apple Team ID (requires Apple Developer account)
- [ ] **App Store Connect listing** — Screenshots, description, privacy policy URL, category, age rating
- [ ] **TestFlight build** — Archive and upload for beta testing

---

## Android Mobile App (Kotlin)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — Android

### Project Setup
- [x] **Landscape lock** — `android:screenOrientation="landscape"` in manifest (REQ-M-4)
- [x] **Keep screen on** — `FLAG_KEEP_SCREEN_ON` in MainActivity `onCreate` (REQ-M-4a)
- [x] **Manifest permissions** — CAMERA, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, INTERNET, POST_NOTIFICATIONS
- [x] **Min SDK** — API 28 / Android 9.0 (C-5)
- [x] **Dependencies** — CameraX, ML Kit, Room, OkHttp, TFLite, Play Services Location, Firebase Messaging

### Camera
- [x] **CameraX setup** — Preview + ImageAnalysis use cases, 1080p, rear camera (REQ-M-1, REQ-M-2)
- [x] **Camera preview** — Compose `PreviewView` wrapper (REQ-M-3)
- [x] **Splash screen** — SplashScreen composable with app name and Start Camera button; camera starts on tap (REQ-M-3)

### UI
- [x] **Full-screen camera preview** — Landscape Compose layout
- [x] **Status bar** — Connectivity, last detected, plates count, targets count, GPS warning — wired to live pipeline state
- [x] **Wire ViewModel** — MainViewModel with StateFlow, CameraScreen observes via collectAsState
- [x] **Recording session state** — Session lifecycle with per-session timestamps and counters, managed in MainViewModel.kt (REQ-M-3a, REQ-M-3d)
- [x] **Stop Recording button** — Persistent bottom-center control (above status bar) that halts new detections immediately (REQ-M-3b)
- [x] **Session summary dialog** — Show plates seen, ICE vehicles identified, duration, and pending-sync note after stop (REQ-M-3c, REQ-M-14b)

### Detection Pipeline
- [x] **TFLite model loading** — Load `.tflite` from assets, create `Interpreter` with thread count options, allocate reusable input `ByteBuffer` (640×640×3×float32) and output tensor buffer (REQ-M-5, REQ-M-6)
- [x] **Frame-to-inference bridge** — Convert `ImageProxy` to `Bitmap`, resize to 640×640, normalize pixels to `[0,1]` float range, pack into reusable `ByteBuffer`, call `interpreter.run()` (REQ-M-6)
- [x] **Raw output parsing** — Parse `[1, N, 8400]` tensor (N=5 for trained plate model, N=84 for COCO placeholder) into per-candidate detections, convert from center-format to corner-format `[x1, y1, x2, y2]`, scale from 640×640 model space to original bitmap coordinates. Channel count auto-detected from model at init. (REQ-M-6)
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
- [x] **Batch upload** — OkHttp POST, 10-plate or 30-second trigger, sends device timestamp in ISO 8601 (REQ-M-14)
- [x] **Match response handling** — Parse per-plate `matched` boolean, update target counter (REQ-M-14a)
- [x] **Session attribution metadata** — Persist local session identifiers with queued hashes and route late match responses to the originating session (REQ-M-14a, REQ-M-15a)
- [x] **Final flush on stop** — Trigger immediate upload attempt when user ends a session and surface provisional stats if uploads remain pending (REQ-M-14b)
- [x] **Retry logic** — Exponential backoff on failure (REQ-M-17)
- [x] **429 handling** — Read Retry-After, pause uploads (REQ-M-17a)
- [x] **Connectivity monitor** — ConnectivityManager.NetworkCallback, flush on reconnect (REQ-M-14)

### Debug Mode
- [x] **Debug toggle** — Triple-tap gesture, debug builds only via `BuildConfig.DEBUG` (REQ-M-18)
- [x] **Debug overlay** — DebugOverlay.kt: Canvas overlay with bounding boxes, text, hash, FPS, queue depth (REQ-M-19)
- [x] **Raw detection boxes** — Yellow bounding boxes for all PlateDetector results (pre-OCR) with confidence labels (DBG-1)
- [x] **Detection feed** — Right-side scrollable feed showing recent plates with QUEUED/SENT/MATCHED state (DBG-2, DBG-3)
- [x] **Debug log panel** — Translucent log panel at bottom of overlay showing DebugLog entries, color-coded by level, auto-scrolling (DBG-4)
- [ ] **Debug image capture** — Save to app-internal storage, delete on toggle off (REQ-M-20)

### Push Notifications
- [x] **Firebase setup** — Add FCM dependency, `google-services.json`, notification channel (REQ-M-60)
- [x] **POST_NOTIFICATIONS permission** — Runtime permission request for Android 13+ (REQ-M-60)
- [x] **FCM token registration** — Send token to server via POST `/api/v1/devices`, handle `onNewToken` (REQ-M-61)
- [x] **Notification service** — `FirebaseMessagingService` subclass, build and display notifications (REQ-M-62)

### Rename
- [x] **Rename to IceBlox everywhere** — Update iOS bundle ID, server references, specs, and any remaining legacy branding references to use IceBlox branding

### Test Mode
- [x] **Test mode intent extra** — `test_mode` boolean extra bypasses camera permission, splash screen shown normally (TS-33)
- [x] **TestFrameFeeder** — Loads images from `src/debug/assets/test_images/` and `filesDir/test_images/`, feeds through `analyzeBitmap()` on 500ms timer (TS-34)
- [x] **Test mode UI** — `TestImagePreview` composable replaces camera preview, `[TEST MODE]` banner shown (TS-35)
- [x] **test_mode.sh script** — Installs APK, optionally pushes images via `--push-dir`, launches with test_mode extra

- [ ] **Memory audit** — Verify < 200 MB, bitmap recycling (REQ-M-31)
- [ ] **Privacy audit** — No plaintext leaks, no analytics, ProGuard rules (REQ-M-40, REQ-M-41, REQ-M-43)

---

## E2E Testing

Spec: [`specs/testing.md`](specs/testing.md) → E2E Testing, [`specs/mobile-app/test-scenarios.md`](specs/mobile-app/test-scenarios.md) → E2E Tests

### Android

- [x] **Directory structure** — `e2e/android/` with orchestrator, config, lib/, tests/, fixtures/
- [x] **Infrastructure lifecycle** — Ephemeral postgres + Go server with test plates (TS-E2E-1, TS-E2E-2)
- [x] **App lifecycle** — Build, install, push images, launch in test mode via `--ez test_mode true`
- [x] **DB verification** — `docker exec psql` queries for sighting assertions
- [x] **`analyzeBitmap()` fallback param** — `useFallback` parameter so no-plate test works correctly
- [x] **Fixture images** — Real images added: `no_plate/no_plate.png`, `non_target_plate/non_target.jpg`, `target_plate/target.jpg`
- [x] **No-plate test scenario** — Verified zero sightings with no-plate image (TS-E2E-1).
- [x] **Non-target plate test scenario** — Verified zero sightings with non-target plate image (TS-E2E-2).
- [x] **Target plate test scenario** — Verified matched sighting with target plate image (TS-E2E-3).
- [x] **Stop recording summary scenario** — Verified the target-plate flow can stop the active session and show session summary stats (TS-E2E-8).
- [x] **iOS stop recording summary scenario** — Verified the simulator stop trigger writes a session summary artifact after a target-plate session (TS-E2E-9).
- [ ] **CI integration** — Run E2E tests in GitHub Actions with emulator + Docker

---

## Proximity Alerts

Spec: [`specs/server/spec.md`](specs/server/spec.md) REQ-S-13 through REQ-S-16, [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) REQ-M-64 through REQ-M-68

### Server

- [x] **Geo package** — Haversine distance calculation + bounding box utility, pure functions (REQ-S-15)
- [x] **Subscriber store** — In-memory subscriber location storage with 1-hour TTL and cleanup (REQ-S-14)
- [x] **Recent sightings query** — DB method with bounding-box SQL pre-filter, `Sighting` struct, composite geo index (REQ-S-15)
- [x] **Subscribe handler** — `POST /api/v1/subscribe` endpoint: validate, store subscriber, query+filter sightings, respond (REQ-S-13)
- [x] **Proximity fan-out** — Enhance push dispatch with subscriber location filtering via haversine (REQ-S-16)
- [x] **Wire in main.go** — Subscriber store init, subscribe handler registration, notifier wiring

### iOS

- [x] **AlertClient** — Subscribe endpoint client with 10-minute timer, GPS truncation to 2 decimal places (REQ-M-64, REQ-M-65, REQ-M-66)
- [x] **Recent sightings handling** — Parse `recent_sightings` response, log to DebugLog, increment counter (REQ-M-67)
- [x] **Lifecycle integration** — Start timer on active, subscribe+stop on background to refresh TTL (REQ-M-64, REQ-M-68)
- [x] **AppConfig** — Add `subscribeEndpoint`, `subscribeIntervalSeconds`, `defaultRadiusMiles` constants

### Android

- [x] **AlertClient** — Subscribe endpoint client with coroutine timer (600s delay), GPS truncation (REQ-M-64, REQ-M-65, REQ-M-66)
- [x] **Recent sightings handling** — Parse `recent_sightings` response, log to DebugLog, increment counter (REQ-M-67)
- [x] **Lifecycle integration** — Start/stop with pipeline lifecycle, subscribe on stop to refresh TTL (REQ-M-64, REQ-M-68)
- [x] **AppConfig** — Add `SUBSCRIBE_ENDPOINT`, `SUBSCRIBE_INTERVAL_MS`, `DEFAULT_RADIUS_MILES` constants

---

## Future

- [ ] **Investigate backgrounding iOS** — Revisit whether any App Store-safe, user-visible iOS mode can relax the foreground-only camera requirement without violating Apple's background camera restrictions.

---

## Productionizing

- [ ] **Change the pepper** — Replace `default-pepper-change-me` with a secure random value (`openssl rand -hex 32`). Update server env var (`PEPPER`), iOS `PlateHasher.swift` pepperPartA/B, and Android `PlateHasher.kt` pepperPartA/B to match.
- [ ] **Enable SSL** — Configure TLS for the server. Railway provides automatic HTTPS via its proxy, but update mobile app `SERVER_BASE_URL` to use `https://` and ensure `DATABASE_URL` uses `sslmode=require` for the Postgres connection.
