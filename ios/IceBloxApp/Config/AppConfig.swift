import Foundation

enum AppConfig {
    static let serverBaseURL: URL = {
        let rawURL = stringEnv("E2E_SERVER_BASE_URL") ?? stringEnv("SERVER_BASE_URL") ?? "http://localhost:8080"
        return URL(string: rawURL)!
    }()
    static let platesEndpoint = "/api/v1/plates"

    static let autoStartCamera = boolEnv("E2E_AUTOSTART_CAMERA", defaultValue: false)
    static let skipNotificationRequest = boolEnv("E2E_SKIP_NOTIFICATION_REQUEST", defaultValue: false)
    static let forceDebugMode = boolEnv("E2E_FORCE_DEBUG_MODE", defaultValue: false)
    static let requestLocationPermission = boolEnv("E2E_REQUEST_LOCATION_PERMISSION", defaultValue: true)
    static let useSplashTrigger = boolEnv("E2E_USE_SPLASH_TRIGGER", defaultValue: false)
    static let useStopRecordingTrigger = boolEnv("E2E_USE_STOP_RECORDING_TRIGGER", defaultValue: false)
    static let splashTriggerFilename = stringEnv("E2E_SPLASH_TRIGGER_FILENAME") ?? "e2e_start_camera.trigger"
    static let stopRecordingTriggerFilename = stringEnv("E2E_STOP_RECORDING_TRIGGER_FILENAME") ?? "e2e_stop_recording.trigger"
    static let sessionSummaryFilename = stringEnv("E2E_SESSION_SUMMARY_FILENAME") ?? "e2e_session_summary.txt"
    static let simulatorTestImagesDirectoryName = stringEnv("SIMULATOR_TEST_IMAGES_DIRNAME") ?? "test_images"
    static let simulatorFrameIntervalMilliseconds = intEnv("SIMULATOR_FRAME_INTERVAL_MS", defaultValue: 100)

    static let detectionConfidenceThreshold = floatEnv("E2E_DETECTION_CONFIDENCE_THRESHOLD", defaultValue: 0.5)
    static let ocrConfidenceThreshold = floatEnv("E2E_OCR_CONFIDENCE_THRESHOLD", defaultValue: 0.6)
    static let deduplicationWindowSeconds: TimeInterval = 60
    static let minPlateLength = 2
    static let maxPlateLength = 8

    static let batchSize = 65
    static let batchIntervalSeconds = timeIntervalEnv("E2E_BATCH_INTERVAL_SECONDS", defaultValue: 30)
    static let maxQueueSize = 1000
    static let uploadTimeoutSeconds: TimeInterval = 600

    static let retryInitialDelay: TimeInterval = 5
    static let retryMaxDelay: TimeInterval = 300
    static let retryMaxAttempts = 10

    static let maxLookalikeVariants = 64

    static let frameSkipCount = 2
    static let throttledFrameSkipCount = 6

    static let devicesEndpoint = "/api/v1/devices"
    static let subscribeEndpoint = "/api/v1/subscribe"
    static let subscribeIntervalSeconds: TimeInterval = 600
    static let defaultRadiusMiles: Double = 100

    static var splashTriggerURL: URL? {
        guard useSplashTrigger else { return nil }
        guard let appSupport = appSupportDirectoryURL else { return nil }
        return appSupport.appendingPathComponent(splashTriggerFilename)
    }

    static var stopRecordingTriggerURL: URL? {
        guard useStopRecordingTrigger else { return nil }
        guard let appSupport = appSupportDirectoryURL else { return nil }
        return appSupport.appendingPathComponent(stopRecordingTriggerFilename)
    }

    static var sessionSummaryArtifactURL: URL? {
        guard useStopRecordingTrigger else { return nil }
        guard let appSupport = appSupportDirectoryURL else { return nil }
        return appSupport.appendingPathComponent(sessionSummaryFilename)
    }

    private static var appSupportDirectoryURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
    }

    private static func stringEnv(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func boolEnv(_ key: String, defaultValue: Bool) -> Bool {
        guard let value = stringEnv(key)?.lowercased() else { return defaultValue }
        switch value {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func intEnv(_ key: String, defaultValue: Int) -> Int {
        guard let value = stringEnv(key), let parsed = Int(value) else { return defaultValue }
        return parsed
    }

    private static func floatEnv(_ key: String, defaultValue: Float) -> Float {
        guard let value = stringEnv(key), let parsed = Float(value) else { return defaultValue }
        return parsed
    }

    private static func timeIntervalEnv(_ key: String, defaultValue: TimeInterval) -> TimeInterval {
        guard let value = stringEnv(key), let parsed = TimeInterval(value) else { return defaultValue }
        return parsed
    }
}
