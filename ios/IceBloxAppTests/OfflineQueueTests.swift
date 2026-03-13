import Foundation
import SQLite3
import XCTest

@testable import IceBloxApp

final class OfflineQueueTests: XCTestCase {

    private let expectedColumns: Set<String> = [
        "id", "plate_hash", "timestamp", "latitude", "longitude",
        "session_id", "confidence", "is_primary"
    ]

    func testSchemaHasExpectedColumns() {
        let path = temporaryDBPath()
        _ = OfflineQueue(databasePath: path)
        let columns = queryColumns(path: path)

        XCTAssertEqual(columns, expectedColumns)
    }

    func testSchemaDoesNotContainRemovedColumns() {
        let path = temporaryDBPath()
        _ = OfflineQueue(databasePath: path)
        let columns = queryColumns(path: path)

        XCTAssertFalse(columns.contains("substitutions"))
    }

    func testMigrationFromLegacySchemaAddsConfidenceColumns() {
        let path = temporaryDBPath()
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            XCTFail("Failed to open test database")
            return
        }

        let legacySQL = """
            CREATE TABLE IF NOT EXISTS queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                plate_hash TEXT NOT NULL,
                timestamp REAL NOT NULL,
                latitude REAL,
                longitude REAL
            )
            """
        sqlite3_exec(db, legacySQL, nil, nil, nil)
        sqlite3_close(db)

        _ = OfflineQueue(databasePath: path)
        let columns = queryColumns(path: path)

        XCTAssertTrue(columns.contains("session_id"))
        XCTAssertTrue(columns.contains("confidence"))
        XCTAssertTrue(columns.contains("is_primary"))
    }

    func testMigrationPreservesExistingData() {
        let path = temporaryDBPath()
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            XCTFail("Failed to open test database")
            return
        }

        let createSQL = """
            CREATE TABLE IF NOT EXISTS queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                plate_hash TEXT NOT NULL,
                timestamp REAL NOT NULL,
                latitude REAL,
                longitude REAL,
                session_id TEXT NOT NULL DEFAULT ''
            )
            """
        sqlite3_exec(db, createSQL, nil, nil, nil)
        let insertSQL = """
            INSERT INTO queue (plate_hash, timestamp, latitude, longitude, session_id) \
            VALUES ('hash1', 1000.0, 40.7, -74.0, 'sess1')
            """
        sqlite3_exec(db, insertSQL, nil, nil, nil)
        sqlite3_close(db)

        let queue = OfflineQueue(databasePath: path)
        let entries = queue.dequeue(limit: 10)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].plateHash, "hash1")
        XCTAssertEqual(entries[0].sessionID, "sess1")
        XCTAssertEqual(entries[0].confidence, 0.0, accuracy: 0.001)
        XCTAssertFalse(entries[0].isPrimary)
    }

    func testColumnsMatchAndroidEntity() {
        let path = temporaryDBPath()
        _ = OfflineQueue(databasePath: path)
        let iosColumns = queryColumns(path: path)

        let androidColumns: Set<String> = [
            "id", "plate_hash", "timestamp", "latitude", "longitude",
            "session_id", "confidence", "is_primary"
        ]

        XCTAssertEqual(iosColumns, androidColumns)
    }

    func testEnqueueDequeueRoundTrip() {
        let path = temporaryDBPath()
        let queue = OfflineQueue(databasePath: path)

        let entry = OfflineQueueEntry(
            plateHash: "testhash",
            timestamp: Date(),
            latitude: 40.7128,
            longitude: -74.0060,
            sessionID: "test-session",
            confidence: 0.85,
            isPrimary: true
        )
        queue.enqueue(entry)

        let results = queue.dequeue(limit: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].plateHash, "testhash")
        XCTAssertEqual(results[0].sessionID, "test-session")
        XCTAssertEqual(results[0].confidence, 0.85, accuracy: 0.001)
        XCTAssertTrue(results[0].isPrimary)
    }

    // MARK: - Helpers

    private func queryColumns(path: String) -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(queue)", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var columns = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cName = sqlite3_column_text(stmt, 1) {
                columns.insert(String(cString: cName))
            }
        }
        return columns
    }

    private func temporaryDBPath() -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("test_offline_queue_\(UUID().uuidString).sqlite3")
    }
}
