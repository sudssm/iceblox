#!/bin/bash
# E2E test configuration for iOS
# Sources the shared simulator config, then adds E2E-specific variables.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/simulator/_config.sh"

# Ephemeral postgres
E2E_PG_CONTAINER="cameras-e2e-postgres-$$"
E2E_PG_PORT=""
E2E_PG_USER="postgres"
E2E_PG_PASSWORD="e2e_cameras"
E2E_PG_DB="cameras_e2e"

# Go server
E2E_SERVER_PORT=8080
E2E_SERVER_PID=""
E2E_SERVER_LOG="/tmp/cameras-e2e-ios-server-$$.log"
E2E_PLATES_FILE="$PROJECT_ROOT/server/testdata/test_plates.txt"
E2E_PEPPER="default-pepper-change-me"

# Fixtures
E2E_FIXTURES_DIR="$PROJECT_ROOT/e2e/android/fixtures"
E2E_IOS_TEST_IMAGES_DIRNAME="test_images"

# Timing
E2E_HEALTHZ_TIMEOUT=15
E2E_BATCH_WAIT=6
E2E_SETTLE_WAIT=4
E2E_IOS_BATCH_INTERVAL_SECONDS=1
E2E_IOS_FRAME_INTERVAL_MS=100
E2E_IOS_START_CAMERA_X=590
E2E_IOS_START_CAMERA_Y=1410
E2E_IOS_SPLASH_TRIGGER_FILENAME="e2e_start_camera.trigger"
E2E_IOS_STOP_RECORDING_TRIGGER_FILENAME="e2e_stop_recording.trigger"
E2E_IOS_SESSION_SUMMARY_FILENAME="e2e_session_summary.txt"

# Test state
E2E_PASS=0
E2E_FAIL=0
