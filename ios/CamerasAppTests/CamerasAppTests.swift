import XCTest
@testable import CamerasApp

final class CamerasAppTests: XCTestCase {
    func testCameraManagerInitialState() throws {
        let manager = CameraManager()
        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(manager.permissionGranted)
        XCTAssertFalse(manager.permissionDenied)
    }

    func testCameraSessionStartsEmpty() throws {
        let manager = CameraManager()
        XCTAssertTrue(manager.session.inputs.isEmpty)
        XCTAssertTrue(manager.session.outputs.isEmpty)
    }
}
