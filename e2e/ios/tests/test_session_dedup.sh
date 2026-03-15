#!/bin/bash
# Test: Session-scoped deduplication (REQ-M-8)
# 1. Within a session, repeated frames of the same plate produce sightings only once
# 2. After session restart (dedup reset), the same plate produces sightings again

run_test_session_dedup_stable() {
    echo ""
    echo "=== TEST: Session Dedup - Stable Count ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    clear_test_images

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/target_plate"
    wait_for_batch_flush

    local count_after_first_flush
    count_after_first_flush=$(count_sightings | tr -d '[:space:]')

    if [ "$count_after_first_flush" -le 0 ] 2>/dev/null; then
        echo "  FAIL: Expected sightings after first batch flush (actual=$count_after_first_flush)"
        E2E_FAIL=$((E2E_FAIL + 1))
        stop_app
        echo "=== END: Session Dedup - Stable Count ==="
        return
    fi

    echo "  INFO: Sightings after first batch flush: $count_after_first_flush"

    wait_for_batch_flush

    local count_after_second_flush
    count_after_second_flush=$(count_sightings | tr -d '[:space:]')

    if [ "$count_after_second_flush" = "$count_after_first_flush" ]; then
        echo "  PASS: Sighting count stable across batch cycles ($count_after_second_flush)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Sighting count should not grow within session (first=$count_after_first_flush, second=$count_after_second_flush)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Session Dedup - Stable Count ==="
}

run_test_session_dedup_cross_session() {
    echo ""
    echo "=== TEST: Session Dedup - Cross Session Reset ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    clear_test_images

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/target_plate"
    wait_for_batch_flush

    local session1_count
    session1_count=$(count_sightings | tr -d '[:space:]')

    if [ "$session1_count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Session 1 produced sightings ($session1_count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Session 1 should produce sightings (actual=$session1_count)"
        E2E_FAIL=$((E2E_FAIL + 1))
        stop_app
        echo "=== END: Session Dedup - Cross Session Reset ==="
        return
    fi

    stop_app
    truncate_sightings
    clear_app_data
    clear_test_images

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/target_plate"
    wait_for_batch_flush

    local session2_count
    session2_count=$(count_sightings | tr -d '[:space:]')

    if [ "$session2_count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Session 2 produced sightings after reset ($session2_count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Session 2 should produce sightings after dedup reset (actual=$session2_count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Session Dedup - Cross Session Reset ==="
}
