#!/bin/bash
# Capture screenshots of the ICE Report flow (splash + report form).
# Uses E2E_AUTO_SHOW_REPORT env var to open the report sheet without tapping,
# avoiding multi-monitor coordinate mapping issues.
#
# Usage: scripts/simulator/screenshot_report_flow.sh [--skip-build] [--output-dir DIR]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

SKIP_BUILD=false
OUTPUT_DIR="${SCREENSHOT_DIR:-/tmp}"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

take_screenshot() {
    local step="$1"
    local filename="report_flow_${step}_${TIMESTAMP}.png"
    local output="$OUTPUT_DIR/$filename"
    xcrun simctl io "$IOS_DEVICE_UDID" screenshot "$output" 2>/dev/null
    echo "$output"
}

# ── Step 1: Build ──
if [ "$SKIP_BUILD" = false ]; then
    echo "=== Step 1: Building iOS app ==="
    "$SCRIPT_DIR/build.sh" ios
else
    echo "=== Step 1: Skipping build (--skip-build) ==="
fi

# ── Step 2: Boot and deploy ──
echo "=== Step 2: Booting simulator and deploying ==="
ensure_ios_simulator

# Uninstall first for clean state (clears notification permission dialog cache)
xcrun simctl uninstall "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" 2>/dev/null || true

APP_PATH=$(find "$IOS_BUILD_DIR" -name "IceBloxApp.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: App not found. Run without --skip-build."
    exit 1
fi
xcrun simctl install "$IOS_DEVICE_UDID" "$APP_PATH" >/dev/null

# Grant permissions upfront
xcrun simctl privacy "$IOS_DEVICE_UDID" grant location "$IOS_BUNDLE_ID" 2>/dev/null || true

# ── Step 3: Launch app (splash only) ──
echo "=== Step 3: Launching app (splash) ==="
xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" 2>/dev/null || true
sleep 1
SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null
sleep 4

# ── Step 4: Screenshot splash ──
echo "=== Step 4: Splash screen ==="
SPLASH=$(take_screenshot "01_splash")
echo "  $SPLASH"

# ── Step 5: Relaunch with auto-show report ──
echo "=== Step 5: Relaunching with report sheet ==="
xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" 2>/dev/null || true
sleep 1
SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
SIMCTL_CHILD_E2E_AUTO_SHOW_REPORT=1 \
xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null
sleep 4

# ── Step 6: Screenshot report form ──
echo "=== Step 6: Report form ==="
FORM=$(take_screenshot "02_report_form")
echo "  $FORM"

echo ""
echo "=== Screenshot session complete ==="
echo "Screenshots:"
echo "  Splash:  $SPLASH"
echo "  Form:    $FORM"
