#!/bin/bash
# Android app lifecycle for E2E tests

build_android_app() {
    echo "Building Android app..."
    cd "$PROJECT_ROOT/android"
    ./gradlew assembleDebug --quiet
    cd "$PROJECT_ROOT"
    local apk="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
    if [ ! -f "$apk" ]; then
        echo "ERROR: APK not found at $apk"
        return 1
    fi
    echo "APK built: $apk"
}

install_android_app() {
    ensure_android_emulator
    local apk="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
    echo "Installing app on emulator..."
    "$ADB" install -r "$apk"
}

push_test_images() {
    local image_dir="$1"
    echo "Pushing test images from $image_dir..."
    "$ADB" shell "run-as $ANDROID_PACKAGE mkdir -p files/test_images"

    local count=0
    for img in "$image_dir"/*.png "$image_dir"/*.jpg "$image_dir"/*.jpeg "$image_dir"/*.bmp; do
        [ -f "$img" ] || continue
        local basename
        basename=$(basename "$img")
        "$ADB" push "$img" "/data/local/tmp/$basename" > /dev/null
        "$ADB" shell "run-as $ANDROID_PACKAGE cp /data/local/tmp/$basename files/test_images/$basename"
        "$ADB" shell "rm /data/local/tmp/$basename"
        count=$((count + 1))
    done
    echo "Pushed $count image(s)"
}

clear_test_images() {
    "$ADB" shell "run-as $ANDROID_PACKAGE rm -rf files/test_images" 2>/dev/null || true
}

grant_permissions() {
    echo "Granting permissions..."
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.CAMERA
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.ACCESS_FINE_LOCATION
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.ACCESS_COARSE_LOCATION
    "$ADB" shell pm grant "$ANDROID_PACKAGE" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
}

launch_app() {
    echo "Launching app in test mode..."
    "$ADB" shell "am start -n $ANDROID_PACKAGE/$ANDROID_ACTIVITY --ez test_mode true"
    sleep "$E2E_SETTLE_WAIT"
}

dump_ui_xml() {
    "$ADB" shell uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1
    "$ADB" shell cat /sdcard/ui_dump.xml
}

ui_dump_texts() {
    dump_ui_xml | python3 -c '
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.stdin)
for elem in tree.iter():
    text = elem.get("text", "").strip()
    if text:
        print(text)
'
}

tap_button_by_text() {
    local button_text="$1"
    echo "Tapping '$button_text' button..."
    "$ADB" shell input keyevent KEYCODE_WAKEUP
    sleep 0.5

    local coords
    coords=$(dump_ui_xml | python3 -c '
import re
import sys
import xml.etree.ElementTree as ET

target = sys.argv[1]
tree = ET.parse(sys.stdin)
for elem in tree.iter():
    text = elem.get("text", "")
    if target in text:
        bounds = elem.get("bounds", "")
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
        if m:
            x = (int(m.group(1)) + int(m.group(3))) // 2
            y = (int(m.group(2)) + int(m.group(4))) // 2
            print(f"{x} {y}")
            break
' "$button_text")

    if [ -z "$coords" ]; then
        echo "WARNING: Could not find '$button_text' button"
        return 1
    fi

    local x y
    read -r x y <<< "$coords"
    "$ADB" shell input tap "$x" "$y"
    echo "Tapped $button_text at ($x, $y)"
    sleep "$E2E_SETTLE_WAIT"
}

wait_for_ui_text() {
    local expected_text="$1"
    local timeout_seconds="${2:-10}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout_seconds" ]; do
        if ui_dump_texts | grep -Fq "$expected_text"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

tap_start_camera() {
    if ! tap_button_by_text "Start Camera"; then
        echo "WARNING: Could not find 'Start Camera' button, attempting center tap"
        "$ADB" shell input tap 540 1200
    fi
    sleep "$E2E_SETTLE_WAIT"
}

stop_app() {
    "$ADB" shell "am force-stop $ANDROID_PACKAGE" 2>/dev/null || true
}

clear_app_data() {
    "$ADB" shell "pm clear $ANDROID_PACKAGE" > /dev/null 2>&1 || true
}

wait_for_batch_flush() {
    echo "Waiting ${E2E_BATCH_WAIT}s for batch flush..."
    sleep "$E2E_BATCH_WAIT"
}
