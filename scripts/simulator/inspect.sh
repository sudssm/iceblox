#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1

if [ "$PLATFORM" = "android" ]; then
    # Wake screen first — uiautomator returns null root node when screen is off
    "$ADB" shell input keyevent KEYCODE_WAKEUP 2>/dev/null
    sleep 0.5

    DUMP_RESULT=$("$ADB" shell uiautomator dump /sdcard/ui_dump.xml 2>&1)
    if echo "$DUMP_RESULT" | grep -q "null root node"; then
        echo "Error: uiautomator returned null root node. Screen may be locked."
        echo "Try: scripts/simulator/navigate.sh android home"
        exit 1
    fi
    "$ADB" shell cat /sdcard/ui_dump.xml

elif [ "$PLATFORM" = "ios" ]; then
    echo "iOS UI hierarchy inspection requires XCUITest (not yet configured)."
    echo "Use 'screenshot.sh ios' for visual inspection."
    exit 1
fi
