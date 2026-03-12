# Implementation Todo

This file tracks the gap between **written specs** and **written code**. Every item here corresponds to a section of a spec's implementation plan. When an item is completed, check it off and note the commit or PR.

Items are ordered by dependency — earlier items unblock later ones. Within a component (server, iOS, Android), the order follows the implementation plan in each spec.

---

## Server (Go)

Spec: [`specs/server/spec.md`](specs/server/spec.md)

- [ ] **Hash matcher hardening** — Switch to constant-time comparison via `crypto/subtle` to prevent timing attacks. The current O(1) map lookup satisfies REQ-S-2 but is not timing-attack resistant.
- [ ] **Rate limiter** — Token bucket per device_id, 429 + Retry-After response (REQ-S-6). Not yet implemented.
- [ ] **Pagination for map sightings** — Add cursor-based pagination to `GET /api/v1/map-sightings` for areas with many sightings.

---

## iOS Mobile App (Swift)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — iOS

### Multi-Lens Optical Zoom (activates existing zoom retry)
- [x] **Multi-lens camera selection** — Switch from `builtInWideAngleCamera` to a multi-lens virtual device (`builtInTripleCamera` → `builtInDualWideCamera` → `builtInDualCamera` → fallback to wide-angle) in `CameraManager.configureSession()`. This activates the existing zoom retry code which is currently dead because a single-lens camera has `videoZoomFactorUpscaleThreshold ≈ 1.0`. See `docs/future/optical_zoom_retry.md`.
- [x] **Baseline zoom for virtual devices** — Compute `baselineZoom` from `virtualDeviceSwitchOverVideoZoomFactors` (first entry, or 1.0 if none) and set it as the initial `videoZoomFactor`. On multi-lens virtual devices, `videoZoomFactor = 1.0` is ultra-wide — the standard wide lens sits at the first switch-over factor (~2.0).
- [x] **Restore to baseline zoom** — Update `ZoomController.restoreZoom()` to restore to `baselineZoom` instead of hardcoded `1.0`, so the user gets the wide-angle view back after a zoom retry (not ultra-wide).
- [x] **4K session preset guard** — Add `canSetSessionPreset(.hd4K3840x2160)` guard with 1080p fallback in `configureSession()`.

### Debug & Release
- [ ] **Debug image capture** — Save to sandbox, delete on toggle off (REQ-M-20)
- [ ] **Memory audit** — Verify < 200 MB RAM, buffer reuse (REQ-M-31)
- [ ] **Privacy audit** — Verify no plaintext in logs, no analytics SDKs, no image export in production (REQ-M-40, REQ-M-41, REQ-M-43)
- [ ] **App icon** — Add 1024×1024 PNG to `AppIcon.appiconset`
- [x] **Development team** — Set `DEVELOPMENT_TEAM` to Apple Team ID (Z9AXZ3RHT2)
- [ ] **App Store Connect listing** — Screenshots, description, privacy policy URL, category, age rating
- [ ] **TestFlight build** — Archive and upload for beta testing

---

## Android Mobile App (Kotlin)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — Android

### Debug & Release
- [ ] **Debug image capture** — Save to app-internal storage, delete on toggle off (REQ-M-20)
- [ ] **Memory audit** — Verify < 200 MB, bitmap recycling (REQ-M-31)
- [ ] **Privacy audit** — No plaintext leaks, no analytics, ProGuard rules (REQ-M-40, REQ-M-41, REQ-M-43)

---

## E2E Testing

Spec: [`specs/testing.md`](specs/testing.md) → E2E Testing, [`specs/mobile-app/test-scenarios.md`](specs/mobile-app/test-scenarios.md) → E2E Tests

- [ ] **CI integration** — Run E2E tests in GitHub Actions with emulator + Docker

---

## Push Notifications

- [x] **Descriptive push notification text** — ~~Include plate info, location, and confidence in the notification body.~~ Updated to "Potential ICE Activity reported". Tapping the notification opens the map view.
- [x] **Dedupe push notifications** — Suppress duplicate notifications when the same location or vehicle is detected multiple times in a short window.
- [ ] **Confidence score** — Calculate a confidence score based on the number of reports at a location and the number of character substitutions in the plate match.
- [ ] **Enable iOS push notifications** — Integrate APNs, register device tokens, and wire up server-side delivery for iOS clients.
- [ ] **Set up Android push notifications in prod** — Configure FCM credentials and delivery for the production environment.

---

## Client UI

- [x] **Notification toggle** — Add a UI toggle on both iOS and Android to let users disable/enable push notifications.
- [x] **Debug mode toggle** — Add a user-facing debug mode toggle in Settings on both iOS and Android. Shows detection bounding boxes on the camera preview without requiring a debug build.
- [ ] **Vehicle trajectory tracking** *(stretch)* — Track vehicle movement across multiple reports and render the trajectory on the client map view.
- [ ] **Splash page** — Build a marketing/landing splash page for the project.
- [ ] **Cluster overlapping map pins** — Merge multiple plates at same location into single high-confidence pin.
- [ ] **Add instructions to app** — In-app onboarding or help content explaining how to use the app.

---

## ICE Vehicle Reporting

- [x] **Server: Report model + DB methods** — `Report` GORM model with `CreateReport` and `UpdateReportStopICE` methods in `db.go`
- [x] **Server: Reports handler** — Multipart POST `/api/v1/reports` accepting photo, description, lat/lng, optional plate number
- [x] **Server: StopICE client** — Async form submission to `stopice.net/platetracker/index.cgi` with DB status callback
- [x] **Server: Wire up reports route** — Register handler in `main.go`, add `--report-upload-dir` flag
- [x] **iOS: Camera picker** — `UIViewControllerRepresentable` wrapping `UIImagePickerController` for photo capture
- [x] **iOS: Report form** — Sheet-presented view with photo, description, plate number fields and submit
- [x] **iOS: Report client** — Multipart form-data POST to `/api/v1/reports`
- [x] **iOS: Splash screen report button** — Red "Report ICE Activity" button below "Start Camera"
- [x] **Android: Report screen** — Composable with camera capture, description, plate number, submit
- [x] **Android: Report client** — OkHttp multipart POST to `/api/v1/reports`
- [x] **Android: Splash screen report button** — Red "Report ICE Activity" button below "Start Camera"
- [x] **Android: Navigation** — Route from splash to report screen

---

## Per-Character OCR Confidence Gating

- [x] **AppConfig threshold** — Add `lookalikeExpansionThreshold = 0.85` constant to iOS and Android AppConfig.
- [x] **PlateOCR per-char confidences** — Return per-slot softmax max values alongside decoded text in `OCROutput`/`OCRResult`.
- [x] **LookalikeExpander confidence gating** — Accept `charConfidences` param, only expand positions below threshold. Compute per-plate confidence via geometric mean.
- [x] **OfflineQueue schema** — Replace `substitutions` column with `confidence` (REAL) and `is_primary` (INTEGER) on both platforms. Update `pendingPlateCount` query.
- [x] **APIClient confidence field** — Send `confidence` float instead of `substitutions` in plate submissions.
- [x] **Server confidence field** — Add `Confidence float64` to `PlateRequest`, `Sighting`, `SightingResult`, and `RecordSighting`. Validate [0,1].
- [x] **FrameProcessor/CaptureRepository integration** — Thread per-char confidences from OCR through to LookalikeExpander. Create individual feed entries per variant. Remove `variantHashMap`/`pendingVariants`.
- [x] **Debug overlay italic variants** — Show expanded variants in italic in the detection feed on both platforms.
- [x] **Tests** — LookalikeExpander confidence-gating tests (iOS + Android), server confidence tests, update existing tests.
- [x] **Spec updates** — Update REQ-M-12a, license_plate_ocr.md, REQ-S-1 for confidence fields.

---

## Model-Derived Lookalike Expansion

- [x] **AppConfig** — Replace `LOOKALIKE_EXPANSION_THRESHOLD` with `OCR_CANDIDATE_THRESHOLD = 0.05` on both platforms.
- [x] **PlateOCR candidate extraction** — Extract per-slot candidate lists (all chars above candidate threshold) from softmax output. Add `SlotCandidate` type and `slotCandidates` field to `OCRResult`/`OCROutput`.
- [x] **Bridge layer** — Add `slotCandidates` to `ProcessedPlate` (Android) and thread through `FrameProcessor.recordPlate()` (iOS).
- [x] **LookalikeExpander rewrite** — Replace hardcoded confusable groups with model-derived candidate lists. New algorithm: cartesian product (small) or priority-queue (large) expansion.
- [x] **Caller updates** — Pass `slotCandidates` to `LookalikeExpander.expand()` from `CaptureRepository` (Android) and `FrameProcessor` (iOS).
- [x] **Tests rewrite** — Replace group-based tests with candidate-list-driven tests.
- [x] **Spec and docs updates** — Update REQ-M-12a, license_plate_ocr.md, and todo.md.

---

## Future

- [ ] **US-plate fine-tuned OCR model** — Fine-tune the CCT-XS model specifically for US license plates to improve accuracy beyond the current ~92-94% global model. Training data: OpenALPR US plate benchmark or similar. The [fast-plate-ocr](https://github.com/ankandrew/fast-plate-ocr) project provides training infrastructure.
- [ ] **Investigate backgrounding iOS** — Revisit whether any App Store-safe, user-visible iOS mode can relax the foreground-only camera requirement without violating Apple's background camera restrictions.
- [ ] **Confidence score for map pins** — Replace hardcoded 1.0 with score based on sighting count + substitution count.

---

## Account

- [ ] **Switch to organization enrollment** — Get a D-U-N-S number and re-enroll as an organization so the App Store seller name shows a company name instead of personal name.

---

## Productionizing

- [ ] **Enable SSL** — Configure TLS for the server. Railway provides automatic HTTPS via its proxy, but update mobile app `SERVER_BASE_URL` to use `https://` and ensure `DATABASE_URL` uses `sslmode=require` for the Postgres connection.
- [ ] **Redis subscriber store** — Replace the in-memory `subscribers.Store` with Redis-backed storage so subscriber state survives server restarts and scales across multiple instances.
- [x] **S3 photo storage** — S3 upload + presigned URLs implemented. Configured via `S3_BUCKET` and `AWS_REGION` env vars.
