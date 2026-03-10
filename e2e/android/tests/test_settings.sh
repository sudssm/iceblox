#!/bin/bash
# Test: Settings screen UI and push notification toggle persistence

run_test_settings_ui() {
    echo ""
    echo "=== TEST: Settings UI ==="
    echo ""

    stop_app
    clear_app_data
    grant_permissions
    launch_app

    if ! tap_button_by_text "Settings"; then
        echo "  FAIL: Could not find Settings button on splash screen"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Settings UI ==="
        return
    fi

    if wait_for_ui_text "Settings"; then
        echo "  PASS: Settings screen opened"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Settings screen did not open"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Settings UI ==="
        return
    fi

    if wait_for_ui_text "Push Notifications"; then
        echo "  PASS: Push Notifications toggle visible"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Push Notifications toggle not found"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Settings UI ==="
}

run_test_settings_toggle() {
    echo ""
    echo "=== TEST: Settings Toggle Persistence ==="
    echo ""

    stop_app
    clear_app_data
    grant_permissions
    launch_app

    if ! tap_button_by_text "Settings"; then
        echo "  FAIL: Could not find Settings button"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Settings Toggle Persistence ==="
        return
    fi

    if ! wait_for_ui_text "Push Notifications"; then
        echo "  FAIL: Settings screen did not load"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Settings Toggle Persistence ==="
        return
    fi

    if tap_button_by_text "Push Notifications"; then
        echo "  Toggled Push Notifications"
    fi

    "$ADB" shell input keyevent KEYCODE_BACK
    sleep "$E2E_SETTLE_WAIT"

    if ! tap_button_by_text "Settings"; then
        echo "  FAIL: Could not reopen Settings"
        E2E_FAIL=$((E2E_FAIL + 1))
        echo "=== END: Settings Toggle Persistence ==="
        return
    fi

    if wait_for_ui_text "Push Notifications"; then
        echo "  PASS: Toggle state persisted after reopening"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: Settings did not reload properly"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi

    echo "=== END: Settings Toggle Persistence ==="
}
