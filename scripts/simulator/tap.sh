#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1
X=$2
Y=$3

if [ -z "$X" ] || [ -z "$Y" ]; then
    echo "Usage: tap.sh <ios|android> <x> <y>"
    echo "Coordinates are in pixels (matching screenshot coordinate space)"
    exit 1
fi

if [ "$PLATFORM" = "android" ]; then
    "$ADB" shell input tap "$X" "$Y"

elif [ "$PLATFORM" = "ios" ]; then
    check_accessibility || exit 1
    open -a Simulator
    sleep 0.3
    read -r SCREEN_X SCREEN_Y <<< "$(ios_map_coords "$X" "$Y")"
    ios_click "$SCREEN_X" "$SCREEN_Y"
fi
