#!/bin/bash
set -euo pipefail

# E2E Test Runner for iOS
# Usage: e2e/ios/run.sh [--skip-build]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/_e2e_config.sh"
source "$SCRIPT_DIR/../android/lib/infra.sh"
source "$SCRIPT_DIR/../android/lib/db_queries.sh"
source "$SCRIPT_DIR/lib/app.sh"
source "$SCRIPT_DIR/tests/test_no_plate.sh"
source "$SCRIPT_DIR/tests/test_non_target_plate.sh"
source "$SCRIPT_DIR/tests/test_target_plate.sh"
source "$SCRIPT_DIR/tests/test_batch_upload.sh"
source "$SCRIPT_DIR/tests/test_proximity_alerts.sh"
source "$SCRIPT_DIR/tests/test_device_registration.sh"
source "$SCRIPT_DIR/tests/test_match_debug_label.sh"
source "$SCRIPT_DIR/tests/test_queued_clears.sh"
source "$SCRIPT_DIR/tests/test_report_ice.sh"

SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

cleanup() {
    echo ""
    echo "=== CLEANUP ==="
    stop_app 2>/dev/null || true
    stop_go_server 2>/dev/null || true
    stop_ephemeral_postgres 2>/dev/null || true
    echo "Cleanup complete."
}
trap cleanup EXIT

echo "=========================================="
echo " Vilnius E2E Tests - iOS"
echo "=========================================="
echo ""

echo "--- Step 1: Infrastructure ---"
start_ephemeral_postgres
start_go_server

echo ""
echo "--- Step 2: Build & Install ---"
if [ "$SKIP_BUILD" = false ]; then
    build_ios_app
fi
install_ios_app

echo ""
echo "--- Step 3: Run Tests ---"
run_test_no_plate
run_test_non_target_plate
run_test_target_plate
run_test_batch_upload
run_test_proximity_subscribe_nearby
run_test_proximity_subscribe_distant
run_test_device_registration
run_test_match_debug_label
run_test_queued_clears
run_test_report_ice

echo ""
echo "=========================================="
echo " Results: $E2E_PASS passed, $E2E_FAIL failed"
echo "=========================================="

if [ "$E2E_FAIL" -gt 0 ]; then
    exit 1
fi
