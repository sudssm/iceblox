#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1
ACTION=$2

if [ -z "$ACTION" ]; then
    echo "Usage: navigate.sh <ios|android> <back|home>"
    exit 1
fi

if [ "$PLATFORM" = "android" ]; then
    case "$ACTION" in
        back)
            "$ADB" shell input keyevent KEYCODE_BACK
            ;;
        home)
            "$ADB" shell input keyevent KEYCODE_HOME
            ;;
        *)
            echo "Unknown action: $ACTION (use 'back' or 'home')"
            exit 1
            ;;
    esac

elif [ "$PLATFORM" = "ios" ]; then
    case "$ACTION" in
        home)
            if check_accessibility 2>/dev/null; then
                open -a Simulator
                sleep 0.3
                # Cmd+Shift+H via CoreGraphics (keycode 4 = 'h', flags = cmd|shift)
                ios_send_keys 4 $((0x100000 | 0x20000))
            else
                # Fallback: terminate the app to return to home screen
                echo "No Accessibility permissions — using simctl terminate as fallback."
                xcrun simctl terminate booted "$IOS_BUNDLE_ID" 2>/dev/null || true
            fi
            ;;
        back)
            echo "iOS has no system back button."
            echo "Use 'swipe.sh ios' from left edge, or tap the back button with 'tap.sh ios'."
            exit 1
            ;;
        *)
            echo "Unknown action: $ACTION (use 'back' or 'home')"
            exit 1
            ;;
    esac
fi
