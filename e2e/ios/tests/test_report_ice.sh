#!/bin/bash
# Test: ICE Vehicle Report submission via /api/v1/reports

run_test_report_ice() {
    echo ""
    echo "=== TEST: Report ICE Vehicle ==="
    echo ""

    truncate_reports

    # Create a minimal JPEG for the photo field (smallest valid JPEG: 2x1 pixel)
    local tmp_photo="/tmp/e2e_test_photo_$$.jpg"
    printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00' > "$tmp_photo"
    # Append a minimal image frame so the file is recognizable as JPEG
    printf '\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.\x27 ",#\x1c\x1c(7),01444\x1f\x27444444444444' >> "$tmp_photo"
    printf '\xff\xd9' >> "$tmp_photo"

    # --- Test 1: Valid submission with plate number ---
    local response
    response=$(curl -sf -X POST \
        -H "X-Device-ID: e2e-ios-report-001" \
        -F "description=ICE vehicle blocking bike lane" \
        -F "latitude=40.7128" \
        -F "longitude=-74.0060" \
        -F "plate_number=ABC1234" \
        -F "photo=@$tmp_photo;type=image/jpeg" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "  FAIL: Reports endpoint returned no response"
        E2E_FAIL=$((E2E_FAIL + 1))
        rm -f "$tmp_photo"
        echo "=== END: Report ICE Vehicle ==="
        return
    fi

    local status
    status=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    if [ "$status" = "ok" ]; then
        echo "  PASS: Report submission returned status ok"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Report submission should return status ok (got '$status')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local report_id
    report_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('report_id',''))" 2>/dev/null)
    if [ -n "$report_id" ] && [ "$report_id" != "None" ] && [ "$report_id" != "" ]; then
        echo "  PASS: Response includes report_id ($report_id)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Response should include report_id"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify report stored in DB
    local report_count
    report_count=$(count_reports | tr -d '[:space:]')
    if [ "$report_count" -eq 1 ] 2>/dev/null; then
        echo "  PASS: Report stored in database (count=$report_count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Report should be stored in database (expected 1, got $report_count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify description stored correctly
    local db_description
    db_description=$(get_report_field "description" | tr -d '[:space:]')
    if [ "$db_description" = "ICEvehicleblockingbikelane" ]; then
        echo "  PASS: Description stored correctly"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Description mismatch (got '$db_description')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify plate number stored
    local db_plate
    db_plate=$(get_report_field "plate_number" | tr -d '[:space:]')
    if [ "$db_plate" = "ABC1234" ]; then
        echo "  PASS: Plate number stored correctly"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Plate number mismatch (expected ABC1234, got '$db_plate')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # Verify stop_ice_status is pending or submitted (async submitter may complete before query)
    local db_status
    db_status=$(get_report_field "stop_ice_status" | tr -d '[:space:]')
    if [ "$db_status" = "pending" ] || [ "$db_status" = "submitted" ] || [ "$db_status" = "failed" ]; then
        echo "  PASS: StopICE status is valid ($db_status)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: StopICE status should be pending/submitted/failed (got '$db_status')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # --- Test 2: Valid submission without plate number ---
    truncate_reports

    local response2
    response2=$(curl -sf -X POST \
        -H "X-Device-ID: e2e-ios-report-002" \
        -F "description=Suspicious vehicle near school" \
        -F "latitude=34.0522" \
        -F "longitude=-118.2437" \
        -F "photo=@$tmp_photo;type=image/jpeg" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    local status2
    status2=$(echo "$response2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    if [ "$status2" = "ok" ]; then
        echo "  PASS: Report without plate number accepted"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Report without plate number should be accepted (got '$status2')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local db_plate2
    db_plate2=$(get_report_field "plate_number" | tr -d '[:space:]')
    if [ -z "$db_plate2" ]; then
        echo "  PASS: Empty plate number stored as empty"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Plate number should be empty (got '$db_plate2')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # --- Test 3: Missing description returns 400 ---
    local bad_response
    bad_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Device-ID: e2e-ios-report-003" \
        -F "latitude=40.0" \
        -F "longitude=-74.0" \
        -F "photo=@$tmp_photo;type=image/jpeg" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    if [ "$bad_response" = "400" ]; then
        echo "  PASS: Missing description returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Missing description should return 400 (got $bad_response)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # --- Test 4: Missing device ID returns 400 ---
    local no_device_response
    no_device_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -F "description=test" \
        -F "latitude=40.0" \
        -F "longitude=-74.0" \
        -F "photo=@$tmp_photo;type=image/jpeg" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    if [ "$no_device_response" = "400" ]; then
        echo "  PASS: Missing X-Device-ID returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Missing X-Device-ID should return 400 (got $no_device_response)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # --- Test 5: Missing photo returns 400 ---
    local no_photo_response
    no_photo_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Device-ID: e2e-ios-report-005" \
        -F "description=test" \
        -F "latitude=40.0" \
        -F "longitude=-74.0" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    if [ "$no_photo_response" = "400" ]; then
        echo "  PASS: Missing photo returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Missing photo should return 400 (got $no_photo_response)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # --- Test 6: Invalid latitude returns 400 ---
    local bad_lat_response
    bad_lat_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Device-ID: e2e-ios-report-006" \
        -F "description=test" \
        -F "latitude=91.0" \
        -F "longitude=-74.0" \
        -F "photo=@$tmp_photo;type=image/jpeg" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    if [ "$bad_lat_response" = "400" ]; then
        echo "  PASS: Out-of-range latitude returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Out-of-range latitude should return 400 (got $bad_lat_response)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    # --- Test 7: GET method returns 405 ---
    local get_response
    get_response=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    if [ "$get_response" = "405" ]; then
        echo "  PASS: GET method returns 405"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: GET method should return 405 (got $get_response)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    rm -f "$tmp_photo"
    echo "=== END: Report ICE Vehicle ==="
}
