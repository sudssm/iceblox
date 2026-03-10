#!/bin/bash
# iOS app lifecycle for E2E tests

find_ios_app_path() {
    find "$IOS_BUILD_DIR" -name "${IOS_SCHEME}.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1
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

clear_session_summary_artifacts() {
    local container
    container="$(app_data_container)"
    rm -f "$container/Library/Application Support/$E2E_IOS_STOP_RECORDING_TRIGGER_FILENAME"
    rm -f "$container/Library/Application Support/$E2E_IOS_SESSION_SUMMARY_FILENAME"
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
    SIMCTL_CHILD_E2E_SKIP_NOTIFICATION_REQUEST=1 \
    SIMCTL_CHILD_E2E_REQUEST_LOCATION_PERMISSION=0 \
    SIMCTL_CHILD_E2E_BATCH_INTERVAL_SECONDS="$E2E_IOS_BATCH_INTERVAL_SECONDS" \
    SIMCTL_CHILD_E2E_SERVER_BASE_URL="http://localhost:$E2E_SERVER_PORT" \
    SIMCTL_CHILD_E2E_USE_SPLASH_TRIGGER=1 \
    SIMCTL_CHILD_E2E_USE_STOP_RECORDING_TRIGGER=1 \
    SIMCTL_CHILD_E2E_SPLASH_TRIGGER_FILENAME="$E2E_IOS_SPLASH_TRIGGER_FILENAME" \
    SIMCTL_CHILD_E2E_STOP_RECORDING_TRIGGER_FILENAME="$E2E_IOS_STOP_RECORDING_TRIGGER_FILENAME" \
    SIMCTL_CHILD_E2E_SESSION_SUMMARY_FILENAME="$E2E_IOS_SESSION_SUMMARY_FILENAME" \
    SIMCTL_CHILD_SIMULATOR_FRAME_INTERVAL_MS="$E2E_IOS_FRAME_INTERVAL_MS" \
    SIMCTL_CHILD_SIMULATOR_TEST_IMAGES_DIRNAME="$E2E_IOS_TEST_IMAGES_DIRNAME" \
    xcrun simctl launch "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null

    sleep "$E2E_SETTLE_WAIT"
}

tap_start_camera() {
    echo "Triggering 'Start Camera' via splash trigger file..."
    local container
    container="$(app_data_container)"
    mkdir -p "$container/Library/Application Support"
    touch "$container/Library/Application Support/$E2E_IOS_SPLASH_TRIGGER_FILENAME"

    local elapsed=0
    local timeout=10
    while [ "$elapsed" -lt "$timeout" ]; do
        if [ ! -f "$container/Library/Application Support/$E2E_IOS_SPLASH_TRIGGER_FILENAME" ]; then
            echo "  Splash trigger consumed by app"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    sleep 2
}

stop_app() {
    xcrun simctl terminate "$IOS_DEVICE_UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
}

trigger_stop_recording() {
    local container
    container="$(app_data_container)"
    mkdir -p "$container/Library/Application Support"
    touch "$container/Library/Application Support/$E2E_IOS_STOP_RECORDING_TRIGGER_FILENAME"
}

wait_for_session_summary_artifact() {
    local timeout_seconds="${1:-10}"
    local elapsed=0
    local container
    container="$(app_data_container)"
    local summary_path="$container/Library/Application Support/$E2E_IOS_SESSION_SUMMARY_FILENAME"

    while [ "$elapsed" -lt "$timeout_seconds" ]; do
        if [ -f "$summary_path" ]; then
            echo "$summary_path"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

wait_for_batch_flush() {
    echo "Waiting ${E2E_BATCH_WAIT}s for batch flush..."
    sleep "$E2E_BATCH_WAIT"
}
