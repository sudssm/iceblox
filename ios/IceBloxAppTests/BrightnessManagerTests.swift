import XCTest
@testable import IceBloxApp

final class BrightnessManagerTests: XCTestCase {

    func testInitialState() {
        let manager = BrightnessManager()
        XCTAssertFalse(manager.isDimmed)
        XCTAssertNil(manager.savedBrightness)
    }

    func testDimSavesBrightnessAndSetsDimmed() {
        var manager = BrightnessManager()
        manager.dim()
        XCTAssertTrue(manager.isDimmed)
        XCTAssertNotNil(manager.savedBrightness)
    }

    func testDimPreservesOriginalBrightnessOnRepeatedCalls() {
        var manager = BrightnessManager()
        manager.dim()
        let firstSaved = manager.savedBrightness
        manager.dim()
        XCTAssertEqual(manager.savedBrightness, firstSaved)
    }

    func testRestoreWithoutDimIsNoOp() {
        var manager = BrightnessManager()
        manager.restore()
        XCTAssertFalse(manager.isDimmed)
        XCTAssertNil(manager.savedBrightness)
    }

    func testRestoreAfterDimClearsDimmedFlag() {
        var manager = BrightnessManager()
        manager.dim()
        manager.restore()
        XCTAssertFalse(manager.isDimmed)
        XCTAssertNotNil(manager.savedBrightness)
    }

    func testTeardownClearsAllState() {
        var manager = BrightnessManager()
        manager.dim()
        XCTAssertTrue(manager.isDimmed)
        XCTAssertNotNil(manager.savedBrightness)

        manager.teardown()
        XCTAssertFalse(manager.isDimmed)
        XCTAssertNil(manager.savedBrightness)
    }

    func testTemporarilyRestoreRequiresDimmedState() {
        var manager = BrightnessManager()
        manager.temporarilyRestore()
        XCTAssertFalse(manager.isDimmed)
    }

    func testTemporarilyRestoreFromDimmedState() {
        var manager = BrightnessManager()
        manager.dim()
        manager.temporarilyRestore()
        XCTAssertTrue(manager.isDimmed)
        XCTAssertNotNil(manager.savedBrightness)
    }

    func testTeardownAfterTemporarilyRestore() {
        var manager = BrightnessManager()
        manager.dim()
        manager.temporarilyRestore()
        manager.teardown()
        XCTAssertFalse(manager.isDimmed)
        XCTAssertNil(manager.savedBrightness)
    }

    func testDimAfterRestoreReDims() {
        var manager = BrightnessManager()
        manager.dim()
        manager.restore()
        XCTAssertFalse(manager.isDimmed)

        manager.dim()
        XCTAssertTrue(manager.isDimmed)
    }
}
