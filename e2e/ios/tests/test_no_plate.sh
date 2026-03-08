#!/bin/bash
# Test: No-plate image should produce zero sightings

run_test_no_plate() {
    echo ""
    echo "=== TEST: No-Plate Image ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    clear_test_images

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/no_plate"
    wait_for_batch_flush

    assert_sighting_count "0" "No-plate image produces zero sightings"

    stop_app
    echo "=== END: No-Plate Image ==="
}
