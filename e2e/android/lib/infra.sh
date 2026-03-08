#!/bin/bash
# Infrastructure lifecycle: ephemeral postgres + Go server

find_free_port() {
    python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()"
}

start_ephemeral_postgres() {
    E2E_PG_PORT=$(find_free_port)
    echo "Starting ephemeral postgres on port $E2E_PG_PORT (container: $E2E_PG_CONTAINER)..."
    docker run --name "$E2E_PG_CONTAINER" \
        -e POSTGRES_DB="$E2E_PG_DB" \
        -e POSTGRES_USER="$E2E_PG_USER" \
        -e POSTGRES_PASSWORD="$E2E_PG_PASSWORD" \
        -p "$E2E_PG_PORT:5432" \
        -d postgres:16-alpine

    local retries=0
    while ! docker exec "$E2E_PG_CONTAINER" pg_isready -U "$E2E_PG_USER" -d "$E2E_PG_DB" &>/dev/null; do
        retries=$((retries + 1))
        if [ "$retries" -gt 30 ]; then
            echo "ERROR: Postgres failed to start within 30 seconds"
            return 1
        fi
        sleep 1
    done
    echo "Postgres ready on port $E2E_PG_PORT"
}

stop_ephemeral_postgres() {
    echo "Stopping ephemeral postgres ($E2E_PG_CONTAINER)..."
    docker rm -f "$E2E_PG_CONTAINER" 2>/dev/null || true
}

e2e_dsn() {
    echo "postgres://$E2E_PG_USER:$E2E_PG_PASSWORD@localhost:$E2E_PG_PORT/$E2E_PG_DB?sslmode=disable"
}

start_go_server() {
    echo "Starting Go server on port $E2E_SERVER_PORT..."
    cd "$PROJECT_ROOT/server"
    go run ./cmd/server/... \
        --port "$E2E_SERVER_PORT" \
        --plates-file "$E2E_PLATES_FILE" \
        --pepper "$E2E_PEPPER" \
        --db-dsn "$(e2e_dsn)" \
        > "$E2E_SERVER_LOG" 2>&1 &
    E2E_SERVER_PID=$!
    cd "$PROJECT_ROOT"

    local retries=0
    while ! curl -sf "http://localhost:$E2E_SERVER_PORT/healthz" &>/dev/null; do
        retries=$((retries + 1))
        if [ "$retries" -gt "$E2E_HEALTHZ_TIMEOUT" ]; then
            echo "ERROR: Server /healthz not responding after ${E2E_HEALTHZ_TIMEOUT}s"
            echo "Server log:"
            cat "$E2E_SERVER_LOG"
            return 1
        fi
        sleep 1
    done

    local healthz
    healthz=$(curl -sf "http://localhost:$E2E_SERVER_PORT/healthz")
    echo "Server healthy: $healthz"
}

stop_go_server() {
    if [ -n "$E2E_SERVER_PID" ]; then
        echo "Stopping Go server (PID $E2E_SERVER_PID)..."
        kill "$E2E_SERVER_PID" 2>/dev/null || true
        wait "$E2E_SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$E2E_SERVER_LOG"
}
