#!/bin/bash
# Test: Target plate match is logged by the server
# Note: iOS lacks UI hierarchy inspection (no XCUITest target), so this test
# verifies the server-side match rather than the debug feed [MTCH] label.

run_test_match_debug_label() {
    echo ""
    echo "=== TEST: Match Debug Label (server-side) ==="
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

    if grep -q 'MATCH DETECTED' "$E2E_SERVER_LOG" 2>/dev/null; then
        echo "  PASS: Server logged MATCH DETECTED"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Server should log MATCH DETECTED for target plate"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Matched plate produced sightings (count=$count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Matched plate should produce sightings (expected >0, actual=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Match Debug Label ==="
}
