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
