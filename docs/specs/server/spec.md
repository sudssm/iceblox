# Server Specification

> **Status:** Minimal v1. Alerting and target management are out of scope — a separate monitoring app will be built for that (see TODO).

## Purpose

Receive hashed license plate identifiers from mobile clients, compare against a target list of ICE vehicle plates, log results, and return per-plate match status to the device.

## Target Data Source

Target plates come from [StopICE Plate Tracker](https://www.stopice.net/platetracker/?data=1), a public database of ICE vehicle license plates (~2,600 unique plates as of March 2026). The data is published as a nightly-compiled ZIP archive containing an XML file with `<vehicle_license>` entries.

**Data pipeline:**
1. `make setup` — Downloads the latest ZIP archive from stopice.net
2. `make extract` — Parses the XML, normalizes plates, and writes `data/plates.txt` (one plate per line)
3. The Go server loads `data/plates.txt` at startup and computes HMAC-SHA256 hashes in memory

## Technology

- **Language**: Go
- **Framework**: `net/http` (standard library)
- **Target list source**: `data/plates.txt` — plaintext plate list extracted from StopICE data

## Requirements

### REQ-S-1: Receive Hashed Plates

The server MUST expose an HTTP endpoint that accepts a single hashed plate submission.

```
POST /api/v1/plates
Content-Type: application/json

{
  "plate_hash": "string (64-char hex, HMAC-SHA256)",
  "latitude": number,
  "longitude": number
}
```

**Field validation:**
- `plate_hash`: Required. MUST be a 64-character hexadecimal string.
- `latitude`: Required. MUST be in range [-90, 90].
- `longitude`: Required. MUST be in range [-180, 180].

**Response (200 OK):**
```json
{
  "status": "ok"
}
```

**Error responses:**
- `400 Bad Request` — malformed JSON or failed field validation. Body: `{"error": "description"}`.
- `405 Method Not Allowed` — non-POST request to this endpoint.

> **Future:** Batch submissions (array of plates + device_id) will be added when offline queue flush is needed. See original batch format in git history.

### REQ-S-2: Compare Against Targets

> **Deferred.** Target matching will be implemented after the logging-only server is validated. The server MUST compare each received hash against a pre-computed set of HMAC-SHA256 target hashes loaded from the seed file. Comparison MUST be constant-time (`crypto/subtle.ConstantTimeCompare`) to prevent timing side-channels.

### REQ-S-3: Log Submissions

The server MUST write every received plate submission to a **structured JSON log file** (one JSON object per line, aka JSONL). The log file path MUST be configurable via command-line flag or environment variable (default: `./plates.jsonl`).

**Log entry format:**
```json
{
  "plate_hash": "a3f8b2c1...64 hex chars",
  "latitude": 31.7619,
  "longitude": -106.4850,
  "received_at": "2026-03-08T14:30:01Z"
}
```

> **Future:** When target matching is added (REQ-S-2), match logs will include `event`, `target_label`, and `device_id` fields. Non-matching hashes will not be persisted.

### REQ-S-4: Response

> **Deferred.** Per-plate match booleans will be returned when target matching is implemented. For now, the response is a simple acknowledgment (see REQ-S-1 response format).

### REQ-S-5: Target Plate Loading

The server MUST load target plates from a plaintext file (`data/plates.txt`) at startup. Each line contains one normalized license plate number.

**On startup, the server:**
1. Reads `data/plates.txt` (one plate per line)
2. Normalizes each plate (uppercase, strip whitespace/hyphens)
3. Computes HMAC-SHA256 of each normalized plate using the shared pepper
4. Stores the hashes in an in-memory set for O(1) lookup

**Data preparation (via Makefile):**
```bash
make setup    # Download latest ZIP from stopice.net
make extract  # Parse XML → data/plates.txt
```

The server MUST support reloading the plates file without restart (e.g., via SIGHUP).

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
| Target list source | StopICE plate tracker data (plaintext `plates.txt` extracted via Makefile) |
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
│   │   └── targets.go           # Load plates.txt, compute hashes, SIGHUP reload
│   ├── matcher/
│   │   └── matcher.go           # Constant-time hash comparison logic
│   ├── ratelimit/
│   │   └── ratelimit.go         # Per-device token bucket rate limiter
│   ├── logger/
│   │   └── logger.go            # JSONL file writer for matches, stdout summaries
│   └── handler/
│       ├── plates.go            # POST /api/v1/plates handler
│       └── health.go            # GET /healthz handler
├── data/                        # Downloaded plate data (gitignored)
│   └── plates.txt               # Extracted plates, one per line
├── Makefile                     # setup, extract, run-server targets
├── go.mod
└── go.sum
```

### Implementation Order

Each step is independently testable. Later steps depend on earlier ones.

| Step | Component | Spec Requirements | Description |
|---|---|---|---|
| 1 | Project scaffold | — | `go mod init`, directory structure, `main.go` with flag parsing |
| 2 | Config | — | Parse CLI flags: `--port`, `--targets-file`, `--log-file`; env var overrides |
| 3 | Target loader | REQ-S-5 | Load plates.txt at startup, compute HMAC hashes into in-memory set, SIGHUP reload |
| 4 | Matcher | REQ-S-2 | Constant-time comparison against target set, return matched label or nil |
| 5 | JSONL logger | REQ-S-3 | Append match entries to file; periodic non-match count to stdout |
| 6 | Rate limiter | REQ-S-6 | Token bucket per device_id, 429 response with Retry-After |
| 7 | Plates handler | REQ-S-1, REQ-S-4 | Parse batch request, validate fields, call matcher per plate, build response |
| 8 | Health handler | REQ-S-7 | Return status + targets_loaded count |
| 9 | Integration | All | Wire handlers into `http.ServeMux`, TLS config, graceful shutdown |
| 10 | Tests | All | Unit tests per package, integration test with seed file + HTTP requests |

### Key Technical Notes

- **No external dependencies** for v1. Standard library only (`net/http`, `encoding/json`, `crypto/subtle`, `crypto/hmac`, `os/signal`).
- **Plates file reload**: Register `SIGHUP` handler in `main.go` → calls `targets.Reload()` → re-reads `plates.txt`, re-computes hashes, swaps the in-memory hash set atomically (`sync.RWMutex`).
- **Rate limiter cleanup**: Stale device entries (no requests for >10 minutes) should be evicted periodically to prevent memory leaks.
- **Graceful shutdown**: `SIGTERM`/`SIGINT` → stop accepting new connections → flush pending log writes → exit.
