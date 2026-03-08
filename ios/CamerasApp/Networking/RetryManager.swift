import Foundation

final class RetryManager {
    private var currentDelay: TimeInterval = AppConfig.retryInitialDelay
    private var attempts = 0
    private var rateLimitedUntil: Date?

    var isRateLimited: Bool {
        guard let until = rateLimitedUntil else { return false }
        return Date() < until
    }

    func handleRateLimit(retryAfter: TimeInterval) {
        rateLimitedUntil = Date().addingTimeInterval(retryAfter)
    }

    func handleFailure() -> TimeInterval? {
        attempts += 1
        guard attempts <= AppConfig.retryMaxAttempts else { return nil }
        let delay = currentDelay
        currentDelay = min(currentDelay * 2, AppConfig.retryMaxDelay)
        return delay
    }

    func reset() {
        currentDelay = AppConfig.retryInitialDelay
        attempts = 0
        rateLimitedUntil = nil
    }
}
