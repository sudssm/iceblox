#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

PUSH_DIR=""

usage() {
    echo "Usage: test_mode.sh [options]"
    echo ""
    echo "Launch the Android app in test mode on the emulator."
    echo "Images are fed from src/debug/assets/test_images/ (built into APK)"
    echo "and/or from filesDir/test_images/ (pushed at runtime)."
    echo ""
    echo "Options:"
    echo "  --push-dir DIR    Push all images from DIR to device before launch"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./test_mode.sh"
    echo "  ./test_mode.sh --push-dir /path/to/plate/photos/"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --push-dir)
            PUSH_DIR="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

ensure_android_emulator

APK="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK" ]; then
    echo "Error: Debug APK not found at $APK"
    echo "Run './build.sh android' first."
    exit 1
fi

echo "Installing APK..."
"$ADB" install -r "$APK"

if [ -n "$PUSH_DIR" ]; then
    if [ ! -d "$PUSH_DIR" ]; then
        echo "Error: Push directory does not exist: $PUSH_DIR"
        exit 1
    fi

    echo "Pushing images from $PUSH_DIR to device..."
    "$ADB" shell "run-as $ANDROID_PACKAGE mkdir -p files/test_images"

    COUNT=0
    for img in "$PUSH_DIR"/*.png "$PUSH_DIR"/*.jpg "$PUSH_DIR"/*.jpeg "$PUSH_DIR"/*.bmp; do
        [ -f "$img" ] || continue
        BASENAME=$(basename "$img")
        "$ADB" push "$img" "/data/local/tmp/$BASENAME" > /dev/null
        "$ADB" shell "run-as $ANDROID_PACKAGE cp /data/local/tmp/$BASENAME files/test_images/$BASENAME"
        "$ADB" shell "rm /data/local/tmp/$BASENAME"
        COUNT=$((COUNT + 1))
        echo "  Pushed: $BASENAME"
    done
    echo "Pushed $COUNT image(s) to device."
fi

echo ""
echo "Launching app in TEST MODE..."
"$ADB" shell "am start -n $ANDROID_PACKAGE/$ANDROID_ACTIVITY --ez test_mode true"

echo ""
echo "Monitor with: ./logs.sh android | grep -E 'TestFrameFeeder|FrameAnalyzer'"
