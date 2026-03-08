#!/bin/bash
# Test: Non-target plate image should produce zero sightings

run_test_non_target_plate() {
    echo ""
    echo "=== TEST: Non-Target Plate Image ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    clear_test_images

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/non_target_plate"
    wait_for_batch_flush

    assert_sighting_count "0" "Non-target plate image produces zero sightings"

    stop_app
    echo "=== END: Non-Target Plate Image ==="
}
