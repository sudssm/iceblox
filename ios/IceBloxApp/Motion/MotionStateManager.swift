import CoreMotion
import Foundation

enum MotionState {
    case unknown
    case moving
    case stationary
}

final class MotionStateManager: ObservableObject {
    private let activityManager = CMMotionActivityManager()
    private var pollingTimer: Timer?
    private var stationaryStartTime: Date?
    private var isMonitoring = false

    @Published var motionState: MotionState = .unknown
    @Published var isMotionPaused = false

    var timeoutMinutes: TimeInterval = AppConfig.stationaryTimeoutMinutes

    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        guard !isMonitoring else { return }
        isMonitoring = true

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity, activity.confidence != .low else { return }
            self.handleActivity(activity)
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkStationaryTimeout()
        }
    }

    func stopMonitoring() {
        activityManager.stopActivityUpdates()
        pollingTimer?.invalidate()
        pollingTimer = nil
        stationaryStartTime = nil
        isMonitoring = false
        motionState = .unknown
        isMotionPaused = false
    }

    func manualResume() {
        isMotionPaused = false
        stationaryStartTime = nil
    }

    private func handleActivity(_ activity: CMMotionActivity) {
        if activity.automotive || activity.walking || activity.running || activity.cycling {
            motionState = .moving
            stationaryStartTime = nil
            if isMotionPaused {
                isMotionPaused = false
            }
        } else if activity.stationary {
            motionState = .stationary
            if stationaryStartTime == nil {
                stationaryStartTime = Date()
            }
        }
    }

    private func checkStationaryTimeout() {
        guard let startTime = stationaryStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed >= timeoutMinutes * 60 && !isMotionPaused {
            isMotionPaused = true
        }
    }
}
