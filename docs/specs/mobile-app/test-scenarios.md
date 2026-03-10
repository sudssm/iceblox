# Mobile App Test Scenarios

## Camera Capture

### TS-1: App launch shows splash screen

```
Given the app is launched
When the main screen appears
Then the splash screen is visible
And a "Start Camera" button is shown
And the rear camera is not yet active
```

### TS-1a: Start Camera begins a new recording session

```
Given the app is showing the splash screen
When the user taps "Start Camera"
Then the rear camera activates within 2 seconds
And the camera preview displays in landscape orientation
And frame processing begins
And the session counters start at zero
```

### TS-2: Orientation locked to landscape

```
Given the app is running
When the device is rotated to portrait
Then the UI remains in landscape orientation
And camera capture is uninterrupted
```

### TS-3: Camera resumes after foreground

```
Given an active recording session was backgrounded
When the app returns to foreground
Then camera capture resumes within 1 second
And the detection pipeline restarts
```

### TS-3a: Stop Recording button is visible during a session

```
Given a recording session is active
When the camera screen is visible
Then a "Stop Recording" button is visible at the bottom-center, above the status bar
And it remains tappable above the camera preview
```

### TS-3b: Stop Recording ends detection and shows session summary

```
Given a recording session is active
And 12 plates have been scanned
And 2 ICE vehicle matches have been confirmed
When the user taps "Stop Recording"
Then no new frames are accepted for plate detection
And the session summary is shown
And the summary displays 12 plates seen
And the summary displays 2 ICE vehicles identified
```

### TS-3c: Session summary shows duration and resets to idle

```
Given a recording session started 7 minutes and 5 seconds ago
When the user taps "Stop Recording"
Then the session summary shows a duration of 7m 05s
When the user dismisses the summary
Then the splash screen is shown again
And starting a new session resets the counters to zero
```

### TS-3d: Session summary indicates provisional ICE count when uploads are pending

```
Given a recording session is active
And 3 queued uploads from this session have not been acknowledged
When the user taps "Stop Recording"
Then the session summary is shown
And it displays a pending-sync indicator
And the ICE vehicle count is labeled as confirmed matches received so far
```

## License Plate Detection

### TS-4: Plate detected in frame

```
Given the camera is capturing frames
When a license plate is visible at 5-15 meters distance
Then the detection model identifies a bounding box around the plate
And the bounding box is passed to the OCR stage
```

### TS-5: Low-confidence detection discarded

```
Given the camera is capturing frames
When a region is detected with confidence below the threshold (0.5)
Then the region is not passed to OCR
And no hash is generated
```

### TS-6: Angled plate detected

```
Given the camera is capturing frames
When a license plate is visible at up to 30 degrees from perpendicular
Then the detection model identifies the plate region
```

## OCR

### TS-7: Successful plate read

```
Given a plate region has been detected with sufficient confidence
When OCR processes the cropped region
Then the recognized text matches the plate characters
And the text is normalized (uppercase, no spaces/hyphens)
```

### TS-8: Invalid OCR result discarded

```
Given OCR produces a result with fewer than 2 characters
Then the result is discarded
And no hash is generated
```

### TS-9: Low-confidence OCR discarded

```
Given OCR produces a result with confidence below the threshold (0.6)
Then the result is discarded
And no hash is generated
```

## Plate Normalization

### TS-10: Normalization rules applied

```
Given OCR returns "abc-1234"
When normalization is applied
Then the result is "ABC1234"
```

### TS-11: Whitespace and special characters removed

```
Given OCR returns " A B C  1234! "
When normalization is applied
Then the result is "ABC1234"
```

### TS-12: Oversized result discarded

```
Given OCR returns "ABCDEFGHIJ" (10 characters after normalization)
Then the result is discarded as invalid
```

## Hashing

### TS-13: HMAC-SHA256 produces consistent output

```
Given a normalized plate "ABC1234"
And an HMAC pepper "test-pepper-key"
When the hash is computed
Then the output is a deterministic 64-character hex string
And computing the hash again with the same inputs produces the same output
```

### TS-14: Plaintext discarded after hashing

```
Given a plate "ABC1234" has been hashed
Then the plaintext string is no longer held in any variable, cache, or buffer
And the plaintext does not appear in any log output
```

## Deduplication

### TS-15: Duplicate within window ignored

```
Given plate "ABC1234" was detected and hashed at T=0
When the same plate "ABC1234" is detected at T=30 seconds
Then no new hash is generated
And no new entry is added to the upload queue
```

### TS-16: Duplicate after window expires processed

```
Given plate "ABC1234" was detected and hashed at T=0
And the deduplication window is 60 seconds
When the same plate "ABC1234" is detected at T=61 seconds
Then a new hash is generated and queued
```

## Server Communication

### TS-17: Batch sent on threshold

```
Given 9 hashed plates are in the upload queue
When a 10th plate is hashed
Then a batch of 10 plates is sent to the server via HTTPS POST
And the queue is cleared on successful response
```

### TS-18: Batch sent on timer

```
Given 3 hashed plates are in the upload queue
When 30 seconds have elapsed since the last send
Then a batch of 3 plates is sent to the server
```

### TS-19: Offline plates queued

```
Given the device has no network connectivity
When a plate is detected, OCR'd, and hashed
Then the hash is added to the offline queue
And no network request is attempted
```

### TS-20: Queue flushed on reconnect

```
Given the device was offline with 15 hashed plates queued
When network connectivity is restored
Then all 15 queued plates are sent to the server in a batch
```

### TS-21: Queue persists across restart

```
Given 5 hashed plates are in the offline queue
When the app is killed and relaunched
Then the offline queue still contains 5 entries
And they are sent when connectivity is available
```

### TS-22: Queue overflow drops oldest

```
Given the offline queue contains 1,000 entries (max capacity)
When a new plate is detected offline
Then the oldest entry is removed
And the new entry is added
And the queue size remains 1,000
```

## Retry Logic

### TS-23: Exponential backoff on failure

```
Given a batch upload fails
Then the app retries after 5 seconds
When it fails again
Then the app retries after 10 seconds
When it fails again
Then the app retries after 20 seconds
(continuing up to 5 minute max delay, 10 max retries)
```

### TS-24: Failed batch stays in queue

```
Given a batch upload fails after all retries
Then the batch entries remain in the offline queue
And are retried on the next upload cycle
```

## Rate Limiting

### TS-24a: 429 response pauses uploads

```
Given the server responds with 429 Too Many Requests
And the Retry-After header is 30
Then the app pauses all uploads for 30 seconds
And plates continue to be detected and queued locally
And uploads resume after 30 seconds
```

## Location

### TS-24b: GPS coordinates included with plates

```
Given the user has granted location permission
When a plate is detected and queued
Then the queue entry includes latitude and longitude
And the batch upload includes coordinates for each plate
```

### TS-24c: No GPS warning displayed

```
Given the user has denied location permission
When the app is running
Then a persistent warning is shown in the status bar: "No GPS"
And plates are still detected, hashed, and uploaded (without coordinates)
```

## Debug Mode

### TS-25: Debug mode activation

```
Given the app is running in a debug build
When the user triple-taps the camera preview
Then debug mode is activated
And bounding boxes, plate text, and hash previews appear on the overlay
```

### TS-26: Debug mode not available in production

```
Given the app is a production (App Store / Play Store) build
When the user triple-taps the camera preview
Then nothing happens
And debug mode is not activated
```

### TS-27: Debug images deleted on toggle off

```
Given debug mode is active and 5 still images have been captured
When the user toggles debug mode off
Then all 5 still images are deleted from the app's sandboxed storage
```

## Privacy

### TS-28: No plaintext in logs

```
Given a plate "ABC1234" is detected and processed
When app logs are examined
Then "ABC1234" does not appear in any log entry
And only the HMAC hash (or truncated hash) appears in debug logs
```

### TS-29: No images in production mode

```
Given the app is running in production mode
When plates are detected continuously for 10 minutes
Then no image files exist in the app's storage directory
```

### TS-30: Pepper not exposed

```
Given the HMAC pepper is stored in secure storage
Then the pepper does not appear in:
  - Application logs
  - Crash reports
  - Network requests
  - User-accessible file storage
```

## Thermal Management

### TS-31: Throttle on thermal pressure

```
Given the device reaches thermal throttling state
When the app detects thermal pressure
Then the frame processing rate is reduced to 5 fps
And the app continues operating without crashing
```

### TS-32: Resume normal rate after cooldown

```
Given the app throttled to 5 fps due to thermal pressure
When the device cools below the thermal threshold
Then the frame processing rate returns to the normal rate (15+ fps)
```

## Test Mode (Android)

### TS-33: Test mode bypasses camera permission

```
Given the app is launched with intent extra test_mode=true
Then the splash screen is shown normally
And the user taps "Start Camera"
And the camera permission check is bypassed (TestFrameFeeder replaces the camera)
And the camera screen is displayed with test mode active
```

### TS-34: Test images fed through pipeline

```
Given the app is in test mode
And test images exist in debug assets or filesDir
When the pipeline starts
Then images are loaded and fed through FrameAnalyzer.analyzeBitmap() on a 500ms interval
And the detection pipeline runs (detect → OCR → normalize → deduplicate → hash → queue)
```

### TS-35: Test mode UI shows current image

```
Given the app is in test mode
When images are being fed
Then the current test image is displayed instead of the camera preview
And a "TEST MODE" banner is visible at the top of the screen
```

### TS-36: Test mode with no images

```
Given the app is in test mode
And no test images exist in debug assets or filesDir
When the pipeline starts
Then a "No test images found" status is logged
And the UI shows "Loading test images..." indefinitely
```

## E2E Tests

### TS-E2E-1: Android no-plate image produces zero sightings

```
Given an ephemeral postgres and Go server are running with test plates
And the Android app is installed on the emulator
When a no-plate image is pushed and the app is launched in test mode
And the batch flush interval elapses (35 seconds)
Then zero sightings exist in the database
```

### TS-E2E-2: Android non-target plate image produces zero sightings

```
Given an ephemeral postgres and Go server are running with test plates
And the Android app is installed on the emulator
When an image containing a plate NOT in test_plates.txt is pushed and the app is launched in test mode
And the batch flush interval elapses (35 seconds)
Then zero sightings exist in the database
And the app logcat shows FrameAnalyzer detected plates from the test image
```

### TS-E2E-3: Android target plate image produces matched sighting

```
Given an ephemeral postgres and Go server are running with test plates
And the Android app is installed on the emulator
When an image containing a known test plate is pushed and the app is launched in test mode
And the batch flush interval elapses (35 seconds)
Then at least one sighting exists in the database
And the server log contains a matched POST response
```

### TS-E2E-4: Full pipeline verification

```
Given TS-E2E-3 has passed
Then the app logcat shows FrameAnalyzer detected plates from the test image
And the server log shows the plate hash was matched
And the sightings table contains a row with plate_id, seen_at, and hardware_id
```

### TS-E2E-5: Subscribe returns nearby sightings

```
Given TS-E2E-3 has passed (a target plate sighting exists in the database)
When POST /api/v1/subscribe is called with coordinates near the sighting and radius_miles=500
Then the response status is "ok"
And recent_sightings contains at least one entry
```

### TS-E2E-6: Subscribe returns empty for distant location

```
Given a target plate sighting exists in the database
When POST /api/v1/subscribe is called with coordinates on the opposite side of the globe and radius_miles=1
Then recent_sightings is an empty array
```

### TS-E2E-7: Android AlertClient subscribes on startup

```
Given the Android app is installed and launched in test mode with a target plate image
And the batch flush interval elapses
Then the app logcat contains AlertClient log entries showing the subscribe timer fired
```

### TS-E2E-8: Android stop recording shows session summary

```
Given TS-E2E-3 has passed in the current Android app session
When the operator taps "Stop Recording"
Then a "Session Summary" overlay appears
And it shows "Plates seen", "ICE vehicles", and "Duration"
And "Plates seen" is at least 1
And "ICE vehicles" is at least 1
```

### TS-E2E-10: Android background capture continues producing sightings

```
Given an ephemeral postgres and Go server are running with test plates
And the Android app is installed on the emulator
When a target plate image is pushed and the app is launched in test mode
And the camera is started
And the app is backgrounded via KEYCODE_HOME
Then the app process remains alive after backgrounding
And the app process remains alive after the batch flush window
And at least one sighting exists in the database (captured while backgrounded)
```

### TS-E2E-11: Android match debug label shows MATCHED state

```
Given an ephemeral postgres and Go server are running with test plates
And the Android app is installed on the emulator
When a target plate image is pushed and the app is launched in test mode
And the camera is started
And debug mode is enabled via triple-tap
And the batch flush interval elapses
Then the server log contains MATCH DETECTED
And the debug feed shows a [MTCH] label for the matched plate
```

### TS-E2E-12: Android detection feed entries transition from QUEUED after batch flush

```
Given an ephemeral postgres and Go server are running with test plates
And the Android app is installed on the emulator
When a target plate image is pushed and the app is launched in test mode
And the camera is started
And debug mode is enabled via triple-tap
And the batch flush interval elapses
Then no detection feed entries remain in QUEUED state
And at least one entry shows SENT or MATCHED state
```

### TS-E2E-9: iOS stop recording writes session summary artifact

```
Given an ephemeral postgres and Go server are running with test plates
And the iOS app is installed on the simulator
When a target plate image is injected into the running camera session
And the batch flush interval elapses
And the E2E stop-recording trigger is fired
Then the app writes a session summary artifact in its Application Support directory
And the artifact reports "plates_seen", "ice_vehicles", and "duration_seconds"
And "plates_seen" is at least 1
And "ice_vehicles" is at least 1
```

### TS-E2E-13: Device registration stores token and supports upsert

```
Given an ephemeral postgres and Go server are running
When POST /api/v1/devices is called with a valid token, platform "ios", and X-Device-ID header
Then the response status is "ok"
And the device_tokens table contains the token
When the same device re-registers with a different token
Then the device_tokens table still contains exactly one row for that device
And the token is updated to the new value
When POST /api/v1/devices is called with an empty token
Then the response is 400 Bad Request
```

### TS-E2E-14: iOS batch upload sends plates via batch POST

```
Given an ephemeral postgres and Go server are running with test plates
And the iOS app is installed on the simulator
When a target plate image is injected into the running camera session
And the batch flush interval elapses
Then the server log contains batch POST(s) with count= entries
And at least one sighting exists in the database
```
