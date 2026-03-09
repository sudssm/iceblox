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
    clear_session_summary_artifacts

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

    trigger_stop_recording

    local summary_path
    if summary_path="$(wait_for_session_summary_artifact 10)"; then
        echo "  PASS: Stop recording produced a session summary artifact"
        E2E_PASS=$((E2E_PASS + 1))

        local plates_seen
        plates_seen="$(grep '^plates_seen=' "$summary_path" | head -1 | cut -d= -f2-)"
        local ice_vehicles
        ice_vehicles="$(grep '^ice_vehicles=' "$summary_path" | head -1 | cut -d= -f2-)"
        local duration_seconds
        duration_seconds="$(grep '^duration_seconds=' "$summary_path" | head -1 | cut -d= -f2-)"

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

        if [ -n "$duration_seconds" ] && [ "$duration_seconds" -ge 0 ] 2>/dev/null; then
            echo "  PASS: Session summary reports a duration (duration_seconds=$duration_seconds)"
            E2E_PASS=$((E2E_PASS + 1))
        else
            echo "  FAIL: Session summary should report duration_seconds"
            E2E_FAIL=$((E2E_FAIL + 1))
        fi
    else
        echo "  FAIL: Stop recording should produce a session summary artifact"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Target Plate Image ==="
}
