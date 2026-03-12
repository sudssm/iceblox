# Optical Zoom Retry for Failed OCR

## Problem

License plates are sometimes detected by YOLO but OCR fails because the plate
occupies too few pixels in the captured frame. A plate might be readable to a
human if they could zoom in, but the 64×128 OCR input crop is too low-resolution
at the current zoom level. Digital zoom cannot help—it just interpolates the same
pixels. Optical zoom (switching to a telephoto lens or using a sensor-crop mode)
captures genuinely new pixel data and can make the plate readable.

## Concept

When OCR fails (confidence below threshold) on a detected plate that is
**sufficiently near the center of the frame**, the app:

1. Freezes the preview (shows the last normal frame to the user)
2. Zooms the camera optically (as far as quality allows)
3. Waits for one zoomed frame
4. Runs detection + OCR on the zoomed frame
5. Restores the original zoom level
6. Unfreezes the preview

The user sees a brief freeze (~100-300ms) with a small translucent "Enhancing..."
indicator centered on screen. In debug mode, the zoomed frame is shown instead
of the frozen overlay. This is best-effort — the plate may move during the cycle,
and that's acceptable.

This only works when:
- The device has optical zoom capability (multi-lens or sensor-crop mode)
- The plate is close enough to the frame center that it remains visible after
  the centered zoom crop
- OCR initially failed (we don't zoom for plates that already read successfully)

## Feasibility Assessment

### iOS (AVFoundation)

**Optical zoom detection:**
- `AVCaptureDevice.activeFormat.videoZoomFactorUpscaleThreshold` gives the exact
  zoom factor where digital upscaling begins. Below this = optical quality.
- `virtualDeviceSwitchOverVideoZoomFactors` shows where physical lens switches
  happen (e.g., `[2, 6]` on iPhone 15 Pro = ultrawide→wide at 2x, wide→tele at 6x).
- `secondaryNativeResolutionZoomFactors` reveals sensor-crop zoom points (e.g.,
  48MP→12MP center crop at 2x on main sensor).

**Zoom speed:**
- Direct assignment to `videoZoomFactor` is **instant** (no animation).
- The zoomed frame arrives at the `AVCaptureVideoDataOutput` delegate within
  1-3 frames (~33-100ms at 30fps).
- Total zoom-capture-restore cycle: ~66-150ms.

**Preview freeze:**
- Zoom changes are visible in `AVCaptureVideoPreviewLayer`—there is no way to
  zoom capture without the preview reflecting it.
- Workaround: overlay the last captured `CMSampleBuffer` as a `UIImage` on top
  of the preview layer before zooming, remove it after restoring zoom.

**Coordinate math:**
- `videoZoomFactor` applies a **centered crop**. A point at normalized coords
  `(nx, ny)` stays in frame at zoom `Z` (from current `Z₀`) iff:
  ```
  |nx - 0.5| ≤ 0.5 * (Z₀/Z)
  |ny - 0.5| ≤ 0.5 * (Z₀/Z)
  ```
- The **entire bounding box** (all 4 corners) must satisfy this constraint, not
  just the center.

### Android (CameraX)

**Optical zoom detection:**
- No direct API for "where optical zoom ends." Must use Camera2 interop:
  `LENS_INFO_AVAILABLE_FOCAL_LENGTHS` across physical cameras to compute the
  ratio of telephoto to wide focal lengths.
- `ZoomState.maxZoomRatio` includes digital zoom and is not useful for this.
- `CONTROL_ZOOM_RATIO_RANGE` (API 30+) gives the full range but doesn't mark
  the optical boundary.
- Practical approach: query physical camera focal lengths at startup and compute
  max optical ratio as `maxFocalLength / minFocalLength`.

**Zoom speed:**
- `CameraControl.setZoomRatio()` returns `ListenableFuture<Void>`. Zoom applies
  within 1-3 frames (~33-100ms).
- Total zoom-capture-restore cycle: ~100-300ms.

**Preview freeze:**
- CameraX `PreviewView` reflects zoom changes immediately.
- Workaround: capture the last `ImageProxy` bitmap and display as an overlay
  `ImageView` on top of `PreviewView`.
- Cairo uses `ImplementationMode.PERFORMANCE` (SurfaceView), which doesn't
  support `previewView.bitmap`. Use the last `ImageAnalysis` frame instead.

**Camera object:**
- Cairo currently discards the `Camera` return from `bindToLifecycle()`. Must
  store it to access `CameraControl` and `CameraInfo`.

**Coordinate math:**
- Identical to iOS: CameraX zoom is a centered crop.
  ```
  inFrame = |nx - 0.5| ≤ 0.5 * (Z₀/Z)  AND  |ny - 0.5| ≤ 0.5 * (Z₀/Z)
  ```

### Resolution Upgrade (Complementary Improvement)

The continuous video analysis pipeline can be upgraded from 1080p to capture
more pixels per plate, improving baseline OCR success rates independently of
zoom retry.

**iOS — upgrade to 4K (3840×2160):**
- Change `session.sessionPreset` from `.hd1920x1080` to `.hd4K3840x2160`.
- 4x the pixel count. Widely supported on A15+ at 30fps.
- Could also use manual `activeFormat` selection for 12MP (4032×3024) but
  that's 5.6x the pixels and may cause frame drops under ML load.
- 4K is the practical sweet spot: big improvement, well-optimized by Apple.
- `alwaysDiscardsLateVideoFrames = true` (already set) handles any frame drops.

**Android — already at CameraX max:**
- CameraX `ImageAnalysis` is **hard-capped at 1080p**. This is an architectural
  limit in CameraX, not a device limit.
- To exceed 1080p, would need to drop to Camera2 API directly (significant
  refactor) or use periodic `ImageCapture.takePicture()` for full-res snapshots.
- For now, Android stays at 1080p for the streaming pipeline.

This resolution upgrade should be done as a separate, earlier change since it
improves all OCR results, not just zoom retry cases.

### Full-Sensor Capture vs Hardware Zoom

We investigated whether we could skip hardware zoom entirely and instead capture
at the sensor's full resolution (e.g., 48MP) then software-crop around the plate.

**Finding: hardware zoom is better for the streaming pipeline.**

- 48MP frames are only available through `AVCapturePhotoOutput` (iOS) or
  Camera2 max-resolution mode (Android). Neither is available in the continuous
  video analysis pipeline.
- The streaming pipeline maxes out at 4K/12MP on iOS and 1080p on Android.
- A software crop of a 1080p frame does not add pixels — it just selects a
  sub-region of the same data. Hardware zoom (via `videoZoomFactor` /
  `setZoomRatio`) tells the ISP to crop the *sensor* and fill the output
  buffer with that crop, giving genuinely more pixels on the target area.
- For the "2x quality zoom" on iPhone's 48MP sensor, the hardware reads the
  center 12MP directly (no pixel binning), then runs the full ISP pipeline
  including Smart HDR and Deep Fusion. A software crop of a 48MP photo capture
  would have the same raw spatial data but worse ISP processing (48MP mode
  disables many computational photography features).

**Conclusion:** Use hardware zoom for the retry, and upgrade the baseline
streaming resolution to 4K on iOS as a complementary improvement.

### Camera2 Migration Analysis (Android)

We investigated whether migrating from CameraX to Camera2 would improve
resolution or zoom control for Android.

**Finding: not worth it for this feature.**

- Camera2 can deliver 4K (3840×2160) continuous frames via `ImageReader`, but
  only on `FULL` or `LEVEL_3` hardware-level devices when combined with a
  preview surface. `LIMITED` devices cap at `RECORD` size (usually 1080p).
  `LEGACY` devices cap at `PREVIEW` size.
- The migration roughly triples the camera code (~100 → ~300-400 lines),
  requires manual lifecycle/session/surface management, and loses CameraX's
  built-in device-quirk handling (Samsung, Huawei, etc.).
- Zoom control is identical — CameraX delegates to the same Camera2
  `CONTROL_ZOOM_RATIO` API internally (Android 11+). No finer-grained control
  is available via Camera2.
- Camera2Interop cannot bypass the 1080p ImageAnalysis cap — it only affects
  capture request parameters, not output surface dimensions.
- A hybrid approach (CameraX preview + Camera2 ImageReader) is not possible
  because Android only allows one client to open a camera device at a time.
- Frame delivery latency is identical — CameraX is built on Camera2 and adds
  negligible overhead.

**Conclusion:** The zoom retry feature works well within CameraX's constraints.
The optical zoom itself provides the resolution benefit (the ISP fills the 1080p
buffer with the zoomed sensor crop, giving genuinely more pixels on the plate).
Camera2 migration would only help if we needed simultaneous wide-angle + high-res
capture, which is not the case here.

### Limitations

1. **Center-only:** Only plates near the frame center benefit. A plate at the
   edge will be cropped out when zooming.
2. **Device-dependent:** iPhones without telephoto (SE, base models) may only
   get 2x sensor-crop zoom. Some Android phones have no telephoto at all.
3. **Minimum benefit threshold:** If optical zoom is only 2x, the plate must
   already be somewhat close. The feature shines on 3x-5x telephoto devices.
4. **Moving subjects:** The plate may move during the ~100-300ms cycle. This is
   best-effort — acceptable for the use case (parked/slow vehicles, and even
   for moving vehicles the attempt costs little).

---

## User Stories

### US-1: Detect optical zoom capability at startup
**As** the app, **when** the camera session starts, **I want to** determine the
device's maximum optical zoom factor, **so that** I know whether zoom retry is
possible and how far I can zoom without losing quality.

**Acceptance criteria:**
- On iOS: read `videoZoomFactorUpscaleThreshold` from the active format. If > 1.0, zoom retry is available.
- On Android: query physical camera focal lengths via Camera2 interop. Compute `maxFocalLength / minFocalLength`. If > 1.0, zoom retry is available.
- Store `maxOpticalZoom` and `isZoomRetryAvailable` in the camera manager.
- If optical zoom is unavailable (== 1.0), skip all zoom retry logic.

### US-2: Calculate zoom eligibility for a detected plate
**As** the frame processor, **when** OCR fails on a detected plate (confidence
below `ocrConfidenceThreshold`), **I want to** check whether the plate's bounding
box is close enough to the center of the frame to survive a zoom crop, **so
that** I only attempt zoom retry when the plate will remain visible.

**Acceptance criteria:**
- Input: plate bounding box in normalized coordinates [0,1], current zoom (1.0),
  target zoom (`maxOpticalZoom`).
- Check all 4 corners of the bounding box against the zoom crop constraint:
  `|corner - 0.5| ≤ 0.5 / targetZoom` for both x and y axes.
- If all corners pass, the plate is eligible for zoom retry.
- If not, skip zoom retry for this plate (it would be cropped out).
- Add a margin of safety (e.g., plate must be within 80% of the theoretical
  visible area to account for slight movement).

### US-3: Freeze the preview and show "Enhancing..." indicator
**As** the app, **when** zoom retry is about to begin, **I want to** freeze the
camera preview and show a subtle "Enhancing..." indicator, **so that** the user
gets a smooth experience and understands something is happening.

**Acceptance criteria:**
- iOS: convert the last `CMSampleBuffer` to a `UIImage`, display in a `UIImageView`
  overlaid on `AVCaptureVideoPreviewLayer`.
- Android: save the last `ImageProxy` as a `Bitmap`, display in an `ImageView`
  overlaid on `PreviewView`.
- The overlay must exactly match the preview's size and aspect ratio.
- Show a small translucent rounded-rect box centered on screen with the text
  "Enhancing..." in white. Box should be ~120×36pt, semi-transparent dark
  background (e.g., black at 60% opacity), SF Pro / Roboto font.
- The overlay and indicator are removed after zoom is restored (US-5).

### US-4: Perform zoom-capture-OCR cycle
**As** the frame processor, **when** a plate is eligible for zoom retry, **I
want to** zoom to the max optical level, capture one frame, and run
detection + OCR on it, **so that** I get a higher-resolution read of the plate.

**Acceptance criteria:**
- iOS: set `device.videoZoomFactor = maxOpticalZoom` (direct assignment, not ramp).
- Android: call `cameraControl.setZoomRatio(maxOpticalZoom)`, await the future.
- Wait for the next frame from the capture pipeline at the new zoom level.
- Run PlateDetector + PlateOCR on the zoomed frame.
- If OCR succeeds (confidence ≥ threshold): use the result, proceed with
  normalization → hashing → queueing as usual.
- If OCR still fails: discard the result, no retry. The plate was unreadable.
- Track a metric: `zoomRetryAttempts` and `zoomRetrySuccesses` (for debug stats).

### US-5: Restore zoom and unfreeze preview
**As** the app, **after** the zoom-capture-OCR cycle completes (success or
failure), **I want to** restore the zoom to the baseline level and remove the preview overlay,
**so that** the user sees normal camera output again.

**Acceptance criteria:**
- iOS: set `device.videoZoomFactor = baselineZoom` (the wide-angle switch-over factor on multi-lens virtual devices, or 1.0 on single-lens cameras). Restoring to 1.0 on virtual devices would show ultra-wide instead of the expected wide-angle view.
- Android: call `cameraControl.setZoomRatio(baselineZoomRatio)`.
- Remove the frozen-frame overlay.
- Total user-perceived freeze time should be < 500ms.
- If zoom restore fails (device error), log and continue—don't crash.

### US-6: Show zoomed frame in debug mode
**As** a developer in debug mode, **when** a zoom retry occurs, **I want to**
see the zoomed-in camera view in the preview (instead of the frozen overlay),
**so that** I can verify the zoom is working and the plate is captured correctly.

**Acceptance criteria:**
- When debug mode is on: skip the preview freeze (US-3). Let the actual zoomed
  camera view show in the preview so the developer can see what the camera sees.
- The "Enhancing..." indicator still shows, but over the live zoomed view.
- Optionally: add the zoomed frame to the debug image capture output (per
  existing REQ-M-20 debug image feature, once implemented).
- Show a brief debug overlay label: "ZOOM RETRY" when it triggers.

### US-7: Throttle zoom retries
**As** the app, **I want to** limit zoom retry frequency, **so that** I don't
degrade frame throughput or battery life by zooming on every failed OCR.

**Acceptance criteria:**
- Maximum one zoom retry per 2 seconds (configurable via `AppConfig`).
- If multiple plates fail OCR in the same frame, retry only the one closest to
  the center of the frame (most likely to benefit from zoom).
- Zoom retry is disabled during thermal throttling (`.serious` or `.critical`
  on iOS, `THERMAL_STATUS_SEVERE` on Android).
- Add `zoomRetryCooldownSeconds` to `AppConfig` (default: 2).

### US-8: Config constants for zoom retry
**As** a developer, **I want** all zoom retry parameters in `AppConfig`, **so
that** they are tunable without code changes.

**Acceptance criteria:**
- `isZoomRetryEnabled: Bool` — master toggle (default: `true`)
- `zoomRetryCooldownSeconds: Double` — minimum interval between retries (default: 2.0)
- `zoomRetryMargin: Double` — safety margin for center-proximity check (default: 0.8,
  meaning plate must be within 80% of the theoretical visible area)
- `zoomRetryMaxWaitMs: Int` — max time to wait for zoomed frame before giving up
  (default: 500)
- Mirror on both iOS (`AppConfig.swift`) and Android (`AppConfig.kt`).

### US-9: Upgrade iOS streaming resolution to 4K
**As** the app on iOS, **I want to** capture at 3840×2160 (4K) instead of
1920×1080, **so that** license plates occupy 4x more pixels and OCR succeeds
more often, even without zoom retry.

**Acceptance criteria:**
- Use `canSetSessionPreset(.hd4K3840x2160)` guard: set 4K if supported, fall back to `.hd1920x1080` otherwise. This ensures compatibility with devices that lack 4K video output.
- `alwaysDiscardsLateVideoFrames` remains `true` to handle any dropped frames.
- Verify YOLO detection still works (input is resized to 640×640 anyway).
- Verify OCR crop quality improves (more source pixels for the 64×128 resize).
- Verify memory stays within REQ-M-31 budget (< 200 MB). 4K buffers are ~32 MB
  in BGRA vs ~8 MB for 1080p — manageable with buffer reuse.
- Verify frame rate stays ≥ 15 fps on target devices (iPhone 12+).
- This is a standalone improvement — ship independently before zoom retry.

---

## Architecture

### New Components

```
iOS:
  Camera/ZoomController.swift        — manages zoom state, optical zoom detection,
                                       zoom-capture-restore cycle
  Camera/PreviewFreezer.swift        — manages frozen-frame overlay on preview

Android:
  camera/ZoomController.kt          — same role as iOS ZoomController
  camera/PreviewFreezer.kt          — same role as iOS PreviewFreezer
```

### Modified Components

```
iOS:
  Camera/CameraManager.swift        — initialize ZoomController with AVCaptureDevice
  Camera/FrameProcessor.swift       — after OCR failure, call ZoomController
  Config/AppConfig.swift             — add zoom retry constants

Android:
  camera/CameraCaptureBinder.kt     — store Camera object, expose CameraControl
  camera/FrameAnalyzer.kt           — after OCR failure, call ZoomController
  camera/CameraPreview.kt           — add overlay ImageView for PreviewFreezer
  config/AppConfig.kt               — add zoom retry constants
```

### Flow Diagram

```
Frame arrives
  → PlateDetector.detect()
  → For each detected plate:
      → PlateOCR.recognizeText()
      → IF confidence >= threshold:
          → normal flow (normalize → hash → queue)
      → ELSE IF zoomRetryAvailable AND NOT on cooldown AND NOT thermal throttled:
          → ZoomController.isPlateEligibleForZoom(boundingBox)?
              → YES:
                  → PreviewFreezer.freeze()
                  → ZoomController.zoomAndCapture()
                  → PlateDetector.detect(zoomedFrame)
                  → PlateOCR.recognizeText(zoomedPlate)
                  → IF success: normal flow
                  → ZoomController.restoreZoom()
                  → PreviewFreezer.unfreeze()
              → NO:
                  → skip (plate too far from center)
      → ELSE:
          → skip (no zoom capability or on cooldown)
```

---

## Testing Plan

### Unit Tests

**UT-1: Zoom eligibility calculation**
- Plate at (0.4, 0.4, 0.6, 0.6) [center] with 3x zoom → eligible
- Plate at (0.0, 0.0, 0.2, 0.2) [top-left corner] with 3x zoom → not eligible
- Plate at (0.3, 0.3, 0.7, 0.7) [large, centered] with 2x zoom → eligible
- Plate at (0.7, 0.4, 0.9, 0.6) [right side] with 3x zoom → not eligible
- Plate at (0.35, 0.35, 0.65, 0.65) with 2x zoom → eligible (edge case, just fits)
- With safety margin 0.8: plate at exact boundary → not eligible

**UT-2: Coordinate transform after zoom**
- Point (0.5, 0.5) stays at (0.5, 0.5) at any zoom
- Point (0.6, 0.5) at 2x zoom → (0.7, 0.5) in zoomed frame
- Point (0.75, 0.5) at 2x zoom → (1.0, 0.5) — exactly at edge

**UT-3: Cooldown enforcement**
- First call: allowed
- Call 1.5s later (cooldown=2s): blocked
- Call 2.1s later: allowed
- During thermal throttle: always blocked

**UT-4: Best candidate selection**
- Three plates fail OCR: at (0.5,0.5), (0.3,0.5), (0.1,0.5)
- Only the one at (0.5,0.5) is selected (closest to center)

### Integration Tests (On-Device)

**IT-1: Optical zoom detection**
- Run on a multi-lens device (iPhone 15 Pro / Pixel 7 Pro)
- Verify `maxOpticalZoom` > 1.0
- Run on a single-lens device or simulator
- Verify `maxOpticalZoom` == 1.0 and zoom retry is disabled

**IT-2: Preview freeze appearance**
- Trigger a zoom retry while recording screen
- Verify the preview does not flash/jump (frozen frame covers the zoom)
- Verify debug mode shows the zoom flash

**IT-3: End-to-end zoom retry**
- Set up a plate at distance where OCR fails at 1x but succeeds at 3x
- Verify zoom retry triggers and plate is read successfully
- Verify stats show `zoomRetryAttempts=1, zoomRetrySuccesses=1`

**IT-4: Zoom retry on edge plate (should skip)**
- Position a plate at the far edge of the frame
- Verify zoom retry is NOT attempted (plate would be cropped out)

**IT-5: Thermal throttle disables zoom**
- Simulate thermal pressure
- Verify zoom retry does not trigger

### Manual Test Scenarios

**MT-1: Real-world plate at distance**
- Park a car 15-20m away. At this distance, plates are detected but OCR often fails.
- Enable zoom retry. Verify the plate is now readable.
- Check battery impact: run for 5 minutes with zoom retry vs without.

**MT-2: Multiple plates, one centered**
- Position two plates: one centered, one at edge.
- Both fail OCR. Verify only the centered one triggers zoom retry.

**MT-3: Moving vehicle**
- Slowly drive past the camera. Verify zoom retry does not cause crashes or
  stale results when the plate moves between detection and zoom capture.

---

## Implementation Order

1. **US-9 (iOS 4K upgrade)** — standalone, no dependencies, immediate OCR
   improvement. Ship first.
2. **US-1 + US-8 (zoom detection + config)** — infrastructure, no user-visible
   change.
3. **US-2 (eligibility calculation)** — pure math, fully unit-testable.
4. **US-7 (throttling)** — cooldown logic, unit-testable.
5. **US-3 (preview freeze + indicator)** — UI work, needs on-device testing.
6. **US-4 + US-5 (zoom-capture-restore cycle)** — core feature, ties everything
   together.
7. **US-6 (debug mode)** — polish, low risk.

---

## Open Questions

1. **Autofocus convergence:** After zooming, does AF need to reconverge? If so,
   the first zoomed frame may be blurry. May need to wait 2-3 frames for AF
   to settle, increasing the freeze duration. Needs on-device testing.
