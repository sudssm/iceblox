#!/bin/bash
# Test: Non-target plate image should produce zero sightings
# The image contains a real plate (Idaho 8BAC392) that is NOT in test_plates.txt,
# so even though the app detects and uploads it, the server should not store a sighting.

run_test_non_target_plate() {
    echo ""
    echo "=== TEST: Non-Target Plate Image ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    grant_permissions

    clear_test_images
    push_test_images "$E2E_FIXTURES_DIR/non_target_plate"

    launch_app
    tap_start_camera
    wait_for_batch_flush

    assert_sighting_count "0" "Non-target plate image produces zero sightings"

    local pid
    pid=$("$ADB" shell pidof "$ANDROID_PACKAGE" 2>/dev/null | tr -d '\r')
    if [ -n "$pid" ]; then
        if "$ADB" logcat -d --pid="$pid" 2>/dev/null | grep -q "Test image produced"; then
            echo "  INFO: FrameAnalyzer detected plates from test image"
        fi
    fi

    stop_app
    echo "=== END: Non-Target Plate Image ==="
}
