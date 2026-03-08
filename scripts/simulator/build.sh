#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1

if [ "$PLATFORM" = "android" ]; then
    echo "Building Android app..."
    cd "$PROJECT_ROOT/android"
    ./gradlew assembleDebug
    echo "Build complete: app/build/outputs/apk/debug/app-debug.apk"

elif [ "$PLATFORM" = "ios" ]; then
    echo "Building iOS app..."
    xcodebuild build \
        -project "$IOS_PROJECT" \
        -scheme "$IOS_SCHEME" \
        -destination "platform=iOS Simulator,id=$IOS_DEVICE_UDID" \
        -derivedDataPath "$IOS_BUILD_DIR" \
        -quiet
    echo "Build complete."
fi
