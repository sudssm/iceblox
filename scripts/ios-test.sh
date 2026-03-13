#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DB_DSN="postgres://postgres:iceblox@localhost:5432/iceblox?sslmode=disable"
PROD_SERVER_URL="https://iceblox.up.railway.app"
USE_PROD_SERVER=false

if [[ "${1:-}" == "--prod-server" ]]; then
    USE_PROD_SERVER=true
fi

# --- Step 1: Find connected iOS device ---
echo "Looking for connected iOS devices..."
DEVICE_LINE=$(xcrun xctrace list devices 2>&1 \
    | sed -n '/== Devices ==/,/== Simulators ==/p' \
    | grep -iE "iphone|ipad" \
    | head -1 || true)

if [ -z "$DEVICE_LINE" ]; then
    echo "ERROR: No connected iOS device found."
    echo "Make sure your device is:"
    echo "  - Connected via USB"
    echo "  - Trusted on this Mac"
    echo "  - Developer mode enabled (Settings > Privacy & Security > Developer Mode)"
    exit 1
fi

DEVICE_UDID=$(echo "$DEVICE_LINE" | rev | cut -d'(' -f1 | rev | tr -d ')')
DEVICE_NAME=$(echo "$DEVICE_LINE" | sed "s/ ($DEVICE_UDID)//" | sed 's/[[:space:]]*$//')
echo "Found device: $DEVICE_NAME ($DEVICE_UDID)"

# --- Step 2: Build iOS app ---
echo ""
EXTRA_SWIFT_FLAGS=""
if [ "$USE_PROD_SERVER" = true ]; then
    echo "Building with production server ($PROD_SERVER_URL)..."
    EXTRA_SWIFT_FLAGS="-DPRODUCTION_SERVER"
else
    LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
    if [ -n "$LOCAL_IP" ]; then
        echo "Building for local server (http://$LOCAL_IP:8080)..."
    else
        echo "WARNING: Could not detect local IP. The app will use localhost:8080 which won't work on device."
        echo "Ensure Mac and device are on the same network, or use --prod-server."
    fi
fi

echo "Building for device..."
cd "$ROOT"
xcodebuild build \
    -project ios/IceBloxApp.xcodeproj \
    -scheme IceBloxApp \
    -destination "generic/platform=iOS" \
    -derivedDataPath ios/build \
    -allowProvisioningUpdates \
    ${EXTRA_SWIFT_FLAGS:+OTHER_SWIFT_FLAGS="$EXTRA_SWIFT_FLAGS"} \
    -quiet

# --- Step 3: Install on device ---
APP_PATH=$(find ios/build -name "IceBloxApp.app" -path "*/Debug-iphoneos/*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "ERROR: App bundle not found. Build may have failed."
    exit 1
fi

echo ""
echo "Installing on device..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"

# --- Step 4: Launch ---
# For local testing, pass the local IP via env var so the app connects to the Mac's server.
# For prod, the PRODUCTION_SERVER flag bakes in the Railway URL at compile time.
echo ""
echo "Launching app..."
if [ "$USE_PROD_SERVER" = true ]; then
    xcrun devicectl device process launch --device "$DEVICE_UDID" com.iceblox.app
    echo ""
    echo "=== App launched against prod server ($PROD_SERVER_URL) ==="
    exit 0
else
    if [ -n "${LOCAL_IP:-}" ]; then
        xcrun devicectl device process launch --device "$DEVICE_UDID" -e '{"SERVER_BASE_URL":"http://'"$LOCAL_IP"':8080"}' com.iceblox.app
    else
        xcrun devicectl device process launch --device "$DEVICE_UDID" com.iceblox.app
    fi
fi

# --- Step 5 (local only): Start PostgreSQL if needed ---
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
