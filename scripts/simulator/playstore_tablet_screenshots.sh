#!/bin/bash
# Capture Play Store TABLET screenshots from Android emulators.
# Creates 7-inch and 10-inch tablet AVDs, boots each, and captures 4 screenshots per size.
# Reuses the existing debug APK (build with playstore_screenshots.sh first).
#
# Usage:
#   scripts/simulator/playstore_tablet_screenshots.sh [--skip-build] [--7-only] [--10-only]
#
# Output: docs/screenshots/android_tablet_7_{splash,camera,map,report}.png
#         docs/screenshots/android_tablet_10_{splash,camera,map,report}.png

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

SKIP_BUILD=false
DO_7=true
DO_10=true
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
        --7-only) DO_10=false ;;
        --10-only) DO_7=false ;;
    esac
done

OUTPUT_DIR="$PROJECT_ROOT/docs/screenshots"
mkdir -p "$OUTPUT_DIR"

DASHCAM_IMAGE="$PROJECT_ROOT/.context/attachments/image-v2.png"
if [ ! -f "$DASHCAM_IMAGE" ]; then
    DASHCAM_IMAGE="$SCRIPT_DIR/assets/dashcam-demo.png"
fi
if [ ! -f "$DASHCAM_IMAGE" ]; then
    echo "Error: Dashcam image not found."
    exit 1
fi

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

APK="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK" ]; then
    echo "Error: APK not found at $APK. Run without --skip-build."
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

kill_emulators() {
    "$ADB" devices | grep emulator | cut -f1 | while read -r emu; do
        "$ADB" -s "$emu" emu kill 2>/dev/null || true
    done
    sleep 3
}

wait_for_boot() {
    "$ADB" wait-for-device
    while [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
        sleep 2
    done
    sleep 3
}

capture_screenshots_for_tablet() {
    local prefix="$1"
    local screen_w="$2"
    local screen_h="$3"

    local center_x=$((screen_w / 2))
    local button_y=$((screen_h * 48 / 100))

    echo "  Installing app..."
    "$ADB" install -r "$APK" >/dev/null
    echo "  App installed."

    # Grant permissions
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.CAMERA 2>/dev/null || true
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.POST_NOTIFICATIONS 2>/dev/null || true

    # Set location
    "$ADB" emu geo fix -118.2437 34.0522 2>/dev/null || true

    # Screenshot 1: Splash
    echo "  Screenshot 1: Splash"
    launch_app
    sleep 10
    take_screenshot "${prefix}_splash"

    # Screenshot 2: Camera (with test image)
    echo "  Screenshot 2: Camera"
    "$ADB" shell run-as "$ANDROID_PACKAGE" rm -rf files/test_images 2>/dev/null || true
    "$ADB" shell run-as "$ANDROID_PACKAGE" mkdir -p files/test_images
    "$ADB" push "$DASHCAM_IMAGE" "/data/local/tmp/dashcam.png" >/dev/null
    "$ADB" shell run-as "$ANDROID_PACKAGE" cp "/data/local/tmp/dashcam.png" "files/test_images/dashcam.png"

    launch_app --ez test_mode true --ez SCREENSHOT_MODE true
    sleep 8

    # Tap "Start Camera" button
    "$ADB" shell input tap "$center_x" "$button_y"
    sleep 6
    take_screenshot "${prefix}_camera"

    # Screenshot 3: Map
    echo "  Screenshot 3: Map"
    launch_app --ez SHOW_MAP true --ez SCREENSHOT_MODE true
    sleep 12
    take_screenshot "${prefix}_map"

    # Screenshot 4: Report
    echo "  Screenshot 4: Report"
    launch_app --ez SHOW_REPORT true
    sleep 10
    take_screenshot "${prefix}_report"

    stop_app
}

# ── Kill any running emulators ──
echo "=== Stopping running emulators ==="
kill_emulators

# ── 7-inch tablet (1080x1920, 160dpi) ──

if [ "$DO_7" = true ]; then
    echo ""
    echo "=== 7-inch tablet screenshots ==="
    echo "Booting Tablet_7inch emulator..."
    "$EMULATOR_BIN" -avd Tablet_7inch -no-snapshot -no-audio -gpu auto &>/dev/null &
    wait_for_boot
    echo "Tablet 7inch booted."

    capture_screenshots_for_tablet "android_tablet_7" 1080 1920

    echo "Killing 7-inch emulator..."
    kill_emulators
fi

# ── 10-inch tablet (1440x2560, 160dpi) ──

if [ "$DO_10" = true ]; then
    echo ""
    echo "=== 10-inch tablet screenshots ==="
    echo "Booting Tablet_10inch emulator..."
    "$EMULATOR_BIN" -avd Tablet_10inch -no-snapshot -no-audio -gpu auto &>/dev/null &
    wait_for_boot
    echo "Tablet 10inch booted."

    capture_screenshots_for_tablet "android_tablet_10" 1440 2560

    echo "Killing 10-inch emulator..."
    kill_emulators
fi

# ── Done ──

echo ""
echo "=== Tablet screenshots complete ==="
echo "Screenshots saved in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/android_tablet_*.png 2>/dev/null || echo "No tablet screenshots found."
