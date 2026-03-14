#!/bin/bash
# Capture Play Store screenshots from the Android emulator.
# Builds a debug APK (with prod server URL), deploys it, then captures 4 screenshots:
#   1. Splash screen (home with buttons)
#   2. Camera view (with injected dashcam test image)
#   3. Map view (with sighting pins from production server)
#   4. Report ICE form
#
# Usage:
#   scripts/simulator/playstore_screenshots.sh [--skip-build]
#
# Output: docs/screenshots/android_*.png

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
    esac
done

OUTPUT_DIR="$PROJECT_ROOT/docs/screenshots"
mkdir -p "$OUTPUT_DIR"

DASHCAM_IMAGE="$PROJECT_ROOT/.context/attachments/image-v2.png"
if [ ! -f "$DASHCAM_IMAGE" ]; then
    DASHCAM_IMAGE="$SCRIPT_DIR/assets/dashcam-demo.png"
fi
if [ ! -f "$DASHCAM_IMAGE" ]; then
    echo "Error: Dashcam image not found. Place one at .context/attachments/image-v2.png or scripts/simulator/assets/dashcam-demo.png"
    exit 1
fi

take_screenshot() {
    local name="$1"
    local output="$OUTPUT_DIR/${name}.png"
    "$ADB" shell screencap /sdcard/screenshot_tmp.png
    "$ADB" pull /sdcard/screenshot_tmp.png "$output" >/dev/null
    echo "  Captured: $output"
}

stop_app() {
    "$ADB" shell am force-stop "$ANDROID_PACKAGE" 2>/dev/null || true
    sleep 1
}

launch_app() {
    stop_app
    "$ADB" shell am start -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY" "$@"
}

# ── Step 1: Build with prod server URL ──

if [ "$SKIP_BUILD" = false ]; then
    echo "=== Building Android debug APK (prod server) ==="
    cd "$PROJECT_ROOT/android"
    ./gradlew assembleDebug -PSERVER_URL=https://iceblox.up.railway.app -q
    cd "$PROJECT_ROOT"
    echo "Build complete."
else
    echo "=== Skipping build (--skip-build) ==="
fi

# ── Step 2: Boot emulator, install app ──

echo "=== Preparing emulator ==="
ensure_android_emulator

APK="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK" ]; then
    echo "Error: APK not found at $APK. Run without --skip-build."
    exit 1
fi

"$ADB" install -r "$APK" >/dev/null
echo "App installed."

# Grant permissions upfront to avoid dialogs
"$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.CAMERA 2>/dev/null || true
"$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
"$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true
"$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.POST_NOTIFICATIONS 2>/dev/null || true

# Set emulator location to LA (matches iOS screenshots)
"$ADB" emu geo fix -118.2437 34.0522 2>/dev/null || true

# ── Screenshot 1: Splash ──

echo "=== Screenshot 1: Splash ==="
launch_app
sleep 8
take_screenshot "android_splash"

# ── Screenshot 2: Camera (with test image) ──

echo "=== Screenshot 2: Camera ==="
# Clean and push dashcam image into app's test_images directory
"$ADB" shell run-as "$ANDROID_PACKAGE" rm -rf files/test_images 2>/dev/null || true
"$ADB" shell run-as "$ANDROID_PACKAGE" mkdir -p files/test_images
"$ADB" push "$DASHCAM_IMAGE" "/data/local/tmp/dashcam.png" >/dev/null
"$ADB" shell run-as "$ANDROID_PACKAGE" cp "/data/local/tmp/dashcam.png" "files/test_images/dashcam.png"

# Launch with test_mode (for image injection) and SCREENSHOT_MODE (hides TEST MODE label)
launch_app --ez test_mode true --ez SCREENSHOT_MODE true
sleep 7

# Tap "Start Camera" button (center-x, ~48% down the screen)
"$ADB" shell input tap 540 1147
sleep 5
take_screenshot "android_camera"

# ── Screenshot 3: Map ──

echo "=== Screenshot 3: Map ==="
launch_app --ez SHOW_MAP true --ez SCREENSHOT_MODE true
sleep 10
take_screenshot "android_map"

# ── Screenshot 4: Report ──

echo "=== Screenshot 4: Report ==="
launch_app --ez SHOW_REPORT true
sleep 8
take_screenshot "android_report"

# ── Done ──

stop_app
echo ""
echo "=== Play Store screenshots complete ==="
echo "Screenshots saved in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/android_*.png
