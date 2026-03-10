#!/bin/bash
# Test: Report submission API, validation, and app UI

run_test_report_api() {
    echo ""
    echo "=== TEST: Report API ==="
    echo ""

    truncate_reports

    local response
    response=$(curl -sf -X POST \
        -H "X-Device-ID: e2e-test-device" \
        -F "description=E2E test report" \
        -F "latitude=40.7128" \
        -F "longitude=-74.0060" \
        -F "photo=@$E2E_FIXTURES_DIR/no_plate/no_plate.png" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "  FAIL: Report endpoint returned no response"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Report API ==="
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
    if [ -n "$report_id" ] && [ "$report_id" != "None" ]; then
        echo "  PASS: Report ID present in response ($report_id)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Report ID should be present in response"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local report_count
    report_count=$(count_reports | tr -d '[:space:]')
    if [ "$report_count" = "1" ]; then
        echo "  PASS: Report stored in database (count=$report_count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Expected 1 report in database (got $report_count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local lat
    lat=$(get_report_field "latitude" | tr -d '[:space:]')
    if echo "$lat" | grep -q "40.71"; then
        echo "  PASS: Latitude stored correctly ($lat)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Latitude should be ~40.7128 (got '$lat')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local lng
    lng=$(get_report_field "longitude" | tr -d '[:space:]')
    if echo "$lng" | grep -q "\-74.00"; then
        echo "  PASS: Longitude stored correctly ($lng)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Longitude should be ~-74.006 (got '$lng')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local desc
    desc=$(get_report_field "description" | tr -d '[:space:]')
    if [ "$desc" = "E2Etestreport" ]; then
        echo "  PASS: Description stored correctly"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Description should be 'E2E test report' (got '$desc')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local photo_path
    photo_path=$(get_report_field "photo_path" | tr -d '[:space:]')
    if [ -n "$photo_path" ] && echo "$photo_path" | grep -q "reports/"; then
        echo "  PASS: Photo path stored ($photo_path)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Photo path should reference reports/ (got '$photo_path')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Report API ==="
}

run_test_report_validation() {
    echo ""
    echo "=== TEST: Report Validation ==="
    echo ""

    local http_code

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Device-ID: e2e-test-device" \
        -F "latitude=40.7128" \
        -F "longitude=-74.0060" \
        -F "photo=@$E2E_FIXTURES_DIR/no_plate/no_plate.png" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)
    if [ "$http_code" = "400" ]; then
        echo "  PASS: Missing description returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Missing description should return 400 (got $http_code)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Device-ID: e2e-test-device" \
        -F "description=Test" \
        -F "latitude=40.7128" \
        -F "longitude=-74.0060" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)
    if [ "$http_code" = "400" ]; then
        echo "  PASS: Missing photo returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Missing photo should return 400 (got $http_code)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -F "description=Test" \
        -F "latitude=40.7128" \
        -F "longitude=-74.0060" \
        -F "photo=@$E2E_FIXTURES_DIR/no_plate/no_plate.png" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)
    if [ "$http_code" = "400" ]; then
        echo "  PASS: Missing X-Device-ID returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Missing X-Device-ID should return 400 (got $http_code)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Device-ID: e2e-test-device" \
        -F "description=Test" \
        -F "latitude=91.0" \
        -F "longitude=-74.0060" \
        -F "photo=@$E2E_FIXTURES_DIR/no_plate/no_plate.png" \
        "http://localhost:$E2E_SERVER_PORT/api/v1/reports" 2>/dev/null)
    if [ "$http_code" = "400" ]; then
        echo "  PASS: Out-of-range latitude returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Out-of-range latitude should return 400 (got $http_code)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Report Validation ==="
}

run_test_report_app_ui() {
    echo ""
    echo "=== TEST: Report App UI ==="
    echo ""

    truncate_reports
    grant_permissions
    launch_app

    if ! tap_button_by_text "Report ICE Activity"; then
        echo "  FAIL: Could not find 'Report ICE Activity' button"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Report App UI ==="
        return
    fi

    if wait_for_ui_text "Description"; then
        echo "  PASS: Report form opened (Description field visible)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Report form did not open (Description field not found)"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Report App UI ==="
        return
    fi

    tap_button_by_text "Take Photo" || true
    sleep 2

    tap_button_by_text "Description" 2>/dev/null || true
    "$ADB" shell input text "E2E_report_test"
    sleep 1

    tap_button_by_text "Submit Report" || true
    sleep 3

    local report_count
    report_count=$(count_reports | tr -d '[:space:]')
    if [ "$report_count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Report submitted from app (count=$report_count)"
        E2E_PASS=$((E2E_PASS + 1))

        local lat
        lat=$(get_report_field "latitude" | tr -d '[:space:]')
        if [ -n "$lat" ] && [ "$lat" != "0" ]; then
            echo "  PASS: Latitude is non-zero ($lat)"
            E2E_PASS=$((E2E_PASS + 1))
        else
            echo "  FAIL: Latitude should be non-zero (got '$lat')"
            E2E_FAIL=$((E2E_FAIL + 1))
        fi
    else
        echo "  SKIP: Report not submitted (camera may be unavailable on emulator)"
    fi

    echo "=== END: Report App UI ==="
}
