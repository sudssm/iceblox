# Server Specification

> **Status:** v2 — PostgreSQL persistence for target plates and sightings.

## Purpose

Receive hashed license plate identifiers from mobile clients, compare against a target list of ICE vehicle plates, persist sighting records to a PostgreSQL database, return per-plate match status to the device, and send push notifications to all registered devices when a target plate is detected.

## Target Data Source

See [System Overview — Target Data Source](../overview.md#target-data-source) for the source database, data pipeline, and plate extraction process.

## Technology

- **Language**: Go
- **Framework**: `net/http` (standard library)
- **Database**: PostgreSQL (via GORM ORM with `pgx` driver)
- **Target list source**: `data/plates.txt` — plaintext plate list extracted from StopICE data, seeded into the `plates` database table on startup
- **Push notifications**: APNs (iOS) via HTTP/2 + ES256 JWT, FCM (Android) via HTTP v1 API + OAuth2 — Go stdlib only (`net/http`, `crypto/*`)

## API Versioning Policy

All endpoints use URL path versioning (`/api/v<N>/`). The version is also returned in the `API-Version` response header on every API response.

### Backward Compatibility Contract

Once a versioned endpoint is released, its contract is frozen. Only **additive, non-breaking changes** may be made within the same version:

**Non-breaking (no version bump required):**
- Adding new **optional** fields to request bodies
- Adding new fields to response bodies
- Adding entirely new endpoints
- Relaxing validation (e.g., accepting a wider range)
- Adding new enum values (clients must tolerate unknown values)

**Breaking (requires incrementing the version):**
- Removing or renaming a field from a request or response
- Removing or renaming an endpoint
- Changing a field's data type
- Making an optional field required
- Changing the meaning or format of an existing field
- Changing error response structure or error codes
- Changing authentication requirements

**Client contract:** Clients MUST ignore unknown fields in responses. New optional response fields may appear at any time within the same API version.

### Deprecation Lifecycle

When a successor version (v(N+1)) ships for an endpoint:
1. The v(N) endpoint continues to function but returns `Deprecation: true`, `Sunset: <date>`, and `Link: </api/v(N+1)/docs>; rel="successor-version"` headers
2. Minimum migration window: 3 months from the `Sunset` date
3. After the sunset date, the deprecated endpoint returns `410 Gone`

### Health Check

`/healthz` is unversioned — it is infrastructure, not part of the API contract.

## Requirements

### REQ-S-1: Receive Hashed Plates (Batch)

The server MUST expose an HTTP endpoint that accepts a batch of hashed plate submissions. Each request contains a `plates` array with one or more plate entries.

```
POST /api/v1/plates
Content-Type: application/json
X-Device-ID: <device identifier>

{
  "plates": [
    {
      "plate_hash": "string (64-char hex, HMAC-SHA256)",
      "latitude": number,
      "longitude": number,
      "timestamp": "string (ISO 8601 / RFC 3339, optional)",
      "substitutions": number (integer >= 0, optional, default 0)
    }
  ]
}
```

**Request validation:**
- `plates`: Required. MUST be a non-empty array. An empty array returns `400 Bad Request`.

**Per-plate field validation:**
- `plate_hash`: Required. MUST be a 64-character hexadecimal string.
- `latitude`: Required. MUST be in range [-90, 90].
- `longitude`: Required. MUST be in range [-180, 180].
- `timestamp`: Optional. ISO 8601 / RFC 3339 format (e.g., `"2026-03-08T14:30:00Z"`). If omitted or unparseable, defaults to the server's current UTC time. Represents when the plate was seen by the device.
- `substitutions`: Optional. Non-negative integer indicating how many character positions were changed from the original OCR reading due to lookalike character expansion (see mobile spec REQ-M-12a). Defaults to 0 if omitted. The server MUST validate that the value is >= 0 and store it with matched sightings.

If any plate in the batch fails validation, the entire request is rejected with `400 Bad Request`.

**Headers:**
- `X-Device-ID`: Optional. Identifies the submitting device. If omitted, recorded as `"unknown"`. Maps to `hardware_id` in the sightings table. The header value is sanitized to allow only alphanumeric characters, hyphens, underscores, and periods.

**Response (200 OK):**
```json
{
  "status": "ok",
  "results": [
    {"matched": true},
    {"matched": false}
  ]
}
```

The `results` array is positionally aligned with the `plates` array in the request — `results[i]` corresponds to `plates[i]`. Per the versioning policy, clients MUST ignore unknown fields in the response.

**Error responses:**
- `400 Bad Request` — malformed JSON, empty plates array, or failed field validation. Body: `{"error": "description"}`.
- `405 Method Not Allowed` — non-POST request to this endpoint.
- `500 Internal Server Error` — database write failure. Body: `{"error": "failed to record sighting"}`.

### REQ-S-2: Compare Against Targets

The server MUST compare each received hash against a pre-computed set of HMAC-SHA256 target hashes loaded from the `plates` database table into an in-memory set. Lookup MUST be O(1).

### REQ-S-3: Persist Sightings

When a plate hash matches a target, the server MUST insert a record into the `sightings` database table with:
- `plate_id`: Foreign key to the matched plate in the `plates` table
- `seen_at`: Timestamp from the request (or server time if omitted)
- `latitude` / `longitude`: GPS coordinates from the request
- `hardware_id`: Device identifier from the `X-Device-ID` header
- `substitutions`: Number of lookalike character substitutions from the request (default 0)

Non-matching hashes MUST NOT be persisted (privacy model: non-target plates are never stored).

### REQ-S-4: Response

The server MUST return a per-plate match boolean in the response body. The response format is `{"status": "ok", "results": [{"matched": true|false}, ...]}`, where the `results` array is positionally aligned with the `plates` array in the request. No target details are revealed to the device.

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
    id              SERIAL PRIMARY KEY,
    plate_id        INTEGER NOT NULL REFERENCES plates(id),  -- FK to matched plate
    seen_at         TIMESTAMPTZ NOT NULL,                    -- when the plate was seen
    latitude        DOUBLE PRECISION NOT NULL,               -- GPS latitude
    longitude       DOUBLE PRECISION NOT NULL,               -- GPS longitude
    hardware_id     TEXT NOT NULL,                            -- device identifier
    substitutions   INTEGER NOT NULL DEFAULT 0               -- lookalike character substitution count
);

CREATE INDEX idx_sightings_plate_id ON sightings(plate_id);
CREATE INDEX idx_sightings_seen_at ON sightings(seen_at);
```

**Table: `device_tokens`** — registered push notification tokens
```sql
CREATE TABLE device_tokens (
    id          SERIAL PRIMARY KEY,
    hardware_id TEXT NOT NULL,
    token       TEXT NOT NULL,
    platform    TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(hardware_id, platform)
);
```

**Table: `sent_pushes`** — per-device push notification history for deduplication
```sql
CREATE TABLE sent_pushes (
    id              SERIAL PRIMARY KEY,
    device_token_id INTEGER NOT NULL REFERENCES device_tokens(id) ON DELETE CASCADE,
    plate_id        INTEGER NOT NULL REFERENCES plates(id),
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    sent_at         TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_sent_pushes_device_token_id ON sent_pushes(device_token_id);
CREATE INDEX idx_sent_pushes_sent_at ON sent_pushes(sent_at);
```

**Data flow:**
1. On startup, plates from `data/plates.txt` are upserted into the `plates` table
2. Hash → plate_id mappings are loaded into memory for O(1) lookup
3. When a submitted hash matches, a sighting is inserted with the plate's ID, timestamp, GPS, and device ID
4. Non-matching hashes are never written to the database

**Schema management:** The database schema is defined by GORM model structs in `internal/db/db.go` with struct tags specifying types, indexes, constraints, and foreign keys. On startup (and via `make migrate`), the server calls GORM's `AutoMigrate` which creates missing tables, adds missing columns, and creates missing indexes — no hand-written migration SQL is required. Adding a column is as simple as adding a tagged field to the Go struct.

**Connection:** Configured via `--db-dsn` flag. Default: `postgres://postgres:iceblox@localhost:5432/iceblox?sslmode=disable`. Schema migrations MUST be executable via `make migrate`, which runs database-only migrations against `DATABASE_URL` or `DB_DSN` and exits without starting the HTTP server. Railway deployments MUST invoke this target as a predeploy command so schema changes complete before the new server instance starts receiving traffic. The server MAY also run the same idempotent migration path on startup as a safety check.

### REQ-S-9: Device Token Registration

The server MUST expose an endpoint for devices to register their push notification token.

```
POST /api/v1/devices
Content-Type: application/json
X-Device-ID: <device identifier>

{
  "token": "string (push notification token)",
  "platform": "ios" | "android"
}
```

**Field validation:**
- `token`: Required. Non-empty string.
- `platform`: Required. MUST be either `"ios"` or `"android"`.

**Headers:**
- `X-Device-ID`: Required. Identifies the device. Maps to `hardware_id` in the `device_tokens` table.

**Behavior:**
- Upsert: one token per `(hardware_id, platform)` pair. If a token already exists for this device and platform, update it.
- Update `updated_at` on every registration (used for stale token cleanup).

**Response (200 OK):**
```json
{
  "status": "ok"
}
```

**Error responses:**
- `400 Bad Request` — missing or invalid fields, or missing `X-Device-ID` header.

### REQ-S-10: Push Notification Dispatch

When a plate hash matches a target (REQ-S-2), the server MUST send a push notification to all registered devices.

**Dispatch rules:**
- Notifications MUST be sent asynchronously — the HTTP response to the detecting device MUST NOT be blocked by notification delivery.
- The server MUST query all active device tokens from the `device_tokens` table and send to each.
- Before sending, the server MUST apply per-device deduplication rules (REQ-S-18) and skip the notification if it would be a duplicate.
- If a push provider returns a token-expired error (APNs HTTP 410 / FCM `UNREGISTERED`), the server MUST delete that token from the database.
- Push delivery failures MUST be logged but MUST NOT affect the plates endpoint response.

**Notification content:**
- Title: `"Target Detected"`
- Body: `"A target plate was detected"`
- Custom data: `sighting_id` (references the `sightings` table)
- No plaintext plate text, hash, or target label in the payload (privacy model).

### REQ-S-11: APNs Integration (iOS)

The server MUST support sending push notifications to iOS devices via the Apple Push Notification service (APNs) HTTP/2 API.

**Authentication:** Token-based (JWT signed with ES256).
- `.p8` key file containing an ECDSA P-256 private key
- Key ID and Team ID from the Apple Developer portal
- JWT refreshed every 50 minutes (Apple requires refresh within 60 minutes)

**Configuration flags:**
- `--apns-key-file` — path to `.p8` key file
- `--apns-key-id` — 10-character Key ID
- `--apns-team-id` — Apple Team ID
- `--apns-bundle-id` — iOS app bundle ID (used as `apns-topic` header)
- `--apns-production` — use production APNs endpoint (default: false)

**Endpoints:**
- Development: `https://api.development.push.apple.com`
- Production: `https://api.push.apple.com`

**Required headers:** `authorization` (bearer JWT), `apns-topic` (bundle ID), `apns-push-type` (`alert`), `apns-priority` (`10`).

**Implementation:** Go stdlib `net/http` with automatic HTTP/2 negotiation via TLS ALPN. No external HTTP/2 library required. Use a single shared `http.Client` to maintain long-lived connections (Apple throttles rapid connect/disconnect).

### REQ-S-12: FCM Integration (Android)

The server MUST support sending push notifications to Android devices via the Firebase Cloud Messaging (FCM) HTTP v1 API.

**Authentication:** OAuth2 access token obtained by:
1. Constructing a JWT signed with RS256 using the service account's RSA private key
2. Exchanging the JWT for an access token at `https://oauth2.googleapis.com/token`
3. Caching the access token until near expiry (tokens last 1 hour, refresh at ~55 minutes)

**Configuration flags:**
- `--fcm-service-account` — path to Firebase service account JSON file (contains `project_id`, `client_email`, and `private_key`)

**Endpoint:** `POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`

**Message format:** Data-only messages (no `notification` key) to ensure `onMessageReceived()` is called in all app states. The Android app builds and displays the notification locally.

**Implementation:** Go stdlib `net/http`, `crypto/rsa`, `crypto/sha256`, `encoding/json`. No external dependencies.

### REQ-S-13: Subscribe Endpoint

The server MUST expose an HTTP endpoint for devices to register their location for proximity alerts and retrieve recent nearby sightings.

```
POST /api/v1/subscribe
Content-Type: application/json
X-Device-ID: <device identifier>

{
  "latitude": number,
  "longitude": number,
  "radius_miles": number
}
```

**Field validation:**
- `latitude`: Required. MUST be in range [-90, 90]. Clients SHOULD truncate to 2 decimal places before sending (~1.1 km / ~0.7 mile precision).
- `longitude`: Required. MUST be in range [-180, 180]. Clients SHOULD truncate to 2 decimal places.
- `radius_miles`: Required. MUST be in range [1, 500]. Default suggested by clients: 100.

**Headers:**
- `X-Device-ID`: Required. Identifies the subscribing device. The server MUST also update the `updated_at` timestamp of the device's `device_tokens` row(s) on each subscribe call, so that active subscribers are not considered stale for push history cleanup (REQ-S-19).

**Response (200 OK):**
```json
{
  "status": "ok",
  "recent_sightings": [
    {
      "plate": "ABC1234",
      "latitude": 34.05,
      "longitude": -118.24,
      "seen_at": "2026-03-08T14:30:00Z"
    }
  ]
}
```

**Error responses:**
- `400 Bad Request` — malformed JSON or failed field validation. Body: `{"error": "description"}`.
- `405 Method Not Allowed` — non-POST request to this endpoint.
- `500 Internal Server Error` — database query failure. Body: `{"error": "description"}`.

### REQ-S-14: In-Memory Subscriber Storage

The server MUST store subscriber location data in an in-memory map keyed by device ID. Each entry contains:
- **Fields**: `lat`, `lng`, `radius_miles`, `expires_at`
- **TTL**: 1 hour from the time of subscription

When a device re-subscribes, the existing entry MUST be overwritten, refreshing the TTL. A background goroutine MUST periodically clean up expired entries (every 5 minutes). The store MUST be concurrency-safe (protected by a read-write mutex).

Note: An earlier version of this spec specified Redis for subscriber storage. The in-memory approach was chosen to avoid adding an external dependency for v1. The TTL and cleanup behavior is equivalent. Redis may be revisited if horizontal scaling requires shared state across multiple server instances.

### REQ-S-15: Recent Sightings Query

When handling a subscribe request, the server MUST query the `sightings` table joined with the `plates` table for sightings where:
- `seen_at` is within the last 1 hour
- Location is within the subscriber's requested radius

The query MUST use a bounding-box pre-filter in SQL (latitude/longitude range computed from the subscriber's location and radius) for efficiency, then apply haversine distance calculation in Go for precision filtering.

The response MUST include the plaintext plate identifier (from the `plates` table), the GPS coordinates of the sighting, and the timestamp. These are ICE vehicle plates from public StopICE data — returning plaintext is consistent with the privacy model (which protects non-target plates only).

### REQ-S-16: Proximity-Filtered Fan-Out on Match

When a new target plate match is detected via `POST /api/v1/plates`, the existing push notification dispatch (REQ-S-10) MUST be enhanced to filter by proximity:
1. Query all active subscribers from the in-memory subscriber store
2. Compute haversine distance between the sighting location and each subscriber's registered location
3. Only send push notifications (via the existing APNs/FCM infrastructure from REQ-S-11/REQ-S-12) to devices whose sighting falls within their requested radius

This proximity filtering MUST NOT block the plates handler HTTP response. It MUST run in the existing async notification goroutine.

### REQ-S-17: Request Logging Middleware

The server MUST wrap the HTTP mux with request logging middleware so operator logs are sufficient to debug unexpected `500 Internal Server Error` responses.

**For every request, the middleware MUST log:**
- HTTP method
- URL path
- Response status code
- Request duration in milliseconds
- `X-Device-ID` header value when present

**Failure handling:**
- Any response with status `>= 500` MUST be logged explicitly as a server error entry.
- If a handler panics, the middleware MUST recover, log the panic value with the request metadata, and return `500 Internal Server Error`.

**Scope:**
- The middleware MUST apply to all server endpoints, including `/healthz`.
- Logging MUST be additive only; it MUST NOT change successful response bodies or status codes from existing handlers.

### REQ-S-18: Push Notification Deduplication

Before sending a push notification to a device, the server MUST check the `sent_pushes` table for that device and skip the notification if any of the following conditions are met:

1. **Same plate**: A push was already sent to this device for the same `plate_id` (regardless of location or time).
2. **Proximity**: A push was already sent to this device for any plate within 1 mile of the current sighting (haversine distance ≤ 1.0 miles).
3. **Cooldown**: A push was already sent to this device less than 2 minutes ago (regardless of plate or location).

After a successful push send, the server MUST record the push in `sent_pushes` with the device token ID, plate ID, sighting coordinates, and current timestamp.

### REQ-S-19: Stale Push History Cleanup

The server MUST run a background goroutine that periodically cleans up stale `sent_pushes` records:

- **Sweep interval**: Every 5 minutes
- **Stale threshold**: 30 minutes — delete `sent_pushes` rows for device tokens whose `device_tokens.updated_at` is older than 30 minutes (indicating the device has not checked in recently)
- **Subscribe touch**: The subscribe endpoint (`POST /api/v1/subscribe`) MUST update the `updated_at` timestamp of the device's token row(s), so that active subscribers are not considered stale

## Out of Scope (v1)

- Admin dashboard
- User authentication
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
| Alert delivery | Push notifications to registered devices on match, filtered by proximity (APNs for iOS, FCM for Android, in-memory store for subscriber locations) |
| Match results to device | Yes — per-plate boolean in batch `results` array, no target details |
| Storage | PostgreSQL — `plates` table for targets, `sightings` table for matched observations |
| Monitoring app data source | REST API querying `sightings` table |
| Rate limiting | 20 plates/minute per device_id, 429 response with Retry-After |

## Open Questions

- [ ] Should the server require an API key or shared secret from devices (beyond device_id)?
- [ ] Should push notifications be throttled (e.g., max one per minute) to prevent flooding when multiple plates match in rapid succession?
- [ ] Should the detecting device be excluded from receiving its own match notification?

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
│   ├── push/
│   │   ├── apns.go              # APNs HTTP/2 client, ES256 JWT auth
│   │   ├── fcm.go               # FCM HTTP v1 client, OAuth2 auth
│   │   └── notifier.go          # Dispatch to all registered devices
│   ├── geo/
│   │   └── haversine.go         # Haversine distance, bounding box calculation
│   ├── subscribers/
│   │   └── store.go             # In-memory subscriber store (map with TTL cleanup)
│   └── handler/
│       ├── plates.go            # POST /api/v1/plates handler
│       ├── subscribe.go         # POST /api/v1/subscribe handler
│       ├── health.go            # GET /healthz handler
│       ├── devices.go           # POST /api/v1/devices handler
│       ├── request_logging.go   # HTTP request logging middleware (REQ-S-17)
│       ├── version.go           # API version + deprecation middleware
│       └── logger.go            # JSONL file writer (legacy, optional)
├── data/                        # Downloaded plate data (gitignored)
│   └── plates.txt               # Extracted plates, one per line
├── Dockerfile                   # Multi-stage build for Railway deployment
├── railway.toml                 # Railway deployment config
├── go.mod
└── go.sum
```

The project's `Makefile` lives at the repository root (not inside `server/`). It provides both server targets (`server-test`, `server-test-db`, `server-lint`, `run-server`, `run-test-server`) and Android targets (`android-test`). Server targets use `cd server && ...` to run commands in the server directory.

### Implementation Order

Each step is independently testable. Later steps depend on earlier ones.

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project scaffold | — | `go mod init`, directory structure, `main.go` with flag parsing |
| 2 | Config | — | Parse CLI flags: `--port`, `--plates-file`, `--db-dsn`, `--pepper`, `--apns-key-file`, `--apns-key-id`, `--apns-team-id`, `--apns-bundle-id`, `--apns-production`, `--fcm-service-account`; env var overrides (`PORT`, `DATABASE_URL`, `PEPPER`, `PLATES_FILE`, `APNS_KEY_FILE`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRODUCTION`, `FCM_SERVICE_ACCOUNT`, `FCM_SERVICE_ACCOUNT_JSON`). Subscriber storage is in-memory (no external config needed). |
| 3 | Database | REQ-S-8 | Connect to PostgreSQL, run migrations, plate upsert, sighting insert |
| 4 | Target loader | REQ-S-5 | Load plates.txt, compute HMAC hashes, seed DB, build in-memory hash→plate_id map |
| 5 | Matcher | REQ-S-2 | O(1) in-memory hash lookup, return plate_id for matched hashes |
| 6 | Rate limiter | REQ-S-6 | Token bucket per device_id, 429 response with Retry-After |
| 7 | Plates handler | REQ-S-1, REQ-S-3, REQ-S-4 | Parse request, validate fields, check match, record sighting to DB, return response |
| 8 | Health handler | REQ-S-7 | Return status + targets_loaded count |
| 9 | Integration | All | Wire handlers into `http.ServeMux`, graceful shutdown, SIGHUP reload with DB re-seed |
| 10 | Tests | All | Unit tests per package, integration test with seed file + HTTP requests + mock recorder |
| 11 | Device store | REQ-S-9 | `device_tokens` table operations, registration endpoint handler |
| 12 | APNs client | REQ-S-11 | HTTP/2 provider, ES256 JWT auth, `.p8` key loading, token caching |
| 13 | FCM client | REQ-S-12 | HTTP v1 API client, RS256 JWT, OAuth2 token exchange, token caching |
| 14 | Notifier | REQ-S-10 | Match → push dispatch to all devices, async goroutine, stale token cleanup |
| 15 | Geo package | REQ-S-15 | Haversine distance calculation, bounding box utility (pure functions, no deps) |
| 16 | Subscriber store | REQ-S-14 | In-memory subscriber location storage with 1-hour TTL and periodic cleanup |
| 17 | Recent sightings query | REQ-S-15 | DB method with bounding-box SQL pre-filter, SightingResult struct, composite geo index |
| 18 | Subscribe handler | REQ-S-13 | Parse request, store subscriber in memory, query+filter recent sightings, respond |
| 19 | Proximity fan-out | REQ-S-16 | Enhance push dispatch with subscriber location filtering via haversine |
| 20 | Request logging middleware | REQ-S-17 | Wrap mux, record method/path/status/duration/device_id, recover panics as 500 |

### Key Technical Notes

- **External dependencies**: `gorm.io/gorm` (ORM) and `gorm.io/driver/postgres` (PostgreSQL driver, uses `pgx` internally).
- **Schema migrations**: GORM's `AutoMigrate` derives the schema from Go struct tags (types, indexes, constraints, foreign keys). It creates tables, adds missing columns, and creates missing indexes idempotently on each startup. A `make migrate` entrypoint runs migrations and exits for deploy-time execution (e.g., Railway predeploy).
- **In-memory cache**: Hash → plate_id map in `targets.Store` provides O(1) lookup without per-request DB queries. DB is only written to (sighting inserts), not read on the hot path.
- **Plates file reload**: Register `SIGHUP` handler in `main.go` → calls `targets.Reload()` → re-reads `plates.txt`, re-computes hashes, re-seeds DB via upsert, rebuilds in-memory map.
- **Rate limiter cleanup**: Stale device entries (no requests for >10 minutes) should be evicted periodically to prevent memory leaks.
- **Graceful shutdown**: `SIGTERM`/`SIGINT` → stop accepting new connections → close DB connection pool → exit.
- **Docker dev setup**: `make db` starts PostgreSQL 16 Alpine container. Default DSN: `postgres://postgres:iceblox@localhost:5432/iceblox?sslmode=disable`.
- **APNs HTTP/2**: Go `net/http` automatically negotiates HTTP/2 over TLS via ALPN. Apple requires long-lived connections — use a single shared `http.Client` instance.
- **APNs JWT**: ES256 (ECDSA P-256) signed with `.p8` key. Cache token for ~50 minutes. All signing uses Go stdlib (`crypto/ecdsa`, `crypto/sha256`, `encoding/pem`).
- **FCM OAuth2**: RS256 JWT exchanged for access token at Google's token endpoint. Cache token until near expiry (~55 minutes). All signing uses Go stdlib (`crypto/rsa`, `crypto/sha256`).
- **Async push dispatch**: Send notifications in a goroutine after recording the sighting. Push failures MUST NOT affect the plates endpoint response.
- **Subscriber storage**: In-memory `map[string]Subscriber` protected by `sync.RWMutex`. Background goroutine cleans expired entries every 5 minutes. No external dependency (Redis was considered but deferred to avoid operational complexity in v1).
- **Haversine distance**: Pure Go implementation in `internal/geo/`. Used for both subscribe response filtering and proximity fan-out. Bounding-box pre-filter in SQL narrows candidates before precise haversine calculation.
- **Proximity fan-out**: Enhances the existing push notification goroutine. After recording a sighting, query active subscribers from the in-memory store, compute haversine distance, and only notify devices within their requested radius.
- **Recent sightings enrichment**: The subscribe query joins `sightings` with `plates` so nearby results can include plaintext target plates without exposing non-target plate text.

### Deployment

The server deploys to [Railway](https://railway.com) via Docker.

- **Dockerfile** (`server/Dockerfile`): Multi-stage build that fetches plate data from StopICE at build time, compiles the Go binary, and produces a minimal Alpine image.
- **Railway config** (`railway.toml`): Configures the build to use the Dockerfile, runs `make migrate` as the predeploy command, exposes `/healthz` for health checks, and uses an ON_FAILURE restart policy.
- **Environment variables**: Railway sets `PORT`, `DATABASE_URL`, `PEPPER`, and `PLATES_FILE` at runtime. Push notification credentials are also configurable via env vars: `APNS_KEY_FILE`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRODUCTION`, `FCM_SERVICE_ACCOUNT`. For environments where mounting a file is not possible, `FCM_SERVICE_ACCOUNT_JSON` accepts the raw JSON content and writes it to a temporary file at startup. All env vars override their corresponding CLI flag defaults.
