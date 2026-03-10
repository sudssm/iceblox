#!/bin/bash
# Test: Device registration endpoint accepts token and stores in DB

run_test_device_registration() {
    echo ""
    echo "=== TEST: Device Registration ==="
    echo ""

    truncate_device_tokens

    local response
    response=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -H "X-Device-ID: e2e-android-device-001" \
        -d '{"token": "fake_fcm_token_e2e", "platform": "android"}' \
        "http://localhost:$E2E_SERVER_PORT/api/v1/devices" 2>/dev/null)

    if [ -z "$response" ]; then
        echo "  FAIL: Device registration endpoint returned no response"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Device Registration ==="
        return
    fi

    local status
    status=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    if [ "$status" = "ok" ]; then
        echo "  PASS: Device registration returned status ok"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Device registration should return status ok (got '$status')"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local token_count
    token_count=$(count_device_tokens | tr -d '[:space:]')
    if [ "$token_count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Device token stored in database (count=$token_count)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Device token should be stored in database (count=$token_count)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    curl -sf -X POST \
        -H "Content-Type: application/json" \
        -H "X-Device-ID: e2e-android-device-001" \
        -d '{"token": "updated_fcm_token_e2e", "platform": "android"}' \
        "http://localhost:$E2E_SERVER_PORT/api/v1/devices" >/dev/null 2>&1

    local token_count2
    token_count2=$(count_device_tokens | tr -d '[:space:]')
    if [ "$token_count2" -eq 1 ] 2>/dev/null; then
        echo "  PASS: Upsert does not duplicate device token (count=$token_count2)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Upsert should not duplicate device token (expected 1, got $token_count2)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    local bad_response
    bad_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "X-Device-ID: e2e-android-device-002" \
        -d '{"token": "", "platform": "android"}' \
        "http://localhost:$E2E_SERVER_PORT/api/v1/devices" 2>/dev/null)

    if [ "$bad_response" = "400" ]; then
        echo "  PASS: Empty token returns 400"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Empty token should return 400 (got $bad_response)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Device Registration ==="
}
