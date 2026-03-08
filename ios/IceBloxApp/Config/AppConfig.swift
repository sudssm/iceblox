import Foundation

enum AppConfig {
    static let serverBaseURL = URL(string: "http://localhost:8080")!
    static let platesEndpoint = "/api/v1/plates"

    static let detectionConfidenceThreshold: Float = 0.7
    static let ocrConfidenceThreshold: Float = 0.6
    static let deduplicationWindowSeconds: TimeInterval = 60
    static let minPlateLength = 2
    static let maxPlateLength = 8

    static let batchSize = 10
    static let batchIntervalSeconds: TimeInterval = 30
    static let maxQueueSize = 1000

    static let retryInitialDelay: TimeInterval = 5
    static let retryMaxDelay: TimeInterval = 300
    static let retryMaxAttempts = 10

    static let frameSkipCount = 2
    static let throttledFrameSkipCount = 6

    static let devicesEndpoint = "/api/v1/devices"
    static let subscribeEndpoint = "/api/v1/subscribe"
    static let subscribeIntervalSeconds: TimeInterval = 600
    static let defaultRadiusMiles: Double = 100
}
