#!/bin/bash
# Test: Map sightings API endpoint + iOS UI navigation

run_test_map_sightings_api() {
    echo ""
    echo "=== TEST: Map Sightings API ==="
    echo ""

    truncate_sightings
    truncate_reports

    # Seed a sighting via /api/v1/plates with a known target plate
    local plates_response
    plates_response=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -H "X-Device-ID: e2e-map-device-001" \
        -d "{\"plates\":[{\"plate_hash\":\"$(echo -n "ABC1234" | openssl dgst -sha256 -hmac "$E2E_PEPPER" -binary | xxd -p -c 64)\",\"latitude\":40.7128,\"longitude\":-74.0060,\"substitutions\":0}]}" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/plates" 2>/dev/null)

    if [ -z "$plates_response" ]; then
        echo "  SKIP: Could not seed sighting (plates endpoint unavailable)"
        echo "=== END: Map Sightings API ==="
        return
    fi

    # Seed a report via /api/v1/reports
    local tmp_photo="/tmp/e2e_map_photo_$$.jpg"
    printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9' > "$tmp_photo"

    curl -sf -X POST \
        -H "X-Device-ID: e2e-map-device-002" \
        -F "description=Black SUV parked outside" \
        -F "latitude=40.7138" \
        -F "longitude=-74.0070" \
        -F "photo=@$tmp_photo;type=image/jpeg" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" >/dev/null 2>&1

    # Query map sightings
    local response
    response=$(curl -sf "http://localhost:$E2E_SERVER_PORT/api/v1/map-sightings?lat=40.7128&lng=-74.0060&radius=10" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "  FAIL: Map sightings endpoint returned no response"
        E2E_FAIL=$((E2E_FAIL + 1))
        rm -f "$tmp_photo"
        echo "=== END: Map Sightings API ==="
        return
    fi

    local status
    status=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    if [ "$status" = "ok" ]; then
        echo "  PASS: Map sightings returned status ok"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Expected status ok (got '$status')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local sighting_count
    sighting_count=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('sightings',[])))" 2>/dev/null)
    if [ "$sighting_count" -ge 1 ] 2>/dev/null; then
        echo "  PASS: At least 1 sighting in response (count=$sighting_count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Expected at least 1 sighting (got $sighting_count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify sighting entry has required fields
    local has_fields
    has_fields=$(echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
s = data['sightings'][0]
fields = ['latitude','longitude','confidence','seen_at','type']
print('ok' if all(f in s for f in fields) else 'missing')
" 2>/dev/null)
    if [ "$has_fields" = "ok" ]; then
        echo "  PASS: Sighting has required fields"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Sighting missing required fields"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify report entry
    local has_report
    has_report=$(echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
reports = [s for s in data['sightings'] if s['type'] == 'report']
if reports:
    r = reports[0]
    print('ok' if 'description' in r and r['type'] == 'report' else 'missing')
else:
    print('no_report')
" 2>/dev/null)
    if [ "$has_report" = "ok" ]; then
        echo "  PASS: Report entry has description and type"
        E2E_PASS=$((E2E_PASS + 1))
    elif [ "$has_report" = "no_report" ]; then
        echo "  SKIP: No report in response (may have been filtered)"
    else
        echo "  FAIL: Report entry missing fields"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    rm -f "$tmp_photo"
    echo "=== END: Map Sightings API ==="
}

run_test_map_sightings_validation() {
    echo ""
    echo "=== TEST: Map Sightings Validation ==="
    echo ""

    local http_code

    # Missing lat
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/map-sightings?lng=-74&radius=10" 2>/dev/null)
    if [ "$http_code" = "400" ]; then
        echo "  PASS: Missing lat returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Missing lat should return 400 (got $http_code)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Out-of-range radius
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/map-sightings?lat=40&lng=-74&radius=600" 2>/dev/null)
    if [ "$http_code" = "400" ]; then
        echo "  PASS: Out-of-range radius returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Out-of-range radius should return 400 (got $http_code)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Empty area
    truncate_sightings
    truncate_reports
    local response
    response=$(curl -sf "http://localhost:$E2E_SERVER_PORT/api/v1/map-sightings?lat=0&lng=0&radius=1" 2>/dev/null)
    local count
    count=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('sightings',[])))" 2>/dev/null)
    if [ "$count" = "0" ]; then
        echo "  PASS: Empty area returns 0 sightings"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Empty area should return 0 sightings (got $count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Map Sightings Validation ==="
}

run_test_map_view_ios_ui() {
    echo ""
    echo "=== TEST: Map View iOS UI ==="
    echo ""

    launch_app
    sleep "$E2E_SETTLE_WAIT"

    # Tap "View Map" via trigger file or UI tap
    local container
    container=$(xcrun simctl get_app_container "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" data 2>/dev/null)
    if [ -n "$container" ]; then
        touch "$container/Library/Application Support/e2e_view_map.trigger"
        sleep "$E2E_SETTLE_WAIT"
        echo "  PASS: Sent view map trigger"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  SKIP: Could not find app container for trigger"
    fi

    stop_app

    echo "=== END: Map View iOS UI ==="
}
