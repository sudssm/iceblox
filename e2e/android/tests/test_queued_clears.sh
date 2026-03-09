#!/bin/bash
# Test: All detection feed entries transition from QUEUED after batch flush

run_test_queued_clears() {
    echo ""
    echo "=== TEST: Queued Entries Clear ==="
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

    local ui_texts
    ui_texts="$(ui_dump_texts)"

    local queued_count
    queued_count=$(printf '%s\n' "$ui_texts" | grep -cF '[QUED]' || echo "0")
    local sent_or_matched_count
    sent_or_matched_count=$(printf '%s\n' "$ui_texts" | grep -cE '\[SENT\]|\[MTCH\]' || echo "0")

    if [ "$sent_or_matched_count" -gt 0 ] && [ "$queued_count" -eq 0 ]; then
        echo "  PASS: All feed entries transitioned from QUEUED ($sent_or_matched_count entries SENT/MATCHED, 0 QUEUED)"
        E2E_PASS=$((E2E_PASS + 1))
    elif [ "$sent_or_matched_count" -gt 0 ] && [ "$queued_count" -gt 0 ]; then
        echo "  FAIL: $queued_count entries still QUEUED after batch flush (expected 0)"
        echo "  DEBUG: Feed entries:"
        printf '%s\n' "$ui_texts" | grep -E '\[QUED\]|\[SENT\]|\[MTCH\]' | head -10
        E2E_FAIL=$((E2E_FAIL + 1))
    else
        echo "  FAIL: No SENT or MATCHED entries found in debug feed"
        echo "  DEBUG: UI texts:"
        printf '%s\n' "$ui_texts" | head -10
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Queued Entries Clear ==="
}
