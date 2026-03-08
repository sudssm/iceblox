# Server Specification

> **Status:** Minimal v1. Alerting and target management are out of scope — a separate monitoring app will be built for that (see TODO).

## Purpose

Receive hashed license plate identifiers from mobile clients, compare against a target list, log results, and return per-plate match status to the device.

## Technology

- **Language**: Go
- **Framework**: `net/http` (standard library)
- **Target list source (v1)**: JSON seed file loaded at startup
- **Target list source (future)**: Third-party API integration

## Requirements

### REQ-S-1: Receive Hashed Plates

The server MUST expose an HTTPS endpoint that accepts hashed plate submissions.

```
POST /api/v1/plates
Content-Type: application/json

{
  "device_id": "string (hardware identifier)",
  "plates": [
    {
      "hash": "string (64-char hex, HMAC-SHA256)",
      "timestamp": "string (ISO 8601, UTC)",
      "latitude": "number (required if device has GPS permission)",
      "longitude": "number (required if device has GPS permission)"
    }
  ]
}
```

The endpoint MUST accept batches (for offline cache flush).

### REQ-S-2: Compare Against Targets

The server MUST compare each received hash against a pre-computed set of HMAC-SHA256 target hashes loaded from the seed file. Comparison MUST be constant-time (`crypto/subtle.ConstantTimeCompare`) to prevent timing side-channels.

### REQ-S-3: Log Results

The server MUST write match logs to a **structured JSON log file** (one JSON object per line, aka JSONL). The log file path MUST be configurable via command-line flag or environment variable (default: `./matches.jsonl`).

**Match log entry format:**
```json
{
  "event": "match",
  "target_label": "target-001",
  "device_id": "abc123",
  "timestamp": "2026-03-08T14:30:00Z",
  "latitude": 31.7619,
  "longitude": -106.4850,
  "server_time": "2026-03-08T14:30:01Z"
}
```

**Non-matches**: The server MUST log a periodic summary to stdout (e.g., every 60 seconds: `"non_match_count": 47`). Individual non-matching hashes MUST NOT be persisted to disk, database, or any durable storage.

The match log file is the data source for the future monitoring app's REST API.

### REQ-S-4: Response

The response MUST include a per-plate match boolean, in the same order as the request:

```json
{
  "received": 3,
  "results": [
    { "match": false },
    { "match": true },
    { "match": false }
  ]
}
```

The response MUST NOT include any additional detail about which target was matched, the target label, or any target metadata. The device learns only: "this hash matched something."

### REQ-S-5: Target Seed File

The server MUST load target plates from a JSON seed file at startup:

```json
{
  "targets": [
    {
      "label": "target-001",
      "hash": "a3f8b2c1...64 hex chars"
    },
    {
      "label": "target-002",
      "hash": "7d4e9f0a...64 hex chars"
    }
  ]
}
```

- `label`: Human-readable identifier for logging (never sent to devices)
- `hash`: Pre-computed HMAC-SHA256 of the normalized plate using the shared pepper

The server MUST support reloading the seed file without restart (e.g., via SIGHUP or an admin endpoint).

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

  Response: list of target plate sightings within the radius, including target label, GPS coordinates, timestamp, and device_id. Data source: the `matches.jsonl` log file (or a database the monitoring app indexes from it).

- [ ] **Third-party target API**: Replace the seed file with a live integration that pulls target plates from an external source.

## Resolved Decisions

| Question | Decision |
|---|---|
| Language / framework | Go with `net/http` |
| Target list source | JSON seed file at startup (future: third-party API) |
| Alert delivery | No alerting from server to device. Separate monitoring app (TODO) |
| Match results to device | Yes — per-plate boolean only, no target details |
| Match log storage | Structured JSONL file (`matches.jsonl`) |
| Monitoring app data source | REST API reading from match log file |
| Rate limiting | 20 plates/minute per device_id, 429 response with Retry-After |

## Open Questions

- [ ] Should the match log file be rotated (e.g., daily, by size)?
- [ ] Should the server require an API key or shared secret from devices (beyond device_id)?

---

## Implementation Plan

### Project Structure

```
server/
├── cmd/
│   └── server/
│       └── main.go              # Entrypoint, flag parsing, signal handling
├── internal/
│   ├── config/
│   │   └── config.go            # CLI flags, env vars, config struct
│   ├── targets/
│   │   └── targets.go           # Seed file loader, SIGHUP reload, hash lookup
│   ├── matcher/
│   │   └── matcher.go           # Constant-time hash comparison logic
│   ├── ratelimit/
│   │   └── ratelimit.go         # Per-device token bucket rate limiter
│   ├── logger/
│   │   └── logger.go            # JSONL file writer for matches, stdout summaries
│   └── handler/
│       ├── plates.go            # POST /api/v1/plates handler
│       └── health.go            # GET /healthz handler
├── targets.json                 # Example seed file
├── go.mod
└── go.sum
```

### Implementation Order

Each step is independently testable. Later steps depend on earlier ones.

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project scaffold | — | `go mod init`, directory structure, `main.go` with flag parsing |
| 2 | Config | — | Parse CLI flags: `--port`, `--targets-file`, `--log-file`; env var overrides |
| 3 | Target loader | REQ-S-5 | Load seed JSON at startup, parse into in-memory hash set, SIGHUP reload |
| 4 | Matcher | REQ-S-2 | Constant-time comparison against target set, return matched label or nil |
| 5 | JSONL logger | REQ-S-3 | Append match entries to file; periodic non-match count to stdout |
| 6 | Rate limiter | REQ-S-6 | Token bucket per device_id, 429 response with Retry-After |
| 7 | Plates handler | REQ-S-1, REQ-S-4 | Parse batch request, validate fields, call matcher per plate, build response |
| 8 | Health handler | REQ-S-7 | Return status + targets_loaded count |
| 9 | Integration | All | Wire handlers into `http.ServeMux`, TLS config, graceful shutdown |
| 10 | Tests | All | Unit tests per package, integration test with seed file + HTTP requests |

### Key Technical Notes

- **No external dependencies** for v1. Standard library only (`net/http`, `encoding/json`, `crypto/subtle`, `crypto/hmac`, `os/signal`).
- **Seed file reload**: Register `SIGHUP` handler in `main.go` → calls `targets.Reload()` → swaps the in-memory hash map atomically (`sync.RWMutex`).
- **Rate limiter cleanup**: Stale device entries (no requests for >10 minutes) should be evicted periodically to prevent memory leaks.
- **Graceful shutdown**: `SIGTERM`/`SIGINT` → stop accepting new connections → flush pending log writes → exit.
