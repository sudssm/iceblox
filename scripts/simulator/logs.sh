#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1
MODE=${2:-dump}

if [ "$PLATFORM" = "android" ]; then
    PID=$("$ADB" shell pidof "$ANDROID_PACKAGE" 2>/dev/null | tr -d '\r' || echo "")

    if [ "$MODE" = "stream" ]; then
        if [ -n "$PID" ]; then
            "$ADB" logcat --pid="$PID"
        else
            echo "App not running. Streaming all logs..."
            "$ADB" logcat
        fi
    else
        if [ -n "$PID" ]; then
            "$ADB" logcat -d --pid="$PID"
        else
            "$ADB" logcat -d | tail -50
        fi
    fi

elif [ "$PLATFORM" = "ios" ]; then
    if [ "$MODE" = "stream" ]; then
        xcrun simctl spawn booted log stream \
            --predicate 'subsystem == "com.cameras.app" OR process == "CamerasApp"' \
            --level info
    else
        xcrun simctl spawn booted log show \
            --predicate 'subsystem == "com.cameras.app" OR process == "CamerasApp"' \
            --last 1m \
            --style compact
    fi
fi
