import XCTest
@testable import IceBloxApp

final class IceBloxAppTests: XCTestCase {
    func testCameraManagerInitialState() throws {
        let manager = CameraManager()
        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(manager.permissionGranted)
        XCTAssertFalse(manager.permissionDenied)
        XCTAssertFalse(manager.isThrottled)
    }

    func testCameraSessionStartsEmpty() throws {
        let manager = CameraManager()
        XCTAssertTrue(manager.session.inputs.isEmpty)
        XCTAssertTrue(manager.session.outputs.isEmpty)
    }

    // MARK: - PlateHasher

    func testHashProduces64CharHex() {
        let hash = PlateHasher.hash(normalizedPlate: "ABC1234")
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    func testHashDeterministic() {
        let h1 = PlateHasher.hash(normalizedPlate: "ABC1234")
        let h2 = PlateHasher.hash(normalizedPlate: "ABC1234")
        XCTAssertEqual(h1, h2)
    }

    func testHashDifferentInputs() {
        let h1 = PlateHasher.hash(normalizedPlate: "ABC1234")
        let h2 = PlateHasher.hash(normalizedPlate: "XYZ9999")
        XCTAssertNotEqual(h1, h2)
    }

    func testHashMatchesServer() {
        let hash = PlateHasher.hash(normalizedPlate: "ABC1234")
        XCTAssertEqual(hash, "2140a5e08c8fb11078d5710075b2743be04f84ee01577c47513865bf79231787")
    }

    // MARK: - DeduplicationCache

    func testDedupFirstSeen() {
        let cache = DeduplicationCache()
        XCTAssertFalse(cache.isDuplicate("ABC1234"))
    }

    func testDedupSecondSeen() {
        let cache = DeduplicationCache()
        _ = cache.isDuplicate("ABC1234")
        XCTAssertTrue(cache.isDuplicate("ABC1234"))
    }

    func testDedupDifferentPlates() {
        let cache = DeduplicationCache()
        _ = cache.isDuplicate("ABC1234")
        XCTAssertFalse(cache.isDuplicate("XYZ9999"))
    }

    func testDedupReset() {
        let cache = DeduplicationCache()
        _ = cache.isDuplicate("ABC1234")
        cache.reset()
        XCTAssertFalse(cache.isDuplicate("ABC1234"))
    }

    // MARK: - RetryManager

    func testRetryInitialState() {
        let rm = RetryManager()
        XCTAssertFalse(rm.isRateLimited)
    }

    func testRetryExponentialBackoff() {
        let rm = RetryManager()
        let first = rm.handleFailure()
        let second = rm.handleFailure()
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(second!, first! * 2, accuracy: 0.01)
    }

    func testRetryReset() {
        let rm = RetryManager()
        _ = rm.handleFailure()
        _ = rm.handleFailure()
        rm.reset()
        let delay = rm.handleFailure()
        XCTAssertNotNil(delay)
        XCTAssertEqual(delay!, AppConfig.retryInitialDelay, accuracy: 0.01)
    }

    func testRetryRateLimit() {
        let rm = RetryManager()
        rm.handleRateLimit(retryAfter: 60)
        XCTAssertTrue(rm.isRateLimited)
    }

    // MARK: - OfflineQueue

    func testQueueEnqueueAndDequeue() {
        let queue = OfflineQueue()
        let sessionID = UUID().uuidString
        let entry = OfflineQueueEntry(plateHash: "abc123", latitude: 40.0, longitude: -74.0, sessionID: sessionID)
        queue.enqueue(entry)

        let entries = queue.dequeue(limit: 10)
        XCTAssertGreaterThanOrEqual(entries.count, 1)
        XCTAssertTrue(entries.contains { $0.plateHash == "abc123" })
        XCTAssertTrue(entries.contains { $0.plateHash == "abc123" && $0.sessionID == sessionID })

        let ids = entries.compactMap(\.id)
        queue.remove(ids: ids)
    }

    func testQueueCountBySessionID() {
        let queue = OfflineQueue()
        let sessionA = UUID().uuidString
        let sessionB = UUID().uuidString

        queue.enqueue(OfflineQueueEntry(plateHash: "hash-a", latitude: nil, longitude: nil, sessionID: sessionA))
        queue.enqueue(OfflineQueueEntry(plateHash: "hash-b", latitude: nil, longitude: nil, sessionID: sessionA))
        queue.enqueue(OfflineQueueEntry(plateHash: "hash-c", latitude: nil, longitude: nil, sessionID: sessionB))

        XCTAssertEqual(queue.count(sessionID: sessionA), 2)
        XCTAssertEqual(queue.count(sessionID: sessionB), 1)
    }

    // MARK: - LocationManager

    func testLocationManagerInitialState() {
        let lm = LocationManager()
        XCTAssertNil(lm.latitude)
        XCTAssertNil(lm.longitude)
        XCTAssertFalse(lm.hasPermission)
    }

    // MARK: - ConnectivityMonitor

    func testConnectivityMonitorInitialState() {
        let cm = ConnectivityMonitor()
        XCTAssertTrue(cm.isConnected)
    }

    // MARK: - AppConfig

    func testAppConfigDefaults() {
        XCTAssertEqual(AppConfig.detectionConfidenceThreshold, 0.5)
        XCTAssertEqual(AppConfig.ocrConfidenceThreshold, 0.6)
        XCTAssertEqual(AppConfig.deduplicationWindowSeconds, 60)
        XCTAssertEqual(AppConfig.batchSize, 65)
        XCTAssertEqual(AppConfig.maxQueueSize, 1000)
    }
}

final class PlateNormalizerTests: XCTestCase {
    func testBasicNormalization() {
        XCTAssertEqual(PlateNormalizer.normalize("abc 1234"), "ABC1234")
    }

    func testRemovesHyphens() {
        XCTAssertEqual(PlateNormalizer.normalize("AB-1234"), "AB1234")
    }

    func testRemovesWhitespace() {
        XCTAssertEqual(PlateNormalizer.normalize("AB  12 34"), "AB1234")
    }

    func testUppercases() {
        XCTAssertEqual(PlateNormalizer.normalize("abc"), "ABC")
    }

    func testRemovesNonAlphanumeric() {
        XCTAssertEqual(PlateNormalizer.normalize("AB@#1234"), "AB1234")
    }

    func testTruncatesTo8Chars() {
        XCTAssertEqual(PlateNormalizer.normalize("ABCDEFGHIJ"), "ABCDEFGH")
    }

    func testRejectsTooShort() {
        XCTAssertNil(PlateNormalizer.normalize("A"))
    }

    func testRejectsEmpty() {
        XCTAssertNil(PlateNormalizer.normalize(""))
    }

    func testRejectsAllSymbols() {
        XCTAssertNil(PlateNormalizer.normalize("@#$"))
    }

    func testAcceptsMinLength() {
        XCTAssertEqual(PlateNormalizer.normalize("AB"), "AB")
    }

    func testAcceptsMaxLength() {
        XCTAssertEqual(PlateNormalizer.normalize("ABCD1234"), "ABCD1234")
    }
}
