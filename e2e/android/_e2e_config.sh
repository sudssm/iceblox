#!/bin/bash
# E2E test configuration for Android
# Sources the shared simulator config, then adds E2E-specific variables.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/simulator/_config.sh"

# Java (needed for Gradle builds)
if [ -z "$JAVA_HOME" ]; then
    export JAVA_HOME="$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
fi

# Ephemeral postgres
E2E_PG_CONTAINER="iceblox-e2e-postgres-$$"
E2E_PG_PORT=""
E2E_PG_USER="postgres"
E2E_PG_PASSWORD="e2e_iceblox"
E2E_PG_DB="iceblox_e2e"

# Go server
E2E_SERVER_PORT=8080
E2E_SERVER_PID=""
E2E_SERVER_LOG="/tmp/iceblox-e2e-server-$$.log"
E2E_PLATES_FILE="$PROJECT_ROOT/server/testdata/test_plates.txt"
source "$SCRIPT_DIR/../../.env"
E2E_PEPPER="$PEPPER"

# Fixtures
E2E_FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Timing
E2E_HEALTHZ_TIMEOUT=15
E2E_BATCH_WAIT=35
E2E_SETTLE_WAIT=3

# Test state
E2E_PASS=0
E2E_FAIL=0
