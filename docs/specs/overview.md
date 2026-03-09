# System Overview Specification

## Purpose

A privacy-focused license plate detection system for private security and community watch. A dashboard-mounted mobile app continuously scans for license plates, OCRs them on-device, and sends hashed plate identifiers to a server for comparison against a target list. The system is designed so that neither party learns what it shouldn't: the app never learns the target plates, and the server never learns non-target plates.

## System Components

```
┌─────────────────────┐         ┌─────────────────────┐
│     Mobile App      │         │       Server        │
│                     │  HTTPS  │                     │
│  Camera → Detect →  │────────▶│  Receive hashed     │
│  OCR → Hash → Send  │         │  plate → Compare    │
│                     │◀────────│  against targets →  │
│  On-device only:    │  Result │  Log match/no-match │
│  - Video frames     │         │                     │
│  - Plaintext plates │   Push  │  On match: push     │
│  - Images (debug)   │◀ ─ ─ ─ │  notify via         │
│                     │ (APNs/  │  APNs / FCM         │
│  Offline: queue     │  FCM)   │                     │
│  hashes locally     │         │  Knows only:        │
│                     │         │  - Hashed targets   │
│                     │         │  - Hashed seen plate│
│                     │         │  - Match result     │
│                     │         │  - Device push token│
└─────────────────────┘         └─────────────────────┘
```

## Privacy Model

### Threat Model

The system operates under an **honest-but-curious** threat model:

- **The app** does not receive the target list. It learns only whether individual plates matched (boolean), not which target or why.
- **The server** receives HMAC hashes of detected plates. It compares them against pre-computed HMAC hashes of target plates. Non-matching hashes are processed in memory and never persisted.

### Hashing Scheme

| Property | Value |
|---|---|
| Algorithm | HMAC-SHA256 |
| Key (pepper) | Shared secret, hardcoded in app binary at build time, obfuscated |
| Input normalization | Uppercase, strip whitespace/hyphens, ASCII only |
| Output | 64-character hex string |

### Known Limitations

License plates have a small keyspace (~2 billion US plates). An attacker with access to the HMAC key can brute-force any hash. Privacy relies on:

1. Operational controls (non-matching hashes are never written to disk on the server)
2. Obfuscation (pepper is obfuscated in the app binary, not stored as plaintext)
3. Honest-but-curious assumption (server doesn't actively attempt brute-force reversal)

**Future enhancement:** Private Set Intersection (PSI) protocol would provide cryptographic guarantees independent of operational trust. See `docs/specs/privacy-roadmap.md` (TBD).

## Data Flow

1. App captures camera frames continuously
2. On-device ML model detects license plate regions in each frame
3. On-device OCR extracts plate text from detected regions
4. Plate text is normalized (uppercase, strip formatting)
5. HMAC-SHA256 is computed using the shared pepper
6. Hash is sent to server (or queued locally if offline)
7. Server compares hash against pre-computed target hashes
8. Server returns per-plate match boolean to the device
9. Server logs match details (device_id, timestamp, location, target label)
10. Server sends push notification to all registered devices via APNs (iOS) / FCM (Android)
11. Non-matching hashes are discarded from server memory

## Target Data Source

Target plates are sourced from the [StopICE Plate Tracker](https://www.stopice.net/platetracker/?data=1), a public database of ICE (Immigration and Customs Enforcement) vehicle license plates. As of March 2026, the database contains ~5,300 vehicle reports comprising ~2,600 unique plate numbers.

The data is published as a nightly-compiled ZIP archive containing XML with plate records. A Makefile in `server/` automates downloading and extracting the plates into a plaintext file that the server loads at startup.

## Target Scale

| Dimension | Expected Value |
|---|---|
| Target plates | ~2,600 (from StopICE database) |
| Plates scanned per hour | Varies (urban driving: ~50-200) |
| Offline cache capacity | 1,000 hashed plates |

## Platform Targets

- **iOS**: Swift, AVFoundation, Core ML (YOLOv8-nano), ONNX Runtime (CCT-XS OCR)
- **Android**: Kotlin, CameraX, TFLite (YOLOv8-nano), ONNX Runtime (CCT-XS OCR)
- **Server**: Go (`net/http`), PostgreSQL (via `pgx`), target plates from StopICE data (see `server/Makefile`)

## Future Components

- **Monitoring App** (TBD): Separate application to monitor detected target plates in real-time. Consumes match logs from the server. Will have its own spec. (Push notifications now provide basic real-time alerting — the monitoring app will add geographic filtering and dashboard features.)
- **Target Data Updates** (TBD): Automate nightly plate data refresh (cron + `make setup extract`).
- **Privacy Upgrade** (TBD): PSI protocol for cryptographic privacy guarantees. See `docs/specs/privacy-roadmap.md`.
