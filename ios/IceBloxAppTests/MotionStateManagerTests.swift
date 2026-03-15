import XCTest
@testable import IceBloxApp

final class MotionStateManagerTests: XCTestCase {

    func testInitialState() {
        let manager = MotionStateManager()
        XCTAssertEqual(manager.motionState, .unknown)
        XCTAssertFalse(manager.isMotionPaused)
    }

    func testManualResumeClearsMotionPaused() {
        let manager = MotionStateManager()
        manager.isMotionPaused = true
        manager.manualResume()
        XCTAssertFalse(manager.isMotionPaused)
    }

    func testStopMonitoringResetsState() {
        let manager = MotionStateManager()
        manager.isMotionPaused = true
        manager.stopMonitoring()
        XCTAssertEqual(manager.motionState, .unknown)
        XCTAssertFalse(manager.isMotionPaused)
    }

    func testTimeoutDefaultsToAppConfig() {
        let manager = MotionStateManager()
        XCTAssertEqual(manager.timeoutMinutes, AppConfig.stationaryTimeoutMinutes)
    }
}
