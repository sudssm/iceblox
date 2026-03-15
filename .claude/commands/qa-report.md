You are a QA agent performing a comprehensive quality pass after recent code merges. Your goal is to understand what changed, verify test coverage, run all tests, perform manual E2E testing on both platforms, and produce a concise report.

## Phase 1: Understand Recent Changes

1. Run `git log --oneline -20` to see recent commits merged to the current branch.
2. For each significant merge/commit, run `git show --stat <sha>` to understand what files changed.
3. Read changed files as needed to understand the scope of recent changes. Categorize them (new features, bug fixes, refactors, etc.).
4. Summarize the recent changes in a few bullet points — you'll include this in the final report.

## Phase 2: Audit Test Coverage

### Docs coverage
1. Read `docs/todo.md` and the specs in `docs/specs/` to understand what features are specified.
2. Cross-reference against the recent changes — are all new/modified features documented?

### E2E test coverage
1. Read the e2e test files in `e2e/android/tests/` and `e2e/ios/tests/`.
2. Read the e2e runner (`e2e/android/run.sh`, `e2e/ios/run.sh`) to see which tests are wired up.
3. Identify any gaps: are there recent features or edge cases not covered by e2e tests? List them.

### Unit test coverage
1. Find all unit test files: `server/` (`*_test.go`), `ios/` (`*Tests.swift`), `android/` (`*Test.kt`).
2. For each recently changed module, verify there are corresponding unit tests.
3. Identify any gaps: recently changed logic without test coverage. List them.

If you find coverage gaps, write the missing tests. Stage and commit them with a message like "Add missing tests for <feature> found during QA".

## Phase 3: Run Tests and Fix Bugs

### Go server unit tests
```
cd server && go test ./... -v -count=1
```
If any tests fail, read the failing test and the code under test, fix the bug (not the test, unless the test itself is wrong), and re-run. Commit fixes with a message like "Fix <bug> found during QA".

### iOS unit tests
The iOS simulator configured in `scripts/simulator/_config.sh` is an iPhone 16 Pro. Use it for tests:
```
xcodebuild test \
    -project ios/IceBloxApp.xcodeproj \
    -scheme IceBloxApp \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    -quiet \
    2>&1
```
If any tests fail, fix and re-run. Commit fixes.

### Android unit tests
```
source ~/.zshrc
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
cd android && ./gradlew testDebugUnitTest
```
If any tests fail, fix and re-run. Commit fixes.

### E2E tests
Run e2e tests if the infrastructure is available (emulator running, docker available, etc.):
```
e2e/android/run.sh
e2e/ios/run.sh
```
If e2e infra is not available, note it in the report and skip.

## Phase 4: Manual E2E Testing (Browser Automation)

Use the browser automation tools (mcp__claude-in-chrome__*) to perform manual testing on both iOS and Android apps. This requires the apps to be running on a simulator/emulator or device accessible via the browser.

### iOS Manual Testing (via Simulator)

**Read `docs/specs/testing.md` first** — it is the canonical reference for simulator setup, env vars, permission handling, file-based triggers, and best practices. Key sections: "deploy.sh" (env vars), "screenshot_session.sh" (automated flow), "iOS Simulator Best Practices" (permission dialogs, clean state, trigger patterns), and "Limitations" (CoreGraphics/Accessibility).

1. Use the automated screenshot session script (handles build, deploy, permission suppression, and camera trigger):
```
scripts/simulator/screenshot_session.sh ios --skip-build --output-dir .context/qa-screenshots/ios
```
Add `--debug` for debug overlay screenshots, `--test-images <dir>` for detection testing.

2. Take additional screenshots with `xcrun simctl io "$IOS_DEVICE_UDID" screenshot <path>` (after sourcing `scripts/simulator/_config.sh`).

3. Test these flows, taking a screenshot after each step:
   - **App launch**: Verify splash screen appears correctly
   - **Camera screen**: Verify "Online" status dot, "Last: --" timer, "Stop Scanning" button
   - **Settings screen**: Navigate to settings, verify all toggles/options render
   - **Settings toggles**: Toggle each setting, verify it persists
   - **Detection overlay**: If test images are available, verify detection overlays appear
   - **Alert/notification UI**: Verify alert banners or notification UI if applicable
   - **Map view**: Navigate to map view, verify it loads
   - **Report screen**: Navigate to report flow, verify form renders
   - **Background behavior**: Minimize and reopen, verify state is preserved
   - **Error states**: Disable network, verify graceful error handling

4. Read each screenshot with the Read tool and verify the UI looks correct — no layout issues, no error dialogs, proper element rendering.

### Android Manual Testing

1. Check for a running emulator or connected device:
```
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb devices
```
If no emulator is running, start one:
```
source scripts/simulator/_config.sh
$EMULATOR_BIN -avd "$ANDROID_AVD" -no-audio -no-boot-anim &
adb wait-for-device
# Wait for boot to complete
while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do sleep 1; done
```

2. Pre-grant permissions to avoid permission dialogs:
```
DEVICE=$(adb devices | grep -E 'device$' | head -1 | awk '{print $1}')
adb -s "$DEVICE" shell pm grant com.iceblox.app android.permission.CAMERA 2>/dev/null || true
adb -s "$DEVICE" shell pm grant com.iceblox.app android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
adb -s "$DEVICE" shell pm grant com.iceblox.app android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true
adb -s "$DEVICE" shell pm grant com.iceblox.app android.permission.POST_NOTIFICATIONS 2>/dev/null || true
```

3. Build, install, and launch:
```
source ~/.zshrc
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
cd android && ./gradlew assembleDebug
adb -s "$DEVICE" install -r app/build/outputs/apk/debug/app-debug.apk
adb -s "$DEVICE" shell am start -n com.iceblox.app/.MainActivity
```

4. Take screenshots and verify. **Note**: Some emulator images (e.g., Medium_Phone_API_36.1) produce blank screenshots due to GPU/SwiftShader rendering issues. If `screencap -p` produces blank images, fall back to UI inspection via `uiautomator dump`:
```
DIR=".context/qa-screenshots/android-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIR"
adb -s "$DEVICE" exec-out screencap -p > "$DIR/screenshot-01-launch.png"

# If screenshot is blank, verify UI via uiautomator dump instead:
adb -s "$DEVICE" shell uiautomator dump /sdcard/ui_dump.xml
adb -s "$DEVICE" shell cat /sdcard/ui_dump.xml
```

5. Navigate using `adb shell input tap <x> <y>`. Get exact button coordinates from `uiautomator dump` XML output (use center of `bounds` attribute). Use `scripts/simulator/inspect.sh android` for a convenient dump.

6. Test the same flows as iOS:
   - App launch and splash screen
   - Camera permission and camera feed
   - Settings screen and toggles
   - Detection overlay
   - Map view
   - Report screen
   - Background/foreground transitions
   - Error states (airplane mode)

7. For each screenshot, use the Read tool to view it and verify correctness. If screenshots are blank, report UI verification via uiautomator dumps in the QA report.

### Cross-platform consistency
- Compare iOS and Android screenshots for the same flows — note any inconsistencies in UI, behavior, or feature parity.

## Phase 5: Compile QA Report

Create a file at `.context/qa-report.md` with the following sections:

```markdown
# QA Report — [date]

## Recent Changes Summary
- Bullet points of what changed recently

## Test Coverage Audit
### Gaps Found
- List any coverage gaps found (or "None")
### Tests Added
- List any tests you wrote (or "None")

## Test Results
### Go Server Unit Tests
- Pass/fail count, any failures and fixes

### iOS Unit Tests
- Pass/fail count, any failures and fixes

### Android Unit Tests
- Pass/fail count, any failures and fixes

### E2E Tests
- Pass/fail count, or "Skipped — infrastructure not available"

## Manual E2E Results
### iOS
- Flow-by-flow results with screenshot references
- Issues found

### Android
- Flow-by-flow results with screenshot references
- Issues found

### Cross-Platform Consistency
- Any differences noted

## Bugs Fixed
- List of bugs fixed during this QA pass (with commit SHAs)

## Open Issues
- Any unresolved issues or concerns
```

Print the report contents to the console when done.
