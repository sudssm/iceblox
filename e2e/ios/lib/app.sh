#!/bin/bash
# iOS app lifecycle for E2E tests

find_ios_app_path() {
    find "$IOS_BUILD_DIR" -name "CamerasApp.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1
}

build_ios_app() {
    echo "Building iOS app..."
    ensure_ios_simulator
    xcodebuild build \
        -project "$IOS_PROJECT" \
        -scheme "$IOS_SCHEME" \
        -destination "platform=iOS Simulator,id=$IOS_DEVICE_UDID" \
        -derivedDataPath "$IOS_BUILD_DIR" \
        -quiet

    local app_path
    app_path="$(find_ios_app_path)"
    if [ ! -d "$app_path" ]; then
        echo "ERROR: App bundle not found in $IOS_BUILD_DIR"
        return 1
    fi
    echo "App built: $app_path"
}

install_ios_app() {
    ensure_ios_simulator

    local app_path
    app_path="$(find_ios_app_path)"
    if [ ! -d "$app_path" ]; then
        echo "ERROR: App bundle not found. Run build first."
        return 1
    fi

    echo "Installing app on simulator..."
    xcrun simctl install "$IOS_DEVICE_UDID" "$app_path" >/dev/null
}

clear_app_data() {
    stop_app
    xcrun simctl uninstall "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
    install_ios_app
}

app_data_container() {
    xcrun simctl get_app_container "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" data
}

clear_test_images() {
    local container
    container="$(app_data_container)"
    rm -rf "$container/Library/Application Support/$E2E_IOS_TEST_IMAGES_DIRNAME"
}

push_test_images() {
    local image_dir="$1"
    local container
    container="$(app_data_container)"

    local runtime_dir="$container/Library/Application Support/$E2E_IOS_TEST_IMAGES_DIRNAME"
    rm -rf "$runtime_dir"
    mkdir -p "$runtime_dir"

    local count=0
    local file
    for file in "$image_dir"/*; do
        [ -f "$file" ] || continue
        case "${file##*.}" in
            png|jpg|jpeg|bmp)
                count=$((count + 1))
                ;;
            txt)
                ;;
            *)
                continue
                ;;
        esac
        cp "$file" "$runtime_dir/"
    done

    echo "Pushed $count image(s) to $runtime_dir"
}

launch_app() {
    echo "Launching app in E2E mode..."
    SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
    SIMCTL_CHILD_E2E_BATCH_INTERVAL_SECONDS="$E2E_IOS_BATCH_INTERVAL_SECONDS" \
    SIMCTL_CHILD_E2E_SERVER_BASE_URL="http://localhost:$E2E_SERVER_PORT" \
    SIMCTL_CHILD_E2E_USE_SPLASH_TRIGGER=1 \
    SIMCTL_CHILD_E2E_SPLASH_TRIGGER_FILENAME="$E2E_IOS_SPLASH_TRIGGER_FILENAME" \
    SIMCTL_CHILD_SIMULATOR_FRAME_INTERVAL_MS="$E2E_IOS_FRAME_INTERVAL_MS" \
    SIMCTL_CHILD_SIMULATOR_TEST_IMAGES_DIRNAME="$E2E_IOS_TEST_IMAGES_DIRNAME" \
    xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null

    sleep "$E2E_SETTLE_WAIT"
}

tap_start_camera() {
    echo "Tapping 'Start Camera' button..."

    local screenshot="/tmp/cameras-ios-splash-$$.png"
    xcrun simctl io "$IOS_DEVICE_UDID" screenshot "$screenshot" >/dev/null 2>&1

    local coords
    coords="$(python3 - "$screenshot" 2>/dev/null <<'PY'
from collections import deque
from PIL import Image
import sys

img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size

left = int(w * 0.1)
top = int(h * 0.2)
right = int(w * 0.9)
bottom = int(h * 0.85)
crop = img.crop((left, top, right, bottom))

scale = 4
small = crop.resize((max(1, crop.width // scale), max(1, crop.height // scale)))
sw, sh = small.size
pixels = small.load()
visited = bytearray(sw * sh)

def is_white(x, y):
    r, g, b = pixels[x, y]
    return r >= 235 and g >= 235 and b >= 235

best = None
best_area = 0

for y in range(sh):
    for x in range(sw):
        idx = y * sw + x
        if visited[idx] or not is_white(x, y):
            continue

        queue = deque([(x, y)])
        visited[idx] = 1
        area = 0
        min_x = max_x = x
        min_y = max_y = y

        while queue:
            cx, cy = queue.popleft()
            area += 1
            min_x = min(min_x, cx)
            max_x = max(max_x, cx)
            min_y = min(min_y, cy)
            max_y = max(max_y, cy)

            for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if 0 <= nx < sw and 0 <= ny < sh:
                    nidx = ny * sw + nx
                    if not visited[nidx] and is_white(nx, ny):
                        visited[nidx] = 1
                        queue.append((nx, ny))

        if area > best_area:
            best_area = area
            best = (min_x, min_y, max_x, max_y)

if best and best_area >= 200:
    min_x, min_y, max_x, max_y = best
    center_x = left + ((min_x + max_x + 1) * scale) // 2
    center_y = top + ((min_y + max_y + 1) * scale) // 2
    print(f"{center_x} {center_y}")
PY
)" || true

    local detected_coords=true

    rm -f "$screenshot"

    if [ -z "$coords" ]; then
        detected_coords=false
        coords="$E2E_IOS_START_CAMERA_X $E2E_IOS_START_CAMERA_Y"
        echo "  WARNING: Could not detect splash button from screenshot, using fallback coords ($coords)"
    fi

    local x y
    read -r x y <<< "$coords"
    "$PROJECT_ROOT/scripts/simulator/tap.sh" ios "$x" "$y"

    sleep 1

    local post_tap="/tmp/cameras-ios-post-tap-$$.png"
    xcrun simctl io "$IOS_DEVICE_UDID" screenshot "$post_tap" >/dev/null 2>&1
    local remaining_button
    remaining_button="$(python3 - "$post_tap" 2>/dev/null <<'PY'
from collections import deque
from PIL import Image
import sys

img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size
left = int(w * 0.1)
top = int(h * 0.2)
right = int(w * 0.9)
bottom = int(h * 0.85)
crop = img.crop((left, top, right, bottom))
scale = 4
small = crop.resize((max(1, crop.width // scale), max(1, crop.height // scale)))
sw, sh = small.size
pixels = small.load()
visited = bytearray(sw * sh)

def is_white(x, y):
    r, g, b = pixels[x, y]
    return r >= 235 and g >= 235 and b >= 235

best_area = 0

for y in range(sh):
    for x in range(sw):
        idx = y * sw + x
        if visited[idx] or not is_white(x, y):
            continue

        queue = deque([(x, y)])
        visited[idx] = 1
        area = 0

        while queue:
            cx, cy = queue.popleft()
            area += 1
            for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if 0 <= nx < sw and 0 <= ny < sh:
                    nidx = ny * sw + nx
                    if not visited[nidx] and is_white(nx, ny):
                        visited[nidx] = 1
                        queue.append((nx, ny))

        best_area = max(best_area, area)

print("present" if best_area >= 200 else "")
PY
)" || true
    rm -f "$post_tap"

    if [ "$detected_coords" = false ] || [ -n "$remaining_button" ]; then
        echo "  INFO: Splash button still visible after tap, triggering the same start-camera path via app signal"
        local container
        container="$(app_data_container)"
        mkdir -p "$container/Library/Application Support"
        touch "$container/Library/Application Support/$E2E_IOS_SPLASH_TRIGGER_FILENAME"
    fi

    sleep 2
}

stop_app() {
    xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
}

wait_for_batch_flush() {
    echo "Waiting ${E2E_BATCH_WAIT}s for batch flush..."
    sleep "$E2E_BATCH_WAIT"
}
