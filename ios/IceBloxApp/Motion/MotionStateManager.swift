import Combine
import CoreLocation
import Foundation

enum MotionState {
    case unknown
    case moving
    case stationary
}

final class MotionStateManager: ObservableObject {
    private var pollingTimer: Timer?
    private var stationaryStartTime: Date?
    private var isMonitoring = false
    private var locationSubscription: AnyCancellable?
    private weak var locationManager: LocationManager?

    private static let movingSpeedThreshold: CLLocationSpeed = 0.5

    @Published var motionState: MotionState = .unknown
    @Published var isMotionPaused = false

    var timeoutMinutes: TimeInterval = AppConfig.stationaryTimeoutMinutes

    func startMonitoring(locationManager: LocationManager) {
        guard !isMonitoring else { return }
        isMonitoring = true
        self.locationManager = locationManager

        locationSubscription = locationManager.$lastSpeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speed in
                self?.handleSpeed(speed)
            }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkStationaryTimeout()
        }
    }

    func stopMonitoring() {
        locationSubscription?.cancel()
        locationSubscription = nil
        locationManager = nil
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

    private func handleSpeed(_ speed: CLLocationSpeed?) {
        guard let speed, speed >= 0 else { return }

        if speed >= Self.movingSpeedThreshold {
            motionState = .moving
            stationaryStartTime = nil
            if isMotionPaused {
                isMotionPaused = false
            }
        } else {
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
