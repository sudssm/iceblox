#!/bin/bash
# E2E test configuration for Android
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
E2E_SERVER_LOG="/tmp/cameras-e2e-server-$$.log"
E2E_PLATES_FILE="$PROJECT_ROOT/server/testdata/test_plates.txt"
E2E_PEPPER="default-pepper-change-me"

# Fixtures
E2E_FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Timing
E2E_HEALTHZ_TIMEOUT=15
E2E_BATCH_WAIT=35
E2E_SETTLE_WAIT=3

# Test state
E2E_PASS=0
E2E_FAIL=0
