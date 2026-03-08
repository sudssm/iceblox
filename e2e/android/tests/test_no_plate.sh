#!/bin/bash
# Test: No-plate image should produce zero sightings

run_test_no_plate() {
    echo ""
    echo "=== TEST: No-Plate Image ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    grant_permissions

    clear_test_images
    push_test_images "$E2E_FIXTURES_DIR/no_plate"

    launch_app
    tap_start_camera
    wait_for_batch_flush

    assert_sighting_count "0" "No-plate image produces zero sightings"

    local pid
    pid=$("$ADB" shell pidof "$ANDROID_PACKAGE" 2>/dev/null | tr -d '\r')
    if [ -n "$pid" ]; then
        if "$ADB" logcat -d --pid="$pid" 2>/dev/null | grep -q "no plates extracted"; then
            echo "  INFO: FrameAnalyzer confirmed no plates extracted"
        fi
    fi

    stop_app
    echo "=== END: No-Plate Image ==="
}
