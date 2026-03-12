#!/bin/bash
# Database query helpers for E2E verification
# Uses docker exec to run psql inside the ephemeral container (no local psql needed)

e2e_psql() {
    docker exec -e PGPASSWORD="$E2E_PG_PASSWORD" "$E2E_PG_CONTAINER" \
        psql -U "$E2E_PG_USER" -d "$E2E_PG_DB" -t -A "$@"
}

count_sightings() {
    e2e_psql -c "SELECT COUNT(*) FROM sightings;"
}

count_sightings_for_plate() {
    local plate_text="$1"
    e2e_psql -c "
        SELECT COUNT(*)
        FROM sightings s
        JOIN plates p ON s.plate_id = p.id
        WHERE p.plate = '$plate_text';
    "
}

get_latest_sighting() {
    e2e_psql -c "
        SELECT p.plate, s.seen_at, s.latitude, s.longitude, s.hardware_id
        FROM sightings s
        JOIN plates p ON s.plate_id = p.id
        ORDER BY s.seen_at DESC
        LIMIT 1;
    "
}

get_sighting_coords() {
    e2e_psql -c "
        SELECT s.latitude, s.longitude
        FROM sightings s
        ORDER BY s.seen_at DESC
        LIMIT 1;
    "
}

truncate_sightings() {
    e2e_psql -c "TRUNCATE sightings CASCADE;"
}

assert_sighting_count() {
    local expected="$1"
    local description="$2"
    local actual
    actual=$(count_sightings | tr -d '[:space:]')
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $description (sightings=$actual)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: $description (expected=$expected, actual=$actual)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi
}

assert_sighting_exists_for_plate() {
    local plate_text="$1"
    local description="$2"
    local count
    count=$(count_sightings_for_plate "$plate_text" | tr -d '[:space:]')
    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "  PASS: $description (found $count sighting(s) for $plate_text)"
        E2E_PASS=$((E2E_PASS + 1))
    else
        echo "  FAIL: $description (no sightings found for $plate_text)"
        E2E_FAIL=$((E2E_FAIL + 1))
    fi
}

count_device_tokens() {
    e2e_psql -c "SELECT COUNT(*) FROM device_tokens;"
}

truncate_device_tokens() {
    e2e_psql -c "TRUNCATE device_tokens CASCADE;"
}

count_reports() {
    e2e_psql -c "SELECT COUNT(*) FROM reports;"
}

truncate_reports() {
    e2e_psql -c "TRUNCATE reports CASCADE;"
}

get_latest_report() {
    e2e_psql -c "
        SELECT id, description, plate_number, latitude, longitude, photo_path, hardware_id, stop_ice_status
        FROM reports
        ORDER BY id DESC
        LIMIT 1;
    "
}

count_map_sightings() {
    local lat="$1"
    local lng="$2"
    local radius="$3"
    local response
    response=$(curl -sf "http://localhost:$E2E_SERVER_PORT/api/v1/map-sightings?lat=$lat&lng=$lng&radius=$radius" 2>/dev/null)
    echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('sightings',[])))" 2>/dev/null
}

get_report_field() {
    local field="$1"
    # Validate field name contains only safe characters (letters, underscores)
    if ! echo "$field" | grep -qE '^[a-z_]+$'; then
        echo "ERROR: invalid field name: $field" >&2
        return 1
    fi
    e2e_psql -c "
        SELECT $field
        FROM reports
        ORDER BY id DESC
        LIMIT 1;
    "
}
