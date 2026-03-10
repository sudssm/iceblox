#!/bin/bash
# Test: Proximity alerts -- subscribe endpoint returns nearby sightings after target detection

run_test_proximity_subscribe_nearby() {
    echo ""
    echo "=== TEST: Proximity Subscribe -- Nearby Sighting ==="
    echo ""

    truncate_sightings
    stop_app
    clear_app_data
    clear_test_images

    launch_app
    tap_start_camera
    push_test_images "$E2E_FIXTURES_DIR/target_plate"
    wait_for_batch_flush

    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -lt 1 ] 2>/dev/null; then
        echo "  SKIP: No sightings recorded, cannot test subscribe (sightings=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
        stop_app
        echo "=== END: Proximity Subscribe -- Nearby Sighting ==="
        return
    fi

    local sighting_coords
    sighting_coords=$(get_sighting_coords)
    local sighting_lat sighting_lng
    sighting_lat=$(echo "$sighting_coords" | cut -d'|' -f1 | tr -d '[:space:]')
    sighting_lng=$(echo "$sighting_coords" | cut -d'|' -f2 | tr -d '[:space:]')

    if [ -z "$sighting_lat" ] || [ -z "$sighting_lng" ]; then
        sighting_lat="37.42"
        sighting_lng="-122.08"
    fi

    echo "  INFO: Sighting at lat=$sighting_lat lng=$sighting_lng"

    local response
    response=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -H "X-Device-ID: e2e-test-device" \
        -d "{\"latitude\": $sighting_lat, \"longitude\": $sighting_lng, \"radius_miles\": 500}" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/subscribe" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "  FAIL: Subscribe endpoint returned no response"
        E2E_FAIL=$((E2E_FAIL + 1))
        stop_app
        echo "=== END: Proximity Subscribe -- Nearby Sighting ==="
        return
    fi

    local sighting_count
    sighting_count=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('recent_sightings',[])))" 2>/dev/null)

    if [ "$sighting_count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Subscribe returns nearby sightings (count=$sighting_count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Subscribe should return nearby sightings (expected >0, got $sighting_count)"
        echo "  DEBUG: response=$response"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local status
    status=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    if [ "$status" = "ok" ]; then
        echo "  PASS: Subscribe response status is ok"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Subscribe response status should be ok (got '$status')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    stop_app
    echo "=== END: Proximity Subscribe -- Nearby Sighting ==="
}

run_test_proximity_subscribe_distant() {
    echo ""
    echo "=== TEST: Proximity Subscribe -- Distant Location ==="
    echo ""

    local count
    count=$(count_sightings | tr -d '[:space:]')
    if [ "$count" -lt 1 ] 2>/dev/null; then
        echo "  SKIP: No sightings available for distant test (sightings=$count)"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Proximity Subscribe -- Distant Location ==="
        return
    fi

    local response
    response=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -H "X-Device-ID: e2e-test-device-far" \
        -d '{"latitude": -33.86, "longitude": 151.20, "radius_miles": 1}' \
        "http://localhost:$E2E_SERVER_PORT/api/v1/subscribe" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "  FAIL: Subscribe endpoint returned no response"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Proximity Subscribe -- Distant Location ==="
        return
    fi

    local sighting_count
    sighting_count=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('recent_sightings',[])))" 2>/dev/null)

    if [ "$sighting_count" -eq 0 ] 2>/dev/null; then
        echo "  PASS: Distant subscribe returns zero sightings"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Distant subscribe should return zero sightings (got $sighting_count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Proximity Subscribe -- Distant Location ==="
}
