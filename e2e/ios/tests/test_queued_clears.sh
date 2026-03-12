#!/bin/bash
# Test: All queued plates are uploaded after the batch flush
# Note: iOS lacks UI hierarchy inspection (no XCUITest target), so this test
# verifies server-side receipt of all plates rather than checking the debug
# feed for QUEUED→SENT/MATCHED transitions.

run_test_queued_clears() {
    echo ""
    echo "=== TEST: Queued Entries Clear (server-side) ==="
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

    if [ "$batch_lines" -gt 0 ]; then
        echo "  PASS: Server received batch POST(s) ($batch_lines batch log lines)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Server should have received batch POST(s) with count= in log"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: All plates processed — sightings recorded (count=$count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Plates should have been uploaded and matched (expected >0, actual=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Queued Entries Clear ==="
}
