#!/bin/bash
# Test: Target plate match updates debug feed entry to [MTCH]

run_test_match_debug_label() {
    echo ""
    echo "=== TEST: Match Debug Label ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    grant_permissions

    : > "$E2E_SERVER_LOG"

    clear_test_images
    push_test_images "$E2E_FIXTURES_DIR/target_plate"

    launch_app
    tap_start_camera

    # Triple-tap to enable debug mode overlay
    "$ADB" shell input tap 540 1200
    sleep 0.15
    "$ADB" shell input tap 540 1200
    sleep 0.15
    "$ADB" shell input tap 540 1200
    sleep 2

    wait_for_batch_flush

    if grep -q 'MATCH DETECTED' "$E2E_SERVER_LOG" 2>/dev/null; then
        echo "  PASS: Server logged MATCH DETECTED"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Server should log MATCH DETECTED for target plate"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local ui_texts
    ui_texts="$(ui_dump_texts)"

    if printf '%s\n' "$ui_texts" | grep -Fq '[MTCH]'; then
        echo "  PASS: Debug feed shows [MTCH] label for matched plate"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Debug feed should show [MTCH] label after server returns match"
        echo "  DEBUG: UI texts:"
        printf '%s\n' "$ui_texts" | grep -E '\[QUED\]|\[SENT\]|\[MTCH\]' | head -5
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Match Debug Label ==="
}
