#!/bin/bash
# Test: Settings screen renders via E2E env var trigger

run_test_settings_ui() {
    echo ""
    echo "=== TEST: Settings UI (iOS) ==="
    echo ""

    stop_app
    clear_app_data

    echo "Launching app with E2E_AUTO_SHOW_SETTINGS=1..."
    SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
    SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
    SIMCTL_CHILD_E2E_AUTO_SHOW_SETTINGS=1 \
    SIMCTL_CHILD_E2E_SERVER_BASE_URL="http://localhost:$E2E_SERVER_PORT" \
    xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null

    sleep "$E2E_SETTLE_WAIT"
    sleep 2

    local screenshot_path="/tmp/e2e_ios_settings_$(date +%Y%m%d_%H%M%S).png"
    xcrun simctl io "$IOS_DEVICE_UDID" screenshot "$screenshot_path" >/dev/null 2>&1

    if [ -f "$screenshot_path" ]; then
        echo "  PASS: Settings screen screenshot captured at $screenshot_path"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Could not capture settings screenshot"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Settings UI (iOS) ==="
}
