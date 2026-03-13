# Persistence & Database Schema Management

## Overview

Both Android and iOS clients use a local SQLite database (`offline_queue`) to persist plate hashes for batch upload. Schema changes must be backward-compatible to avoid crashing existing installs.

## Current Schema

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | INTEGER | No | auto | Primary key, autoincrement |
| `plate_hash` | TEXT | No | — | HMAC-SHA256 hash of normalized plate |
| `timestamp` | INTEGER (Android) / REAL (iOS) | No | — | Detection time |
| `latitude` | REAL | Yes | — | GPS latitude |
| `longitude` | REAL | Yes | — | GPS longitude |
| `session_id` | TEXT | No | `''` | Recording session identifier |
| `confidence` | REAL | No | `0` | Per-variant OCR confidence (0.0–1.0) |
| `is_primary` | INTEGER | No | `0` | 1 = primary variant, 0 = lookalike expansion |

## Migration Rules

### Adding a column

1. **Android (Room):** Add a `MIGRATION_N_N+1` object in `OfflineQueueDatabase.kt` with `ALTER TABLE offline_queue ADD COLUMN ... DEFAULT ...`. Bump the `@Database(version = ...)`. Register the migration in `.addMigrations(...)`.
2. **iOS (SQLite3):** Add an `ensure*Column()` method in `OfflineQueue.swift` that checks `PRAGMA table_info(queue)` and runs `ALTER TABLE queue ADD COLUMN ...` if missing. Call it from `init()`.
3. **Both:** Add the field to the entity/struct with a default value so existing rows are valid.

### Removing a column

1. **Android (Room):** Use the table-recreation pattern (create new table without the column, copy data, drop old table, rename new table) inside a migration. `ALTER TABLE ... DROP COLUMN` requires SQLite 3.35.0+ which is only available on API 34+, so avoid it for backward compatibility. Bump the version. Remove the field from `OfflineQueueEntry`.
2. **iOS (SQLite3):** The `CREATE TABLE IF NOT EXISTS` in `init()` defines the canonical schema. Old databases with extra columns are harmless — SQLite ignores columns not referenced in queries. No migration needed unless the extra column causes issues.
3. **Important:** Never remove a column from the Room entity without adding a migration. Room validates the schema on startup and will crash with `IllegalStateException: Migration didn't properly handle` if the database has columns not defined in the entity.

### Renaming a column

Avoid renaming. If necessary, add the new column, migrate data, then drop the old column in a single migration.

### Changing a column type

SQLite does not support `ALTER TABLE ... ALTER COLUMN`. Use the table-recreation pattern: create a new table, copy data, drop old table, rename new table — all in one migration transaction.

## Checklist for Schema Changes

- [ ] Entity/struct updated with new field (include default value)
- [ ] Android: Room migration added, version bumped, migration registered
- [ ] iOS: `ensure*Column()` added (for new columns) or `CREATE TABLE` updated
- [ ] Android: Migration unit test added (see `OfflineQueueMigrationTest.kt`)
- [ ] iOS: Schema validation test added (see `OfflineQueueTests.swift`)
- [ ] Both platforms tested on a device/emulator with an existing database from the previous version
- [ ] Columns match between Android and iOS (same names, compatible types)

## Platform Differences

| Aspect | Android | iOS |
|--------|---------|-----|
| ORM | Room (compile-time schema validation) | Raw SQLite3 (runtime only) |
| Table name | `offline_queue` | `queue` |
| Migration style | Versioned Migration objects | Idempotent `ensure*` checks |
| Schema validation | Automatic on DB open (crashes on mismatch) | None (extra columns silently ignored) |
| Thread safety | Coroutines + suspend functions | DispatchQueue.sync |

## Lessons Learned

- **Room crashes on schema mismatch.** If the database has a column that is not in the entity, Room throws `IllegalStateException` on startup. Always add a migration when removing or renaming columns.
- **iOS is more forgiving.** Raw SQLite3 does not validate the schema against a model. Extra columns are ignored. Missing columns cause query failures only if referenced.
- **Test migrations on real data.** Unit tests validate SQL correctness, but always test on a device with an existing database from the previous version before shipping.
