#!/bin/bash
# Test: Batch upload sends plates in a single POST

run_test_batch_upload() {
    echo ""
    echo "=== TEST: Batch Upload ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    clear_test_images

    : > "$E2E_SERVER_LOG"

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/target_plate"
    wait_for_batch_flush

    local batch_lines
    batch_lines=$(grep -c 'count=[0-9]' "$E2E_SERVER_LOG" 2>/dev/null || true)
    local total_plates
    total_plates=$(grep -o 'count=[0-9]*' "$E2E_SERVER_LOG" 2>/dev/null | sed 's/count=//' | awk '{s+=$1} END {print s+0}')

    if [ "$batch_lines" -gt 0 ]; then
        echo "  PASS: Server received $batch_lines batch POST(s) totaling $total_plates plates"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Server should have received batch POST(s) with count= in log"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Batch upload produced sightings (sightings=$count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Batch upload should produce sightings (expected >0, actual=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Batch Upload ==="
}
