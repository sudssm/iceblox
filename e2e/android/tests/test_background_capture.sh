#!/bin/bash
# Test: App continues capturing plates after being backgrounded

run_test_background_capture() {
    echo ""
    echo "=== TEST: Background Capture ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    grant_permissions

    clear_test_images
    push_test_images "$E2E_FIXTURES_DIR/target_plate"

    launch_app
    tap_start_camera

    # Background the app
    echo "Backgrounding the app..."
    "$ADB" shell input keyevent KEYCODE_HOME
    sleep "$E2E_SETTLE_WAIT"

    # Verify the app process is still alive
    local pid
    pid=$("$ADB" shell pidof "$ANDROID_PACKAGE" 2>/dev/null | tr -d '\r')
    if [ -n "$pid" ]; then
        echo "  PASS: App process still alive after backgrounding (pid=$pid)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: App process died after backgrounding"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    wait_for_batch_flush

    # Verify the process is still alive after the batch window
    pid=$("$ADB" shell pidof "$ANDROID_PACKAGE" 2>/dev/null | tr -d '\r')
    if [ -n "$pid" ]; then
        echo "  PASS: App process still alive after batch window (pid=$pid)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: App process crashed during background capture"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify sightings were recorded while backgrounded
    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Background capture produced sightings (sightings=$count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Background capture should produce sightings (expected >0, actual=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    if [ -n "$pid" ]; then
        if "$ADB" logcat -d --pid="$pid" 2>/dev/null | grep -q "BackgroundCaptureService"; then
            echo "  INFO: BackgroundCaptureService was active in logs"
        fi
    fi

    stop_app
    echo "=== END: Background Capture ==="
}
