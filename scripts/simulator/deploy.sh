#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1

if [ "$PLATFORM" = "android" ]; then
    ensure_android_emulator

    APK="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
    if [ ! -f "$APK" ]; then
        echo "Error: APK not found. Run 'build.sh android' first."
        exit 1
    fi

    echo "Installing and launching Android app..."
    "$ADB" install -r "$APK"
    "$ADB" shell am start -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY"
    echo "App launched."

elif [ "$PLATFORM" = "ios" ]; then
    ensure_ios_simulator

    APP_PATH=$(find "$IOS_BUILD_DIR" -name "IceBloxApp.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "Error: App not found. Run 'build.sh ios' first."
        exit 1
    fi

    echo "Installing and launching iOS app..."
    xcrun simctl install booted "$APP_PATH"
    xcrun simctl launch booted "$IOS_BUNDLE_ID"
    echo "App launched."
fi
