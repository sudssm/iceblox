# IceBlox Privacy Policy

*Last updated: March 13, 2026*

IceBlox is a community safety app that detects license plates and checks them against a public list of known ICE vehicles ([StopICE](https://www.stopice.net/platetracker/?data=1)). This policy explains what data we collect, how we handle it, and the privacy protections built into the system.

## On-Device Processing

All camera and plate processing happens entirely on your device:

- **Video frames** are processed in memory by on-device ML models and are **never saved, uploaded, or transmitted**.
- **Detected plate text** is immediately hashed using HMAC-SHA256 and then discarded. Plaintext plate text never leaves your device and is never written to disk.

## Data We Collect

| Data | When | Purpose |
|---|---|---|
| **Hashed plate text** | Automatically during scanning | Compared against known target hashes on the server |
| **Device location** | If you grant permission | Proximity-based alerts; truncated to ~1 km precision for subscriber notifications |
| **Device identifier** | Automatically | Rate limiting and push notification deduplication |
| **Push notification token** | If you allow notifications | Delivering match alerts via APNs (iOS) or FCM (Android) |
| **Reports** (photo, description, location, optional plate) | Only when you explicitly submit a report | Forwarded to StopICE for community tracking |

## Data We Do Not Collect

- Plaintext license plate numbers (only cryptographic hashes are transmitted)
- Video or camera images
- Personal identity information (no accounts, no names, no emails)
- Analytics or tracking data (no third-party analytics SDKs)

## How Matching Works

IceBlox uses an asymmetric knowledge model:

- **Your device** sends only hashed plates to the server and receives back a match/no-match result per plate. Your device never sees the target plate list.
- **The server** compares hashes and returns results. It never sees the plaintext of non-target plates.
- **Non-matching hashes are discarded immediately** by the server and are never written to disk or logged.
- **Matched sightings** (hash, location, timestamp, device ID) are recorded in the database for alert delivery.

## Push Notifications

Match alerts contain only a generic message (e.g., "Potential ICE Activity Reported"). No plate numbers, hashes, or identifying details are included in notification payloads. Notifications are filtered by proximity and deduplicated per device.

## Offline Queue

When your device is offline, hashes are queued locally in an on-device database. Only hashes, timestamps, and location are stored — never plaintext plates or images. Stale entries older than 10 minutes are automatically pruned, and the queue is capped at 1,000 entries.

## Data Retention

| Data | Retention |
|---|---|
| Non-matching hashes | Immediately discarded, never stored |
| Subscriber location (Redis) | 1-hour expiry |
| Push notification history | 30-minute cleanup cycle |
| Matched sightings | Stored until administrative deletion |
| User-submitted reports | Stored until administrative deletion |

## Third-Party Services

IceBlox communicates only with:

- **Our server** for plate hash comparison and alert delivery
- **Apple Push Notification Service (APNs)** and **Firebase Cloud Messaging (FCM)** for delivering push notifications, subject to Apple's and Google's respective privacy policies
- **StopICE** for submitting user-initiated reports

No third-party analytics, advertising, or tracking services are used.

## Your Controls

- **Location permission**: You can deny GPS access; the app still functions but cannot provide proximity alerts.
- **Push notifications**: Can be toggled on or off at any time.
- **Reports**: Submitted only by your explicit action.

## Security Considerations

- All network communication uses HTTPS encryption.
- The HMAC key (pepper) is embedded in the app binary at build time. While this prevents casual observation of plate text, a determined attacker who extracts the key from the binary could theoretically brute-force hashes due to the limited keyspace of license plates. Privacy against the server relies on operational controls (non-matching hashes are never persisted).
- There are no user accounts or passwords — no credentials to compromise.

## Contact

For privacy questions or concerns, open an issue at [github.com/sudssm/iceblox](https://github.com/sudssm/iceblox).
