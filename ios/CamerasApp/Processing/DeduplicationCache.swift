import Foundation

final class DeduplicationCache {
    private var seen: [String: Date] = [:]
    private let window: TimeInterval
    private let lock = NSLock()

    init(window: TimeInterval = AppConfig.deduplicationWindowSeconds) {
        self.window = window
    }

    func isDuplicate(_ normalizedPlate: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        evictExpired(now: now)

        if seen[normalizedPlate] != nil {
            return true
        }
        seen[normalizedPlate] = now
        return false
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        seen.removeAll()
    }

    private func evictExpired(now: Date) {
        seen = seen.filter { now.timeIntervalSince($0.value) < window }
    }
}
