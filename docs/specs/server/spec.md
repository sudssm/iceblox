# Server Specification

> **Status:** v2 — PostgreSQL persistence for target plates and sightings.

## Purpose

Receive hashed license plate identifiers from mobile clients, compare against a target list of ICE vehicle plates, persist sighting records to a PostgreSQL database, and return per-plate match status to the device.

## Target Data Source

Target plates come from [StopICE Plate Tracker](https://www.stopice.net/platetracker/?data=1), a public database of ICE vehicle license plates (~2,600 unique plates as of March 2026). The data is published as a nightly-compiled ZIP archive containing an XML file with `<vehicle_license>` entries.

**Data pipeline:**
1. `make setup` — Downloads the latest ZIP archive from stopice.net
2. `make extract` — Parses the XML, normalizes plates, and writes `data/plates.txt` (one plate per line)
3. The Go server loads `data/plates.txt` at startup, computes HMAC-SHA256 hashes, and seeds the `plates` table in PostgreSQL

## Technology

- **Language**: Go
- **Framework**: `net/http` (standard library)
- **Database**: PostgreSQL (via `pgx` driver with `database/sql`)
- **Target list source**: `data/plates.txt` — plaintext plate list extracted from StopICE data, seeded into the `plates` database table on startup

## Requirements

### REQ-S-1: Receive Hashed Plates

The server MUST expose an HTTP endpoint that accepts a single hashed plate submission.

```
POST /api/v1/plates
Content-Type: application/json
X-Device-ID: <device identifier>

{
  "plate_hash": "string (64-char hex, HMAC-SHA256)",
  "latitude": number,
  "longitude": number,
  "timestamp": "string (ISO 8601 / RFC 3339, optional)"
}
```

**Field validation:**
- `plate_hash`: Required. MUST be a 64-character hexadecimal string.
- `latitude`: Required. MUST be in range [-90, 90].
- `longitude`: Required. MUST be in range [-180, 180].
- `timestamp`: Optional. ISO 8601 / RFC 3339 format (e.g., `"2026-03-08T14:30:00Z"`). If omitted or unparseable, defaults to the server's current UTC time. Represents when the plate was seen by the device.

**Headers:**
- `X-Device-ID`: Optional. Identifies the submitting device. If omitted, recorded as `"unknown"`. Maps to `hardware_id` in the sightings table.

**Response (200 OK):**
```json
{
  "status": "ok",
  "matched": true
}
```

**Error responses:**
- `400 Bad Request` — malformed JSON or failed field validation. Body: `{"error": "description"}`.
- `405 Method Not Allowed` — non-POST request to this endpoint.
- `500 Internal Server Error` — database write failure. Body: `{"error": "failed to record sighting"}`.

> **Future:** Batch submissions (array of plates + device_id) will be added when offline queue flush is needed.

### REQ-S-2: Compare Against Targets

The server MUST compare each received hash against a pre-computed set of HMAC-SHA256 target hashes loaded from the `plates` database table into an in-memory set. Lookup MUST be O(1).

### REQ-S-3: Persist Sightings

When a plate hash matches a target, the server MUST insert a record into the `sightings` database table with:
- `plate_id`: Foreign key to the matched plate in the `plates` table
- `seen_at`: Timestamp from the request (or server time if omitted)
- `latitude` / `longitude`: GPS coordinates from the request
- `hardware_id`: Device identifier from the `X-Device-ID` header

Non-matching hashes MUST NOT be persisted (privacy model: non-target plates are never stored).

### REQ-S-4: Response

The server MUST return a per-plate match boolean in the response body. The response format is `{"status": "ok", "matched": true|false}`. No target details are revealed to the device.

### REQ-S-5: Target Plate Loading

The server MUST load target plates from a plaintext file (`data/plates.txt`) at startup and seed them into the `plates` database table.

**On startup, the server:**
1. Reads `data/plates.txt` (one plate per line)
2. Normalizes each plate (uppercase, strip whitespace/hyphens)
3. Computes HMAC-SHA256 of each normalized plate using the shared pepper
4. Upserts each (plate, hash) pair into the `plates` table (ON CONFLICT updates the plate text)
5. Loads all (hash → plate_id) mappings from the database into an in-memory set for O(1) lookup

**Data preparation (via Makefile):**
```bash
make setup    # Download latest ZIP from stopice.net
make extract  # Parse XML → data/plates.txt
make db       # Start PostgreSQL via Docker
```

The server MUST support reloading the plates file without restart (e.g., via SIGHUP). On reload, the server re-reads the file, re-seeds the database, and rebuilds the in-memory hash set.

### REQ-S-6: Rate Limiting

The server MUST enforce per-device rate limiting:

- **Limit**: 20 plates per minute per `device_id`
- **Window**: Sliding window (or fixed 60-second buckets)
- **Enforcement**: When a device exceeds the limit, the server MUST respond with `429 Too Many Requests` and a `Retry-After` header (in seconds)
- **Implementation**: In-memory rate limiter (e.g., token bucket or sliding window counter keyed by `device_id`)

```json
HTTP 429
{
  "error": "rate_limit_exceeded",
  "retry_after": 30
}
```

The app MUST handle 429 responses by backing off for the specified duration and keeping plates in the offline queue.

### REQ-S-7: Health Check

The server MUST expose a `GET /healthz` endpoint returning `200 OK` with:

```json
{
  "status": "ok",
  "targets_loaded": 100
}
```

### REQ-S-8: Database Schema

The server MUST use PostgreSQL with the following schema:

**Table: `plates`** — target plates from StopICE data
```sql
CREATE TABLE plates (
    id      SERIAL PRIMARY KEY,
    plate   TEXT NOT NULL,           -- raw normalized plate text (e.g., "ABC1234")
    hash    VARCHAR(64) NOT NULL UNIQUE  -- HMAC-SHA256 hash (matches value sent from phone)
);
```

**Table: `sightings`** — records of matched target plate observations
```sql
CREATE TABLE sightings (
    id          SERIAL PRIMARY KEY,
    plate_id    INTEGER NOT NULL REFERENCES plates(id),  -- FK to matched plate
    seen_at     TIMESTAMPTZ NOT NULL,                    -- when the plate was seen
    latitude    DOUBLE PRECISION NOT NULL,               -- GPS latitude
    longitude   DOUBLE PRECISION NOT NULL,               -- GPS longitude
    hardware_id TEXT NOT NULL                             -- device identifier
);

CREATE INDEX idx_sightings_plate_id ON sightings(plate_id);
CREATE INDEX idx_sightings_seen_at ON sightings(seen_at);
```

**Data flow:**
1. On startup, plates from `data/plates.txt` are upserted into the `plates` table
2. Hash → plate_id mappings are loaded into memory for O(1) lookup
3. When a submitted hash matches, a sighting is inserted with the plate's ID, timestamp, GPS, and device ID
4. Non-matching hashes are never written to the database

**Connection:** Configured via `--db-dsn` flag. Default: `postgres://postgres:cameras@localhost:5432/cameras?sslmode=disable`. Migrations run automatically on startup using `CREATE TABLE IF NOT EXISTS`.

## Out of Scope (v1)

- Alerting / notification system (future: separate monitoring app)
- Admin dashboard
- User authentication
- Device registration
- Analytics / reporting
- Target plate management CRUD (future: third-party API integration)

## TODO

- [ ] **Monitoring app**: Separate application (own spec TBD) that provides a REST API for querying target plate sightings by geography:

  ```
  GET /api/v1/sightings?lat=31.76&lng=-106.48&radius_km=5
  ```

  Response: list of target plate sightings within the radius, including target label, GPS coordinates, timestamp, and device_id. Data source: the `sightings` database table.

- [ ] **Third-party target API**: Replace the seed file with a live integration that pulls target plates from an external source.

## Resolved Decisions

| Question | Decision |
|---|---|
| Language / framework | Go with `net/http` |
| Target list source | StopICE plate tracker data (plaintext `plates.txt` extracted via Makefile) |
| Alert delivery | No alerting from server to device. Separate monitoring app (TODO) |
| Match results to device | Yes — per-plate boolean only, no target details |
| Storage | PostgreSQL — `plates` table for targets, `sightings` table for matched observations |
| Monitoring app data source | REST API querying `sightings` table |
| Rate limiting | 20 plates/minute per device_id, 429 response with Retry-After |

## Open Questions

- [ ] Should the server require an API key or shared secret from devices (beyond device_id)?

---

## Implementation Plan

### Project Structure

```
server/
├── cmd/
│   └── server/
│       └── main.go              # Entrypoint, flag parsing, DB init, signal handling
├── internal/
│   ├── config/
│   │   └── config.go            # CLI flags, env vars, config struct
│   ├── db/
│   │   └── db.go                # PostgreSQL connection, migrations, plate/sighting operations
│   ├── targets/
│   │   └── targets.go           # Load plates.txt, compute hashes, in-memory hash→plate_id map
│   ├── matcher/
│   │   └── matcher.go           # Constant-time hash comparison logic
│   ├── ratelimit/
│   │   └── ratelimit.go         # Per-device token bucket rate limiter
│   └── handler/
│       ├── plates.go            # POST /api/v1/plates handler
│       ├── health.go            # GET /healthz handler
│       └── logger.go            # JSONL file writer (legacy, optional)
├── data/                        # Downloaded plate data (gitignored)
│   └── plates.txt               # Extracted plates, one per line
├── Makefile                     # setup, extract, db, run-server targets
├── go.mod
└── go.sum
```

### Implementation Order

Each step is independently testable. Later steps depend on earlier ones.

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project scaffold | — | `go mod init`, directory structure, `main.go` with flag parsing |
| 2 | Config | — | Parse CLI flags: `--port`, `--plates-file`, `--db-dsn`, `--pepper`; env var overrides |
| 3 | Database | REQ-S-8 | Connect to PostgreSQL, run migrations, plate upsert, sighting insert |
| 4 | Target loader | REQ-S-5 | Load plates.txt, compute HMAC hashes, seed DB, build in-memory hash→plate_id map |
| 5 | Matcher | REQ-S-2 | O(1) in-memory hash lookup, return plate_id for matched hashes |
| 6 | Rate limiter | REQ-S-6 | Token bucket per device_id, 429 response with Retry-After |
| 7 | Plates handler | REQ-S-1, REQ-S-3, REQ-S-4 | Parse request, validate fields, check match, record sighting to DB, return response |
| 8 | Health handler | REQ-S-7 | Return status + targets_loaded count |
| 9 | Integration | All | Wire handlers into `http.ServeMux`, graceful shutdown, SIGHUP reload with DB re-seed |
| 10 | Tests | All | Unit tests per package, integration test with seed file + HTTP requests + mock recorder |

### Key Technical Notes

- **External dependency**: `github.com/jackc/pgx/v5` for PostgreSQL driver (via `database/sql` interface).
- **Schema migrations**: Run on startup via `CREATE TABLE IF NOT EXISTS`. No migration framework needed for v1.
- **In-memory cache**: Hash → plate_id map in `targets.Store` provides O(1) lookup without per-request DB queries. DB is only written to (sighting inserts), not read on the hot path.
- **Plates file reload**: Register `SIGHUP` handler in `main.go` → calls `targets.Reload()` → re-reads `plates.txt`, re-computes hashes, re-seeds DB via upsert, rebuilds in-memory map.
- **Rate limiter cleanup**: Stale device entries (no requests for >10 minutes) should be evicted periodically to prevent memory leaks.
- **Graceful shutdown**: `SIGTERM`/`SIGINT` → stop accepting new connections → close DB connection pool → exit.
- **Docker dev setup**: `make db` starts PostgreSQL 16 Alpine container. Default DSN: `postgres://postgres:cameras@localhost:5432/cameras?sslmode=disable`.
