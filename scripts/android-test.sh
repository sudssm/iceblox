#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"

DB_DSN="postgres://postgres:iceblox@localhost:5432/iceblox?sslmode=disable"
USE_PROD_SERVER=false

if [[ "${1:-}" == "--prod-server" ]]; then
    USE_PROD_SERVER=true
fi

# --- Step 1: Connect to device ---
USB_DEVICE=$(adb devices | grep -v emulator | grep -E 'device$' | head -1 | awk '{print $1}' || true)

if [ -n "$USB_DEVICE" ]; then
    echo "Found USB device: $USB_DEVICE"
    DEVICE="$USB_DEVICE"
else
    DEFAULT_ADB_HOST="192.168.1.194:36363"
    read -rp "No USB device found. ADB host:port [$DEFAULT_ADB_HOST]: " ADB_HOST
    ADB_HOST="${ADB_HOST:-$DEFAULT_ADB_HOST}"

    echo "Connecting to $ADB_HOST..."
    adb connect "$ADB_HOST"

    DEVICE=$(adb devices | grep "$ADB_HOST" | awk '{print $1}')
    if [ -z "$DEVICE" ]; then
        echo "ERROR: device $ADB_HOST not found in adb devices"
        echo "Tip: you may need to pair first: adb pair <ip>:<pairing-port>"
        exit 1
    fi
fi
echo "Connected to device: $DEVICE"

# --- Step 2: Build and install Android app ---
echo ""
if [ "$USE_PROD_SERVER" = true ]; then
    echo "Building debug APK with prod server (https://iceblox.up.railway.app)..."
    GRADLE_SERVER_FLAG="-PSERVER_URL=https://iceblox.up.railway.app"
else
    echo "Building debug APK for physical device (localhost via adb reverse)..."
    GRADLE_SERVER_FLAG="-PSERVER_URL=http://localhost:8080"
fi

cd "$ROOT/android"
./gradlew assembleDebug "$GRADLE_SERVER_FLAG"

echo ""
echo "Installing APK..."
adb -s "$DEVICE" install -r app/build/outputs/apk/debug/app-debug.apk

# --- Step 3: Launch app ---
echo ""
echo "Launching app..."
adb -s "$DEVICE" shell am force-stop com.iceblox.app
adb -s "$DEVICE" shell am start -n com.iceblox.app/.MainActivity

if [ "$USE_PROD_SERVER" = true ]; then
    echo ""
    echo "=== App launched against prod server (https://iceblox.up.railway.app) ==="
    exit 0
fi

# --- Step 4 (local only): Start PostgreSQL if needed ---
if ! docker ps --format '{{.Names}}' | grep -q iceblox-postgres-test; then
    echo ""
    echo "Stopping local PostgreSQL (if running)..."
    brew services stop postgresql@17 2>/dev/null || true

    echo "Waiting for port 5432..."
    for i in $(seq 1 10); do
        if ! lsof -i :5432 -sTCP:LISTEN >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    echo "Starting PostgreSQL (Docker)..."
    docker run --name iceblox-postgres-test -e POSTGRES_DB=iceblox -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=iceblox -p 5432:5432 -d postgres:16-alpine 2>/dev/null || docker start iceblox-postgres-test
    sleep 2
else
    echo ""
    echo "PostgreSQL (Docker) already running"
fi

# --- Step 5 (local only): Set up reverse port forwarding ---
echo ""
echo "Setting up adb reverse port forwarding (phone:8080 -> host:8080)..."
adb -s "$DEVICE" reverse tcp:8080 tcp:8080

# --- Step 6 (local only): Run Go server in foreground ---
cd "$ROOT"
if [ ! -f server/data/plates.txt ]; then
    echo ""
    echo "Downloading and extracting plate data..."
    make setup
    make extract
fi
echo ""
echo "=== App launched! Starting Go server with $(wc -l < server/data/plates.txt | tr -d ' ') plates (Ctrl+C to stop) ==="
echo ""
make run-server DB_DSN="$DB_DSN"
