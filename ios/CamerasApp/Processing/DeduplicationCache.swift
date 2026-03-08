import Foundation

final class DeduplicationCache {
    private var seen: [String: Date] = [:]
    private let window: TimeInterval

    init(window: TimeInterval = AppConfig.deduplicationWindowSeconds) {
        self.window = window
    }

    func isDuplicate(_ normalizedPlate: String) -> Bool {
        let now = Date()
        evictExpired(now: now)

        if seen[normalizedPlate] != nil {
            return true
        }
        seen[normalizedPlate] = now
        return false
    }

    func reset() {
        seen.removeAll()
    }

    private func evictExpired(now: Date) {
        seen = seen.filter { now.timeIntervalSince($0.value) < window }
    }
}
