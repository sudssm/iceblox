#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT="$SCREENSHOT_DIR/screenshot_${PLATFORM}_${TIMESTAMP}.png"

if [ "$PLATFORM" = "android" ]; then
    "$ADB" exec-out screencap -p > "$OUTPUT"

elif [ "$PLATFORM" = "ios" ]; then
    xcrun simctl io booted screenshot "$OUTPUT" 2>/dev/null
fi

echo "$OUTPUT"
