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
    # Escape single quotes and backslashes for safe JavaScript string interpolation
    ESCAPED_TEXT=$(printf '%s' "$TEXT" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g")
    osascript -l JavaScript <<JSEOF
ObjC.import('CoreGraphics');
var text = '$ESCAPED_TEXT';
var source = $.CGEventSourceCreate(1);
for (var i = 0; i < text.length; i++) {
    var down = $.CGEventCreateKeyboardEvent(source, 0, true);
    var ch = text.charCodeAt(i);
    var buf = $.NSString.stringWithString(text[i]).characterAtIndex(0);
    $.CGEventKeyboardSetUnicodeString(down, 1, buf);
    $.CGEventPost(0, down);
    var up = $.CGEventCreateKeyboardEvent(source, 0, false);
    $.CGEventPost(0, up);
    delay(0.02);
}
JSEOF
fi
