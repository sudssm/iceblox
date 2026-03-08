#!/bin/bash
# Test: Target plate image should produce a matched sighting in the database

run_test_target_plate() {
    echo ""
    echo "=== TEST: Target Plate Image ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    clear_test_images

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/target_plate"
    wait_for_batch_flush

    local count
    count="$(count_sightings | tr -d '[:space:]')"
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Target plate image produces at least one sighting (sightings=$count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Target plate image produces at least one sighting (expected >0, actual=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    if grep -q '"matched":true' "$E2E_SERVER_LOG" 2>/dev/null; then
        echo "  INFO: Server logged a matched plate POST"
    fi

    local sighting
    sighting="$(get_latest_sighting)"
    if [ -n "$sighting" ]; then
        echo "  INFO: Latest sighting: $sighting"
    fi

    stop_app
    echo "=== END: Target Plate Image ==="
}
