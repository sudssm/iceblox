#!/bin/bash
# Test: Target plate image should produce a matched sighting in the database

run_test_target_plate() {
    echo ""
    echo "=== TEST: Target Plate Image ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    grant_permissions

    clear_test_images
    push_test_images "$E2E_FIXTURES_DIR/target_plate"

    launch_app
    tap_start_camera
    wait_for_batch_flush

    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Target plate image produces at least one sighting (sightings=$count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Target plate image produces at least one sighting (expected >0, actual=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local pid
    pid=$("$ADB" shell pidof "$ANDROID_PACKAGE" 2>/dev/null | tr -d '\r')
    if [ -n "$pid" ]; then
        if "$ADB" logcat -d --pid="$pid" 2>/dev/null | grep -q "Test image produced"; then
            echo "  INFO: FrameAnalyzer detected plates from test image"
        fi
    fi

    if grep -q '"matched":true' "$E2E_SERVER_LOG" 2>/dev/null; then
        echo "  INFO: Server logged a matched plate POST"
    fi

    local sighting
    sighting=$(get_latest_sighting)
    if [ -n "$sighting" ]; then
        echo "  INFO: Latest sighting: $sighting"
    fi

    if tap_button_by_text "Stop Recording" && wait_for_ui_text "Session Summary" 10; then
        echo "  PASS: Stop Recording shows the session summary overlay"
        E2E_PASS=$((E2E_PASS + 1))

        local ui_texts
        ui_texts="$(ui_dump_texts)"

        local plates_seen
        plates_seen="$(printf '%s\n' "$ui_texts" | sed -n 's/^Plates seen: //p' | head -1)"
        local ice_vehicles
        ice_vehicles="$(printf '%s\n' "$ui_texts" | sed -n 's/^ICE vehicles: //p' | head -1)"
        local duration_text
        duration_text="$(printf '%s\n' "$ui_texts" | sed -n 's/^Duration: //p' | head -1)"

        if [ -n "$plates_seen" ] && [ "$plates_seen" -ge 1 ] 2>/dev/null; then
            echo "  PASS: Session summary reports at least one plate seen (plates_seen=$plates_seen)"
            E2E_PASS=$((E2E_PASS + 1))
        else
            echo "  FAIL: Session summary should report at least one plate seen (actual=${plates_seen:-missing})"
            E2E_FAIL=$((E2E_FAIL + 1))
        fi

        if [ -n "$ice_vehicles" ] && [ "$ice_vehicles" -ge 1 ] 2>/dev/null; then
            echo "  PASS: Session summary reports at least one ICE vehicle (ice_vehicles=$ice_vehicles)"
            E2E_PASS=$((E2E_PASS + 1))
        else
            echo "  FAIL: Session summary should report at least one ICE vehicle (actual=${ice_vehicles:-missing})"
            E2E_FAIL=$((E2E_FAIL + 1))
        fi

        if [ -n "$duration_text" ]; then
            echo "  PASS: Session summary reports a duration ($duration_text)"
            E2E_PASS=$((E2E_PASS + 1))
        else
            echo "  FAIL: Session summary should report a duration"
            E2E_FAIL=$((E2E_FAIL + 1))
        fi
    else
        echo "  FAIL: Stop Recording should surface the session summary overlay"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Target Plate Image ==="
}
