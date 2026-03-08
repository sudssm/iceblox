#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1
X1=$2
Y1=$3
X2=$4
Y2=$5
DURATION=${6:-300}

if [ -z "$X1" ] || [ -z "$Y1" ] || [ -z "$X2" ] || [ -z "$Y2" ]; then
    echo "Usage: swipe.sh <ios|android> <x1> <y1> <x2> <y2> [duration_ms]"
    echo "Coordinates are in pixels (matching screenshot coordinate space)"
    exit 1
fi

if [ "$PLATFORM" = "android" ]; then
    "$ADB" shell input swipe "$X1" "$Y1" "$X2" "$Y2" "$DURATION"

elif [ "$PLATFORM" = "ios" ]; then
    open -a Simulator
    sleep 0.3
    read -r SX1 SY1 <<< "$(ios_map_coords "$X1" "$Y1")"
    read -r SX2 SY2 <<< "$(ios_map_coords "$X2" "$Y2")"
    DURATION_S=$(awk "BEGIN {printf \"%.3f\", $DURATION / 1000}")
    ios_drag "$SX1" "$SY1" "$SX2" "$SY2" "$DURATION_S"
fi
