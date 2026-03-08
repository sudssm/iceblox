#!/bin/bash
set -euo pipefail

# E2E Test Runner for Android
# Usage: e2e/android/run.sh [--skip-build]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/_e2e_config.sh"
source "$SCRIPT_DIR/lib/infra.sh"
source "$SCRIPT_DIR/lib/app.sh"
source "$SCRIPT_DIR/lib/db_queries.sh"
source "$SCRIPT_DIR/tests/test_no_plate.sh"
source "$SCRIPT_DIR/tests/test_plate.sh"

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
echo " Vilnius E2E Tests - Android"
echo "=========================================="
echo ""

echo "--- Step 1: Infrastructure ---"
start_ephemeral_postgres
start_go_server

echo ""
echo "--- Step 2: Build & Install ---"
if [ "$SKIP_BUILD" = false ]; then
    build_android_app
fi
ensure_android_emulator
install_android_app

echo ""
echo "--- Step 3: Run Tests ---"
run_test_no_plate
run_test_plate

echo ""
echo "=========================================="
echo " Results: $E2E_PASS passed, $E2E_FAIL failed"
echo "=========================================="

if [ "$E2E_FAIL" -gt 0 ]; then
    exit 1
fi
