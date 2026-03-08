#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_config.sh"
check_platform "$1"

PLATFORM=$1
TEXT=$2

if [ -z "$TEXT" ]; then
    echo "Usage: type.sh <ios|android> \"text to type\""
    exit 1
fi

if [ "$PLATFORM" = "android" ]; then
    # adb input text requires spaces encoded as %s
    ENCODED=$(echo "$TEXT" | sed 's/ /%s/g')
    "$ADB" shell input text "$ENCODED"

elif [ "$PLATFORM" = "ios" ]; then
    open -a Simulator
    sleep 0.3
    # Type each character via CoreGraphics keyboard events
    osascript -l JavaScript -e "
ObjC.import('CoreGraphics');
var text = '$TEXT';
var source = $.CGEventSourceCreate(1);
for (var i = 0; i < text.length; i++) {
    var ch = text.charCodeAt(i);
    var event = $.CGEventCreateKeyboardEvent(source, 0, true);
    $.CGEventKeyboardSetUnicodeString(event, 1, $.NSString.stringWithString(text[i]).characterAtIndex(0));
    $.CGEventPost(0, event);
    var up = $.CGEventCreateKeyboardEvent(source, 0, false);
    $.CGEventPost(0, up);
    delay(0.02);
}
"
fi
