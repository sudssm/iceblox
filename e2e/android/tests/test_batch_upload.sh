#!/bin/bash
# Test: Batch upload sends plates in a single POST, banner appears and clears

run_test_batch_upload() {
    echo ""
    echo "=== TEST: Batch Upload ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    grant_permissions

    # Clear server log to isolate this test's output
    : > "$E2E_SERVER_LOG"

    clear_test_images
    push_test_images "$E2E_FIXTURES_DIR/target_plate"

    launch_app
    tap_start_camera

    # Brief wait for plates to be detected and queued (but before batch fires)
    sleep 5

    # Check if upload queue banner appears (plates detected but may not yet be sent)
    if ui_dump_texts | grep -Fq "uploads queued"; then
        echo "  PASS: Upload queue banner visible while plates are queued"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  INFO: Upload queue banner not visible (batch may have already fired)"
    fi

    wait_for_batch_flush

    # Verify batch format: server log should show count= (batch POST, not individual)
    local batch_lines
    batch_lines=$(grep -c 'count=[0-9]' "$E2E_SERVER_LOG" 2>/dev/null || echo "0")
    local total_plates
    total_plates=$(grep -oP 'count=\K[0-9]+' "$E2E_SERVER_LOG" 2>/dev/null | awk '{s+=$1} END {print s+0}')

    if [ "$batch_lines" -gt 0 ]; then
        echo "  PASS: Server received $batch_lines batch POST(s) totaling $total_plates plates"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Server should have received batch POST(s) with count= in log"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify sightings were recorded
    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Batch upload produced sightings (sightings=$count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Batch upload should produce sightings (expected >0, actual=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # After batch flush, banner should be gone (queue drained)
    if ui_dump_texts | grep -Fq "uploads queued"; then
        echo "  FAIL: Upload queue banner should disappear after batch flush"
        E2E_FAIL=$((E2E_FAIL + 1))
    else
        echo "  PASS: Upload queue banner cleared after batch flush"
        E2E_PASS=$((E2E_PASS + 1))
    fi

    # Verify stop recording shows pending sync info
    if tap_button_by_text "Stop Recording" && wait_for_ui_text "Session Summary" 10; then
        local ui_texts
        ui_texts="$(ui_dump_texts)"

        if printf '%s\n' "$ui_texts" | grep -Fq "Pending sync"; then
            echo "  INFO: Session summary shows pending sync indicator"
        else
            echo "  INFO: No pending sync (all uploads completed before stop)"
        fi
    fi

    stop_app
    echo "=== END: Batch Upload ==="
}
