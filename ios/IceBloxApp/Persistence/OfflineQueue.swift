import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class OfflineQueue {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "offlinequeue.db")

    var count: Int {
        queue.sync { queryCount() }
    }

    init() {
        let path = Self.databasePath()
        queue.sync {
            guard sqlite3_open(path, &db) == SQLITE_OK else { return }
            let sql = """
                CREATE TABLE IF NOT EXISTS queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    plate_hash TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    latitude REAL,
                    longitude REAL,
                    session_id TEXT NOT NULL DEFAULT ''
                )
                """
            sqlite3_exec(db, sql, nil, nil, nil)
            ensureSessionIDColumn()
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func enqueue(_ entry: OfflineQueueEntry) {
        queue.sync {
            evictIfNeeded()
            let sql = """
                INSERT INTO queue (plate_hash, timestamp, latitude, longitude, session_id)
                VALUES (?, ?, ?, ?, ?)
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (entry.plateHash as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, entry.timestamp.timeIntervalSince1970)
            if let lat = entry.latitude {
                sqlite3_bind_double(stmt, 3, lat)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let lng = entry.longitude {
                sqlite3_bind_double(stmt, 4, lng)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_text(stmt, 5, (entry.sessionID as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    func dequeue(limit: Int) -> [OfflineQueueEntry] {
        queue.sync {
            let sql = """
                SELECT id, plate_hash, timestamp, latitude, longitude, session_id
                FROM queue
                ORDER BY id ASC
                LIMIT ?
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))
            var entries: [OfflineQueueEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let hash = String(cString: sqlite3_column_text(stmt, 1))
                let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                let lat: Double? = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? sqlite3_column_double(stmt, 3) : nil
                let lng: Double? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
                let sessionID = String(cString: sqlite3_column_text(stmt, 5))
                entries.append(
                    OfflineQueueEntry(
                        id: id,
                        plateHash: hash,
                        timestamp: ts,
                        latitude: lat,
                        longitude: lng,
                        sessionID: sessionID
                    )
                )
            }
            return entries
        }
    }

    func count(sessionID: String) -> Int {
        queue.sync {
            let sql = "SELECT COUNT(*) FROM queue WHERE session_id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (sessionID as NSString).utf8String, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
        }
    }

    func remove(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let sql = "DELETE FROM queue WHERE id IN (\(placeholders))"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, id) in ids.enumerated() {
                sqlite3_bind_int64(stmt, Int32(i + 1), id)
            }
            sqlite3_step(stmt)
        }
    }

    private func queryCount() -> Int {
        let sql = "SELECT COUNT(*) FROM queue"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    private func evictIfNeeded() {
        let currentCount = queryCount()
        guard currentCount >= AppConfig.maxQueueSize else { return }
        let excess = currentCount - AppConfig.maxQueueSize + 1
        let sql = "DELETE FROM queue WHERE id IN (SELECT id FROM queue ORDER BY id ASC LIMIT ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(excess))
        sqlite3_step(stmt)
    }

    private func ensureSessionIDColumn() {
        guard let db else { return }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "PRAGMA table_info(queue)", -1, &stmt, nil) == SQLITE_OK else { return }

        var hasSessionID = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cName = sqlite3_column_text(stmt, 1) else { continue }
            if String(cString: cName) == "session_id" {
                hasSessionID = true
                break
            }
        }

        if !hasSessionID {
            sqlite3_exec(
                db,
                "ALTER TABLE queue ADD COLUMN session_id TEXT NOT NULL DEFAULT ''",
                nil,
                nil,
                nil
            )
        }
    }

    private static func databasePath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("offline_queue.sqlite3").path
    }
}
