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
- [ ] **App Store Connect listing** — Screenshots, description, privacy policy URL, category, age rating
- [x] **TestFlight build** — Archive and upload for beta testing (`make package-ios` + `make publish-ios`)

---

## Android Mobile App (Kotlin)

Spec: [`specs/mobile-app/spec.md`](specs/mobile-app/spec.md) → Implementation Plan — Android

### Debug & Release
- [ ] **Debug image capture** — Save to app-internal storage, delete on toggle off (REQ-M-20)
- [ ] **Memory audit** — Verify < 200 MB, bitmap recycling (REQ-M-31)
- [ ] **Privacy audit** — No plaintext leaks, no analytics, ProGuard rules (REQ-M-40, REQ-M-41, REQ-M-43)
- [x] **Play Store publishing** — Screenshots, feature graphic, `make publish-android` target, compile-time server URL flag

---

## E2E Testing

Spec: [`specs/testing.md`](specs/testing.md) → E2E Testing, [`specs/mobile-app/test-scenarios.md`](specs/mobile-app/test-scenarios.md) → E2E Tests

- [ ] **CI integration** — Run E2E tests in GitHub Actions with emulator + Docker

---

## Client UI

- [ ] **Vehicle trajectory tracking** *(stretch)* — Track vehicle movement across multiple reports and render the trajectory on the client map view.
- [ ] **Splash page** — Build a marketing/landing splash page for the project.
- [ ] **Cluster overlapping map pins** — Merge multiple plates at same location into single high-confidence pin.
- [ ] **Add instructions to app** — In-app onboarding or help content explaining how to use the app.

---

## Future

- [ ] **US-plate fine-tuned OCR model** — Fine-tune the CCT-XS model specifically for US license plates to improve accuracy beyond the current ~92-94% global model. Training data: OpenALPR US plate benchmark or similar. The [fast-plate-ocr](https://github.com/ankandrew/fast-plate-ocr) project provides training infrastructure.
- [ ] **Investigate backgrounding iOS** — Revisit whether any App Store-safe, user-visible iOS mode can relax the foreground-only camera requirement without violating Apple's background camera restrictions.
- [ ] **Confidence score for map pins** — Replace hardcoded 1.0 with score based on sighting count and per-variant OCR confidence stored in the sightings table.

---

## Account

- [ ] **Switch to organization enrollment** — Get a D-U-N-S number and re-enroll as an organization so the App Store seller name shows a company name instead of personal name.

---

## Productionizing

- [x] **Redis subscriber store** — Replace the in-memory `subscribers.Store` with Redis-backed storage so subscriber state survives server restarts and scales across multiple instances. (PR #106)

---

## Design Review

- [ ] **Larger stop button for driving context** — The "Stop Scanning" capsule on the camera screen is small for a driving use case. Widen to at least 200pt with more vertical padding, and consider placing it in a semi-opaque bottom bar for a consistent tap target.
- [ ] **Add tagline on splash screen** — The splash is just a title and buttons with no context. Add a one-line subtitle below "IceBlox" (caption size, white at 0.5 opacity) to orient new users.
- [x] **Settings gear discoverability** — Resolved by replacing the gear icon with a full "Settings" button in the splash screen button stack (REQ-M-70).
- [ ] **Report submit success feedback** — No confirmation after submitting a report. Show a brief success state (checkmark + "Report submitted") before dismissing the sheet.
- [ ] **iOS/Android naming parity** — iOS says "Report ICE Activity", Android says "Report ICE Vehicle". Unify the label text across platforms.
- [ ] **Disabled submit button + validation hints** — Android's gray disabled submit button doesn't explain why it's disabled. Add inline validation text (e.g., red hint below Description field saying "Required").
- [ ] **Camera status bar text sizing** — "Online" and "Last: 0s ago" monospaced caption text is hard to read at a glance while driving. Bump font size or rely more on the colored status dot.
- [ ] **Empty states** — No handling for empty map (no sightings) or offline splash screen. Show helpful placeholder content.
- [ ] **Upload queue prominence** — The yellow "N uploads queued" text is small and easy to miss. Use a persistent banner with a background color for better visibility.
