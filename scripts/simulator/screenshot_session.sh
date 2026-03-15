#!/bin/bash
# Automated screenshot session: build, deploy, launch, and capture screenshots at key stages.
# Supports both iOS and Android. Designed for AI-assisted visual verification.
#
# Usage:
#   scripts/simulator/screenshot_session.sh ios [options]
#   scripts/simulator/screenshot_session.sh android [options]
#
# Options:
#   --skip-build        Reuse existing build artifacts
#   --debug             Enable debug overlay (iOS: via E2E_FORCE_DEBUG_MODE, Android: via triple-tap)
#   --test-images DIR   Push test images and use them instead of camera (enables test mode)
#   --output-dir DIR    Save screenshots to DIR instead of /tmp
#
# Output:
#   Screenshots are saved as session_<platform>_<step>_<timestamp>.png
#   The script prints each screenshot path as it's captured.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM="$1"
shift

SKIP_BUILD=false
DEBUG_MODE=false
TEST_IMAGES_DIR=""
OUTPUT_DIR="$SCREENSHOT_DIR"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --test-images)
            TEST_IMAGES_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

take_screenshot() {
    local step="$1"
    local filename="session_${PLATFORM}_${step}_${TIMESTAMP}.png"
    local output="$OUTPUT_DIR/$filename"

    if [ "$PLATFORM" = "android" ]; then
        "$ADB" exec-out screencap -p > "$output"
    elif [ "$PLATFORM" = "ios" ]; then
        xcrun simctl io booted screenshot "$output" 2>/dev/null
    fi

    echo "$output"
}

# ── Step 1: Build ──

if [ "$SKIP_BUILD" = false ]; then
    echo "=== Step 1: Building $PLATFORM app ==="
    "$SCRIPT_DIR/build.sh" "$PLATFORM"
else
    echo "=== Step 1: Skipping build (--skip-build) ==="
fi

# ── Step 2: Deploy ──

echo "=== Step 2: Deploying ==="

if [ "$PLATFORM" = "android" ]; then
    ensure_android_emulator

    APK="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
    if [ ! -f "$APK" ]; then
        echo "Error: APK not found. Run without --skip-build."
        exit 1
    fi
    "$ADB" install -r "$APK" >/dev/null

elif [ "$PLATFORM" = "ios" ]; then
    ensure_ios_simulator

    APP_PATH=$(find "$IOS_BUILD_DIR" -name "IceBloxApp.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "Error: App not found. Run without --skip-build."
        exit 1
    fi
    xcrun simctl install booted "$APP_PATH" >/dev/null
fi

# ── Step 3: Pre-launch screenshot ──

echo "=== Step 3: Pre-launch screenshot ==="
take_screenshot "01_pre_launch"

# ── Step 4: Launch app ──

echo "=== Step 4: Launching app ==="

if [ "$PLATFORM" = "android" ]; then
    if [ -n "$TEST_IMAGES_DIR" ]; then
        # Push test images and launch in test mode
        echo "Pushing test images from $TEST_IMAGES_DIR..."
        "$ADB" shell run-as "$ANDROID_PACKAGE" mkdir -p files/test_images
        for img in "$TEST_IMAGES_DIR"/*.{png,jpg,jpeg,bmp}; do
            [ -f "$img" ] || continue
            "$ADB" push "$img" "/data/local/tmp/$(basename "$img")" >/dev/null
            "$ADB" shell run-as "$ANDROID_PACKAGE" cp "/data/local/tmp/$(basename "$img")" "files/test_images/$(basename "$img")"
        done
        "$ADB" shell am start -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY" --ez test_mode true
    else
        "$ADB" shell am start -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY"
    fi

elif [ "$PLATFORM" = "ios" ]; then
    # Stop any existing instance first
    xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
    sleep 1

    # Build launch env vars
    local_env=""
    local_env="SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1"
    local_env="$local_env SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0"
    local_env="$local_env SIMCTL_CHILD_E2E_USE_SPLASH_TRIGGER=1"
    local_env="$local_env SIMCTL_CHILD_E2E_SPLASH_TRIGGER_FILENAME=e2e_start_camera.trigger"

    if [ "$DEBUG_MODE" = true ]; then
        local_env="$local_env SIMCTL_CHILD_E2E_FORCE_DEBUG_MODE=1"
    fi

    if [ -n "$TEST_IMAGES_DIR" ]; then
        local_env="$local_env SIMCTL_CHILD_SIMULATOR_TEST_IMAGES_DIRNAME=test_images"
        local_env="$local_env SIMCTL_CHILD_SIMULATOR_FRAME_INTERVAL_MS=100"
    fi

    env $local_env xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null
fi

sleep 3
echo "=== Step 5: Splash screen screenshot ==="
take_screenshot "02_splash"

# ── Step 6: Start camera / transition past splash ──

echo "=== Step 6: Triggering camera start ==="

if [ "$PLATFORM" = "android" ]; then
    # Tap "Start Camera" button (center-bottom area of splash screen)
    "$ADB" shell input tap 540 1368

elif [ "$PLATFORM" = "ios" ]; then
    # Use file-based trigger to bypass splash
    CONTAINER=$(xcrun simctl get_app_container "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" data)
    mkdir -p "$CONTAINER/Library/Application Support"
    touch "$CONTAINER/Library/Application Support/e2e_start_camera.trigger"

    # Push test images if provided (must be done after app is running)
    if [ -n "$TEST_IMAGES_DIR" ]; then
        runtime_dir="$CONTAINER/Library/Application Support/test_images"
        rm -rf "$runtime_dir"
        mkdir -p "$runtime_dir"
        for img in "$TEST_IMAGES_DIR"/*; do
            [ -f "$img" ] || continue
            case "${img##*.}" in
                png|jpg|jpeg|bmp|txt) cp "$img" "$runtime_dir/" ;;
            esac
        done
    fi

    # Wait for trigger to be consumed
    elapsed=0
    while [ "$elapsed" -lt 10 ]; do
        if [ ! -f "$CONTAINER/Library/Application Support/e2e_start_camera.trigger" ]; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
fi

sleep 3
echo "=== Step 7: Camera active screenshot ==="
take_screenshot "03_camera_active"

# ── Step 8: Enable debug mode if requested ──

if [ "$DEBUG_MODE" = true ]; then
    echo "=== Step 8: Enabling debug mode ==="

    if [ "$PLATFORM" = "android" ]; then
        # Triple-tap center of screen to toggle debug mode
        for _ in 1 2 3; do
            "$ADB" shell input tap 540 1200
            sleep 0.15
        done
    fi
    # iOS debug mode is enabled via E2E_FORCE_DEBUG_MODE env var (already set at launch)

    sleep 2
    echo "=== Step 9: Debug overlay screenshot ==="
    take_screenshot "04_debug_overlay"
fi

# ── iOS: Screenshot additional screens via auto-show env vars ──

if [ "$PLATFORM" = "ios" ]; then
    ios_auto_show_screenshot() {
        local env_var="$1"
        local step_name="$2"

        xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
        sleep 1
        env \
            SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
            SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
            "SIMCTL_CHILD_${env_var}=1" \
            xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null
        sleep 3
        echo "=== Screenshot: $step_name ==="
        take_screenshot "$step_name"
    }

    ios_auto_show_screenshot "E2E_AUTO_SHOW_SETTINGS" "05_settings"
    ios_auto_show_screenshot "E2E_AUTO_SHOW_MAP" "06_map"
    ios_auto_show_screenshot "E2E_AUTO_SHOW_REPORT" "07_report"

    # Return to splash for a clean final state
    xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo ""
echo "=== Screenshot session complete ==="
echo "Screenshots saved in: $OUTPUT_DIR"
echo "Prefix: session_${PLATFORM}_*_${TIMESTAMP}.png"
