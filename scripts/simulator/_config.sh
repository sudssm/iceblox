#!/bin/bash
# Shared configuration for simulator testing scripts

# Project root (two levels up from scripts/simulator/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Android
ANDROID_SDK="$HOME/Library/Android/sdk"
ADB="$ANDROID_SDK/platform-tools/adb"
EMULATOR_BIN="$ANDROID_SDK/emulator/emulator"
ANDROID_AVD="Medium_Phone_API_36.1"
ANDROID_PACKAGE="com.iceblox.app"
ANDROID_ACTIVITY=".MainActivity"

# iOS
IOS_DEVICE_UDID="C06D96F6-6AE3-4B73-874F-C8324A15B0B9"
IOS_BUNDLE_ID="com.cameras.app"
IOS_DEVICE_PIXEL_W=1179
IOS_DEVICE_PIXEL_H=2556
IOS_PROJECT="$PROJECT_ROOT/ios/CamerasApp.xcodeproj"
IOS_SCHEME="CamerasApp"
IOS_BUILD_DIR="$PROJECT_ROOT/ios/build"

# Screenshot output
SCREENSHOT_DIR="/tmp"

# --- Helpers ---

check_platform() {
    if [ "$1" != "ios" ] && [ "$1" != "android" ]; then
        echo "Usage: $(basename "$0") <ios|android> [args...]"
        exit 1
    fi
}

ensure_android_emulator() {
    if ! "$ADB" devices 2>/dev/null | grep -q "emulator"; then
        echo "Starting Android emulator..."
        "$EMULATOR_BIN" -avd "$ANDROID_AVD" &>/dev/null &
        echo "Waiting for emulator to boot..."
        "$ADB" wait-for-device
        while [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
            sleep 1
        done
        echo "Emulator booted."
    fi
}

ensure_ios_simulator() {
    if ! xcrun simctl list devices booted 2>/dev/null | grep -q "$IOS_DEVICE_UDID"; then
        echo "Booting iOS simulator..."
        xcrun simctl boot "$IOS_DEVICE_UDID"
        open -a Simulator
        sleep 2
        echo "Simulator booted."
    fi
}

# iOS device logical dimensions (points) for iPhone 16 Pro
IOS_DEVICE_POINTS_W=393
IOS_DEVICE_POINTS_H=852
IOS_RETINA_SCALE=3

# Map iOS device pixel coordinates to absolute macOS screen coordinates.
# Reads Simulator window geometry from its preferences plist (no permissions needed).
# Usage: ios_map_coords <device_pixel_x> <device_pixel_y>
# Outputs: <screen_x> <screen_y>
ios_map_coords() {
    local DEV_PX=$1
    local DEV_PY=$2

    # Read window center and scale from Simulator preferences (no permissions needed)
    local PLIST_JSON
    PLIST_JSON=$(defaults export com.apple.iphonesimulator - | plutil -convert json -o - -)

    # Parse with python: extract first WindowCenter and WindowScale for our device
    python3 -c "
import json, sys, re
data = json.loads('''$PLIST_JSON''')
device = data.get('DevicePreferences', {}).get('$IOS_DEVICE_UDID', {})
geom = device.get('SimulatorWindowGeometry', {})
# Pick the first screen entry (primary display)
for screen_id, config in geom.items():
    center_str = config.get('WindowCenter', '{0, 0}')
    scale = config.get('WindowScale', 1)
    nums = re.findall(r'[-\d.]+', center_str)
    cx, cy = float(nums[0]), float(nums[1])
    # Device logical dims
    dw, dh = $IOS_DEVICE_POINTS_W, $IOS_DEVICE_POINTS_H
    # Window content = device points * scale
    content_w = dw * scale
    content_h = dh * scale
    title_bar = 28
    # Window top-left from center
    win_x = cx - content_w / 2
    win_y = cy - (content_h + title_bar) / 2
    # Content area top-left
    ct_x = win_x
    ct_y = win_y + title_bar
    # Map device pixels to screen coords
    retina = $IOS_RETINA_SCALE
    screen_x = ct_x + ($DEV_PX / retina) * scale
    screen_y = ct_y + ($DEV_PY / retina) * scale
    print(f'{screen_x:.0f} {screen_y:.0f}')
    break
"
}

# Post a mouse click at absolute screen coordinates via CoreGraphics.
# Requires macOS Accessibility permission for osascript.
# Usage: ios_click <screen_x> <screen_y>
ios_click() {
    local SX=$1
    local SY=$2
    osascript -l JavaScript <<JSEOF
ObjC.import('CoreGraphics');
var point = $.CGPointMake($SX, $SY);
var source = $.CGEventSourceCreate(1);
var down = $.CGEventCreateMouseEvent(source, 1, point, 0);
var up = $.CGEventCreateMouseEvent(source, 2, point, 0);
$.CGEventPost(0, down);
delay(0.05);
$.CGEventPost(0, up);
JSEOF
}

# Post a mouse drag between two screen coordinates via CoreGraphics.
# Usage: ios_drag <x1> <y1> <x2> <y2> <duration_seconds>
ios_drag() {
    local SX1=$1 SY1=$2 SX2=$3 SY2=$4 DUR=$5
    osascript -l JavaScript <<JSEOF
ObjC.import('CoreGraphics');
var source = $.CGEventSourceCreate(1);
var steps = 20;
var stepDelay = $DUR / steps;
var down = $.CGEventCreateMouseEvent(source, 1, $.CGPointMake($SX1, $SY1), 0);
$.CGEventPost(0, down);
delay(0.02);
for (var i = 1; i <= steps; i++) {
    var t = i / steps;
    var cx = $SX1 + ($SX2 - $SX1) * t;
    var cy = $SY1 + ($SY2 - $SY1) * t;
    var drag = $.CGEventCreateMouseEvent(source, 6, $.CGPointMake(cx, cy), 0);
    $.CGEventPost(0, drag);
    delay(stepDelay);
}
var up = $.CGEventCreateMouseEvent(source, 2, $.CGPointMake($SX2, $SY2), 0);
$.CGEventPost(0, up);
JSEOF
}

# Send a keyboard shortcut to the frontmost app via CoreGraphics.
# Usage: ios_send_keys <keycode> [modifier_flags]
# Common keycodes: h=4, backspace=51, return=36, escape=53
# Modifier flags: cmd=0x100000, shift=0x20000, option=0x80000, ctrl=0x40000
ios_send_keys() {
    local KEYCODE=$1
    local FLAGS=${2:-0}
    osascript -l JavaScript <<JSEOF
ObjC.import('CoreGraphics');
var source = $.CGEventSourceCreate(1);
var down = $.CGEventCreateKeyboardEvent(source, $KEYCODE, true);
$.CGEventSetFlags(down, $FLAGS);
$.CGEventPost(0, down);
delay(0.05);
var up = $.CGEventCreateKeyboardEvent(source, $KEYCODE, false);
$.CGEventSetFlags(up, $FLAGS);
$.CGEventPost(0, up);
JSEOF
}
