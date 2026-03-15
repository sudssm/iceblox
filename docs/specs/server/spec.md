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
- **Subscriber storage**: Redis (via `github.com/redis/go-redis/v9`) — subscriber locations with native TTL expiry
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
  "session_id": "string (UUID, optional — see REQ-S-25)",
  "plates": [
    {
      "plate_hash": "string (64-char hex, HMAC-SHA256)",
      "latitude": number,
      "longitude": number,
      "timestamp": "string (ISO 8601 / RFC 3339, optional)",
      "substitutions": number (integer >= 0, optional, default 0),
      "confidence": number (float 0.0–1.0, optional, default 0)
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
- `confidence`: Optional. Float between 0.0 and 1.0 representing the per-variant geometric mean confidence from OCR character-level softmax probabilities (see mobile spec REQ-M-12a). Defaults to 0 if omitted. The server MUST validate that the value is in range [0, 1] and store it with matched sightings.

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
- `confidence`: Per-variant confidence score from the request (default 0)

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
    substitutions   INTEGER NOT NULL DEFAULT 0,              -- lookalike character substitution count
    confidence      DOUBLE PRECISION NOT NULL DEFAULT 0     -- per-variant OCR confidence score
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

**Table: `reports`** — user-submitted ICE vehicle reports
```sql
CREATE TABLE reports (
    id              SERIAL PRIMARY KEY,
    description     TEXT NOT NULL,
    plate_number    TEXT,
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    photo_path      TEXT NOT NULL,
    hardware_id     TEXT NOT NULL,
    stop_ice_status TEXT NOT NULL DEFAULT 'pending',
    stop_ice_error  TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Table: `sessions`** — scanning session tracking
```sql
CREATE TABLE sessions (
    id                         SERIAL PRIMARY KEY,
    session_id                 TEXT NOT NULL UNIQUE,                -- client-generated UUID
    device_id                  TEXT NOT NULL,                       -- device identifier
    started_at                 TIMESTAMPTZ NOT NULL,                -- first upload in session
    ended_at                   TIMESTAMPTZ,                         -- NULL until session ends
    vehicles                   INTEGER NOT NULL DEFAULT 0,          -- number of upload batches
    plates                     INTEGER NOT NULL DEFAULT 0,          -- total plates across batches
    max_detection_confidence   DOUBLE PRECISION NOT NULL DEFAULT 0, -- highest plate detection confidence
    total_detection_confidence DOUBLE PRECISION NOT NULL DEFAULT 0, -- sum of detection confidences
    max_ocr_confidence         DOUBLE PRECISION NOT NULL DEFAULT 0, -- highest OCR confidence
    total_ocr_confidence       DOUBLE PRECISION NOT NULL DEFAULT 0  -- sum of OCR confidences
);
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
- Title: `"Potential ICE Activity Reported"`
- Body: `"Potential ICE Activity reported"`
- Custom data: `sighting_id` (references the `sightings` table)
- No plaintext plate text, hash, or target label in the payload (privacy model).

### REQ-S-11: APNs Integration (iOS)

The server MUST support sending push notifications to iOS devices via the Apple Push Notification service (APNs) HTTP/2 API.

**Authentication:** Token-based (JWT signed with ES256).
- `.p8` key file containing an ECDSA P-256 private key
- Key ID and Team ID from the Apple Developer portal
- JWT refreshed every 50 minutes (Apple requires refresh within 60 minutes)

**Configuration:** A single JSON env var `APNS_CONFIG_JSON` with fields:
- `key_p8` — PEM-encoded `.p8` key contents (ECDSA P-256 private key)
- `key_id` — 10-character Key ID
- `team_id` — Apple Team ID
- `bundle_id` — iOS app bundle ID (used as `apns-topic` header)
- `production` — use production APNs endpoint (default: false)

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

**Configuration:** A single JSON env var `FCM_SERVICE_ACCOUNT_JSON` containing the raw Firebase service account JSON (must include `project_id`, `client_email`, and `private_key` fields).

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

### REQ-S-14: Redis-Backed Subscriber Storage

The server MUST store subscriber location data in Redis, keyed by device ID with a `sub:` prefix (e.g., `sub:device-1`). Each entry is a JSON object containing:
- **Fields**: `lat`, `lng`, `radius_miles`
- **TTL**: 1 hour, enforced via Redis native key expiry

An active-device set (`sub:active`) tracks all device IDs with active subscriptions. When `All()` is called, stale entries (expired keys still in the set) are lazily cleaned from the active set.

When a device re-subscribes, the existing entry MUST be overwritten and the TTL refreshed. Redis handles concurrency natively (no application-level mutex required).

**Connection:** Configured via the `REDIS_URL` environment variable (required). The store connects on startup, pings Redis with a 5-second timeout, and returns an error if the connection fails.

**Dependency:** `github.com/redis/go-redis/v9`

Note: An earlier version of this spec used an in-memory map with `sync.RWMutex` and a background cleanup goroutine. Redis was adopted to allow subscriber state to survive server restarts and to support horizontal scaling across multiple server instances.

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

### REQ-S-20: ICE Vehicle Report Submission

The server MUST expose an endpoint for users to submit ICE vehicle reports with a photo, description, and location.

```
POST /api/v1/reports
Content-Type: multipart/form-data
X-Device-ID: <device identifier>

Fields:
  description: string (required)
  latitude: number (required, range [-90, 90])
  longitude: number (required, range [-180, 180])
  plate_number: string (optional)
  photo: file (required, image/jpeg)
```

**Field validation:**
- `description`: Required. Non-empty string.
- `latitude`: Required. MUST be in range [-90, 90].
- `longitude`: Required. MUST be in range [-180, 180].
- `plate_number`: Optional. If provided, stored as-is.
- `photo`: Required. Uploaded file saved to the report upload directory with a UUID-based filename.

**Headers:**
- `X-Device-ID`: Required. Identifies the submitting device. Maps to `hardware_id` in the `reports` table.

**Behavior:**
- Save the uploaded photo to disk under the configured `--report-upload-dir` directory (default: `data/reports`). The directory is created at startup if it does not exist.
- Store a `Report` record in the database with `stop_ice_status` set to `"pending"`.
- After storing, asynchronously submit the report upstream to StopICE (REQ-S-21).
- Body size limit: 10 MB.

**Response (200 OK):**
```json
{
  "status": "ok",
  "report_id": 1
}
```

**Error responses:**
- `400 Bad Request` — missing required fields, invalid coordinates, or missing `X-Device-ID` header.
- `405 Method Not Allowed` — non-POST request to this endpoint.
- `500 Internal Server Error` — file save or database write failure.

**Configuration:**
- `--report-upload-dir` flag (env: `REPORT_UPLOAD_DIR`): Directory for report photo uploads. Default: `data/reports`.

### REQ-S-21: StopICE Upstream Submission

After storing a report (REQ-S-20), the server MUST asynchronously submit it to the StopICE plate tracker.

**Target:** `POST https://www.stopice.net/platetracker/index.cgi` (form-encoded)

**Form fields:**
- `vehicle_license`: Plate number from the report
- `address`: Formatted as `"<lat>, <lng>"` (6 decimal places)
- `comments`: Description from the report
- `get_location_gps`: Same as `address`
- `guest`: `"1"`
- `alert_token`: Current Unix timestamp in milliseconds

**Behavior:**
- Submission runs in a background goroutine — MUST NOT block the HTTP response to the reporting device.
- On success (HTTP 2xx from StopICE), update the report's `stop_ice_status` to `"submitted"`.
- On failure (HTTP error or network error), update `stop_ice_status` to `"failed"` and store the error message in `stop_ice_error`.
- HTTP client timeout: 30 seconds.

### REQ-S-25: Session Tracking

The server MUST track scanning sessions reported by mobile clients. Sessions are created client-side with a random UUID and sent with plate uploads. The server aggregates per-session statistics (vehicle count, plate count) for observability.

**Start session endpoint:**

```
POST /api/v1/sessions/start
Content-Type: application/json

{
  "session_id": "string (UUID, required)",
  "device_id": "string (required)"
}
```

**Field validation:**
- `session_id`: Required. Non-empty string. Returns `400 Bad Request` if empty.
- `device_id`: Required. Non-empty string. Returns `400 Bad Request` if empty.

**Behavior:**
- Creates a new session record with `started_at = NOW()`, `vehicles = 0`, `plates = 0`, and all confidence fields set to 0.
- Uses `ON CONFLICT (session_id) DO NOTHING` for idempotency — calling start on an existing session is a no-op.
- Database errors are logged but the endpoint always returns `200 OK`.

**Response (200 OK):**
```json
{
  "status": "ok"
}
```

**Error responses:**
- `400 Bad Request` — invalid JSON, empty `session_id`, or empty `device_id`.
- `405 Method Not Allowed` — non-POST request.

**Session upsert (via plates endpoint):**

When `POST /api/v1/plates` includes an optional `session_id` field in the request body, the server MUST upsert a session record:
- If no session exists for this `session_id`, create one with `started_at = NOW()`, `vehicles = 1`, `plates = <plate count in batch>`.
- If a session already exists, atomically increment `vehicles` by 1 and `plates` by the number of plates in the batch.
- The `device_id` is taken from the `X-Device-ID` header (same as sightings).
- Session upsert errors MUST be logged but MUST NOT fail the plates request.
- If `session_id` is empty or omitted, no session tracking occurs.

**End session endpoint:**

```
POST /api/v1/sessions/end
Content-Type: application/json

{
  "session_id": "string (UUID, required)",
  "max_detection_confidence": number (float, optional, default 0),
  "total_detection_confidence": number (float, optional, default 0),
  "max_ocr_confidence": number (float, optional, default 0),
  "total_ocr_confidence": number (float, optional, default 0)
}
```

The confidence fields allow computing per-session statistics:
- `max_detection_confidence`: Highest plate detection model confidence seen during the session.
- `total_detection_confidence`: Sum of all plate detection confidences (divide by `plates` for average).
- `max_ocr_confidence`: Highest OCR model confidence seen during the session.
- `total_ocr_confidence`: Sum of all OCR confidences (divide by `plates` for average).

**Field validation:**
- `session_id`: Required. Non-empty string. Returns `400 Bad Request` if empty.
- All confidence fields are optional and default to 0 if omitted.

**Behavior:**
- Sets `ended_at = NOW()` for the session where `session_id` matches and `ended_at IS NULL`.
- Best-effort: if no matching session exists (0 rows affected), returns success anyway.
- Database errors are logged but the endpoint always returns `200 OK`.

**Response (200 OK):**
```json
{
  "status": "ok"
}
```

**Error responses:**
- `400 Bad Request` — invalid JSON or empty `session_id`.
- `405 Method Not Allowed` — non-POST request.

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
| Alert delivery | Push notifications to registered devices on match, filtered by proximity (APNs for iOS, FCM for Android, Redis-backed store for subscriber locations) |
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
│   │   └── store.go             # Redis-backed subscriber store (native TTL expiry)
│   ├── stopice/
│   │   ├── client.go            # Async form submission to StopICE plate tracker (REQ-S-21)
│   │   └── client_test.go       # StopICE client tests
│   ├── storage/
│   │   └── s3.go                # S3 client: upload + presigned URL generation (REQ-S-23)
│   └── handler/
│       ├── plates.go            # POST /api/v1/plates handler
│       ├── subscribe.go         # POST /api/v1/subscribe handler
│       ├── health.go            # GET /healthz handler
│       ├── devices.go           # POST /api/v1/devices handler
│       ├── reports.go           # POST /api/v1/reports handler (REQ-S-20)
│       ├── reports_test.go      # Reports handler tests
│       ├── sessions.go          # POST /api/v1/sessions/{start,end} handlers (REQ-S-25)
│       ├── map_sightings.go     # GET /api/v1/map-sightings handler (REQ-S-22)
│       ├── map_sightings_test.go # Map sightings handler tests
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

The project's `Makefile` lives at the repository root (not inside `server/`). It provides server targets (`server-test`, `server-test-db`, `server-lint`, `run-server`, `run-test-server`), a combined `unit-test` target (runs Go, Android, and iOS unit tests back to back), and E2E targets (`android-test`, `ios-test`). Server targets use `cd server && ...` to run commands in the server directory.

### Implementation Order

Each step is independently testable. Later steps depend on earlier ones.

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project scaffold | — | `go mod init`, directory structure, `main.go` with flag parsing |
| 2 | Config | — | Parse CLI flags: `--port`, `--plates-file`, `--db-dsn`, `--pepper`, `--report-upload-dir`, `--s3-bucket`, `--s3-region`; env var overrides (`PORT`, `DATABASE_URL`, `PEPPER`, `PLATES_FILE`, `APNS_CONFIG_JSON`, `FCM_SERVICE_ACCOUNT_JSON`, `REPORT_UPLOAD_DIR`, `S3_BUCKET`, `AWS_REGION`, `REDIS_URL`). Push credentials use single JSON env vars: `APNS_CONFIG_JSON` (fields: `key_p8`, `key_id`, `team_id`, `bundle_id`, `production`) and `FCM_SERVICE_ACCOUNT_JSON`. Subscriber storage configured via `REDIS_URL` (required). |
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
| 16 | Subscriber store | REQ-S-14 | Redis-backed subscriber location storage with 1-hour TTL via native key expiry |
| 17 | Recent sightings query | REQ-S-15 | DB method with bounding-box SQL pre-filter, SightingResult struct, composite geo index |
| 18 | Subscribe handler | REQ-S-13 | Parse request, store subscriber in memory, query+filter recent sightings, respond |
| 19 | Proximity fan-out | REQ-S-16 | Enhance push dispatch with subscriber location filtering via haversine |
| 20 | Request logging middleware | REQ-S-17 | Wrap mux, record method/path/status/duration/device_id, recover panics as 500 |
| 21 | Reports handler | REQ-S-20 | Multipart POST `/api/v1/reports`, save photo to disk, store report in DB |
| 22 | StopICE client | REQ-S-21 | Async form submission to StopICE plate tracker with status callback |
| 23 | Map sightings endpoint | REQ-S-22 | GET `/api/v1/map-sightings?lat=X&lng=Y&radius=Z`, returns sightings + reports within bounding box from last 2h, deduped by plate, with confidence 1.0 |
| 24 | Report photo serving | REQ-S-23 | S3 upload for report photos (`reports/{uuid}.jpg`), presigned GET URLs (60min TTL) in map sightings response, fallback to local disk if S3 not configured |
| 25 | Session tracking | REQ-S-25 | `sessions` table, upsert on plate upload, `POST /api/v1/sessions/start` and `POST /api/v1/sessions/end` endpoints, best-effort non-blocking |

### Key Technical Notes

- **External dependencies**: `gorm.io/gorm` (ORM), `gorm.io/driver/postgres` (PostgreSQL driver, uses `pgx` internally), `github.com/google/uuid` (UUID generation for report photo filenames), `github.com/aws/aws-sdk-go-v2` (S3 photo upload + presigned URLs), and `github.com/redis/go-redis/v9` (Redis-backed subscriber storage).
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
- **Subscriber storage**: Redis-backed `Store` using `github.com/redis/go-redis/v9`. Each subscriber is stored as a JSON value under key `sub:{deviceID}` with a 1-hour TTL via Redis native key expiry. A `sub:active` set tracks all device IDs; stale entries are lazily cleaned from the set when `All()` is called and keys have expired.
- **Haversine distance**: Pure Go implementation in `internal/geo/`. Used for both subscribe response filtering and proximity fan-out. Bounding-box pre-filter in SQL narrows candidates before precise haversine calculation.
- **Proximity fan-out**: Enhances the existing push notification goroutine. After recording a sighting, query active subscribers from the in-memory store, compute haversine distance, and only notify devices within their requested radius.
- **Recent sightings enrichment**: The subscribe query joins `sightings` with `plates` so nearby results can include plaintext target plates without exposing non-target plate text.

### Deployment

The server deploys to [Railway](https://railway.com) via Docker.

- **Dockerfile** (`server/Dockerfile`): Multi-stage build that fetches plate data from StopICE at build time, compiles the Go binary, and produces a minimal Alpine image.
- **Railway config** (`railway.toml`): Configures the build to use the Dockerfile, runs `make migrate` as the predeploy command, exposes `/healthz` for health checks, and uses an ON_FAILURE restart policy.
- **Environment variables**: Railway sets `PORT`, `DATABASE_URL`, `PEPPER`, `PLATES_FILE`, and `REDIS_URL` at runtime. Push notification credentials use single JSON env vars: `APNS_CONFIG_JSON` (fields: `key_p8`, `key_id`, `team_id`, `bundle_id`, `production`) and `FCM_SERVICE_ACCOUNT_JSON` (raw Firebase service account JSON). Report photo storage is configured via `REPORT_UPLOAD_DIR` (default: `data/reports`). S3 photo storage is configured via `S3_BUCKET` and `AWS_REGION` (default: `us-east-1`); AWS credentials come from the default credential chain (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`). `REDIS_URL` is required for subscriber storage (e.g., `redis://localhost:6379`). All env vars override their corresponding CLI flag defaults.
