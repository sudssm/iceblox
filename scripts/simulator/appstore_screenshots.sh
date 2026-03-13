#!/bin/bash
# Capture App Store screenshots from the iOS simulator.
# Builds with APPSTORE_SCREENSHOTS flag, then captures 4 screenshots:
#   1. Splash screen
#   2. Camera view (with dashcam image)
#   3. Map view (with hardcoded pins)
#   4. Report ICE form
#
# Usage:
#   scripts/simulator/appstore_screenshots.sh [--skip-build]
#
# Output: .context/screenshots/*.png

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

# Device selection
IPAD_MODE=false
SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --ipad) IPAD_MODE=true ;;
        --skip-build) SKIP_BUILD=true ;;
    esac
done

if [ "$IPAD_MODE" = true ]; then
    # iPad Pro 13-inch (M4) for 2048x2732 screenshots
    IOS_DEVICE_UDID="7910CF24-D802-44F0-8E9E-E503F2E69A77"
    echo "=== iPad 13-inch mode ==="
else
    # iPhone 14 Plus for 1284x2778 screenshots
    IOS_DEVICE_UDID="61D9C4DA-6B19-4F5E-AC5D-6D821124C13C"
    echo "=== iPhone 6.5\" mode ==="
fi

OUTPUT_DIR="$PROJECT_ROOT/.context/screenshots"
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
    xcrun simctl io "$IOS_DEVICE_UDID" screenshot "$output" 2>/dev/null
    echo "  Captured: $output"
}

launch_app() {
    # Stop any running instance
    xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" 2>/dev/null || true
    sleep 1

    # Build env vars from arguments
    local env_args=""
    for arg in "$@"; do
        env_args="$env_args $arg"
    done

    env $env_args xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null
}

push_test_image() {
    local container
    container=$(xcrun simctl get_app_container "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" data)
    local runtime_dir="$container/Library/Application Support/test_images"
    rm -rf "$runtime_dir"
    mkdir -p "$runtime_dir"
    cp "$DASHCAM_IMAGE" "$runtime_dir/dashcam.png"
}

# ── Step 1: Build with APPSTORE_SCREENSHOTS flag ──

if [ "$SKIP_BUILD" = false ]; then
    echo "=== Building with APPSTORE_SCREENSHOTS flag ==="
    xcodebuild build \
        -project "$IOS_PROJECT" \
        -scheme "$IOS_SCHEME" \
        -destination "platform=iOS Simulator,id=$IOS_DEVICE_UDID" \
        -derivedDataPath "$IOS_BUILD_DIR" \
        OTHER_SWIFT_FLAGS="-DAPPSTORE_SCREENSHOTS" \
        -quiet
    echo "Build complete."
else
    echo "=== Skipping build (--skip-build) ==="
fi

# ── Step 2: Boot simulator, install app ──

echo "=== Preparing simulator ==="
ensure_ios_simulator

# Clean install
xcrun simctl uninstall "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" 2>/dev/null || true

APP_PATH=$(find "$IOS_BUILD_DIR" -name "IceBloxApp.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: App not found. Run without --skip-build."
    exit 1
fi
xcrun simctl install "$IOS_DEVICE_UDID" "$APP_PATH"

# Grant location permission and set location to LA
xcrun simctl privacy "$IOS_DEVICE_UDID" grant location "$IOS_BUNDLE_ID"
xcrun simctl location "$IOS_DEVICE_UDID" set 34.0522,-118.2437

# ── Screenshot 1: Splash ──

echo "=== Screenshot 1: Splash ==="
launch_app \
    SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
    SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0
sleep 3
take_screenshot "01_splash"

# ── Screenshot 2: Camera ──

echo "=== Screenshot 2: Camera ==="
launch_app \
    SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
    SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
    SIMCTL_CHILD_E2E_USE_SPLASH_TRIGGER=1 \
    SIMCTL_CHILD_SIMULATOR_TEST_IMAGES_DIRNAME=test_images \
    SIMCTL_CHILD_SIMULATOR_FRAME_INTERVAL_MS=100
sleep 2

# Push dashcam image into app's test_images directory
push_test_image

# Trigger camera start via file
CONTAINER=$(xcrun simctl get_app_container "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" data)
mkdir -p "$CONTAINER/Library/Application Support"
touch "$CONTAINER/Library/Application Support/e2e_start_camera.trigger"

# Wait for trigger to be consumed
elapsed=0
while [ "$elapsed" -lt 10 ]; do
    if [ ! -f "$CONTAINER/Library/Application Support/e2e_start_camera.trigger" ]; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
sleep 3
take_screenshot "02_camera"

# ── Screenshot 3: Map ──

echo "=== Screenshot 3: Map ==="
launch_app \
    SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
    SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
    SIMCTL_CHILD_E2E_AUTO_SHOW_MAP=1
sleep 5
take_screenshot "03_map"

# ── Screenshot 4: Report ──

echo "=== Screenshot 4: Report ==="
launch_app \
    SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
    SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
    SIMCTL_CHILD_E2E_AUTO_SHOW_REPORT=1
sleep 3
take_screenshot "04_report"

# ── Done ──

echo ""
echo "=== App Store screenshots complete ==="
echo "Screenshots saved in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/*.png
