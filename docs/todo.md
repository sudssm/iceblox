# Implementation Todo

This file tracks the gap between **written specs** and **written code**. Every item here corresponds to a section of a spec's implementation plan. When an item is completed, check it off and note the commit or PR.

Items are ordered by dependency — earlier items unblock later ones. Within a component (server, iOS, Android), the order follows the implementation plan in each spec.

---

## YOLO Model Training

Spec: [`specs/mobile-app/license_plate_detection.md`](specs/mobile-app/license_plate_detection.md)

- [ ] Download license plate dataset (HuggingFace, 8,823 images)
- [ ] Train YOLOv8-nano (fine-tune from COCO pretrained weights)
- [ ] Validate against quality gates (mAP@0.5 ≥ 0.80, recall ≥ 0.75)
- [ ] Create `models/CHANGELOG.md` with v1 metrics (after training completes)

---

## Server (Go)

Spec: [`specs/server/spec.md`](specs/server/spec.md)

- [ ] **Hash matcher** — Constant-time comparison via `crypto/subtle`, return matched label (REQ-S-2). Currently uses O(1) map lookup which is not timing-attack resistant.
- [ ] **Rate limiter** — Token bucket per device_id, 429 + Retry-After response (REQ-S-6). Not yet implemented.

---

## iOS Mobile App (Swift)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — iOS

- [ ] **Debug image capture** — Save to sandbox, delete on toggle off (REQ-M-20)
- [ ] **Memory audit** — Verify < 200 MB RAM, buffer reuse (REQ-M-31)
- [ ] **Privacy audit** — Verify no plaintext in logs, no analytics SDKs, no image export in production (REQ-M-40, REQ-M-41, REQ-M-43)
- [ ] **App icon** — Add 1024×1024 PNG to `AppIcon.appiconset`
- [ ] **Development team** — Set `DEVELOPMENT_TEAM` to Apple Team ID (requires Apple Developer account)
- [ ] **App Store Connect listing** — Screenshots, description, privacy policy URL, category, age rating
- [ ] **TestFlight build** — Archive and upload for beta testing

---

## Android Mobile App (Kotlin)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — Android

- [ ] **Debug image capture** — Save to app-internal storage, delete on toggle off (REQ-M-20)
- [ ] **Memory audit** — Verify < 200 MB, bitmap recycling (REQ-M-31)
- [ ] **Privacy audit** — No plaintext leaks, no analytics, ProGuard rules (REQ-M-40, REQ-M-41, REQ-M-43)

---

## Productionizing

- [ ] **Change the pepper** — Replace `default-pepper-change-me` with a secure random value (`openssl rand -hex 32`). Update server env var (`PEPPER`), iOS `PlateHasher.swift` pepperPartA/B, and Android `PlateHasher.kt` pepperPartA/B to match.
- [ ] **Enable SSL** — Configure TLS for the server. Railway provides automatic HTTPS via its proxy, but update mobile app `SERVER_BASE_URL` to use `https://` and ensure `DATABASE_URL` uses `sslmode=require` for the Postgres connection.
