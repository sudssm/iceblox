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

final class PlateNormalizerTests: XCTestCase {
    func testBasicNormalization() {
        XCTAssertEqual(PlateNormalizer.normalize("abc 1234"), "ABC1234")
    }

    func testRemovesHyphens() {
        XCTAssertEqual(PlateNormalizer.normalize("AB-1234"), "AB1234")
    }

    func testRemovesWhitespace() {
        XCTAssertEqual(PlateNormalizer.normalize("AB  12 34"), "AB1234")
    }

    func testUppercases() {
        XCTAssertEqual(PlateNormalizer.normalize("abc"), "ABC")
    }

    func testRemovesNonAlphanumeric() {
        XCTAssertEqual(PlateNormalizer.normalize("AB@#1234"), "AB1234")
    }

    func testTruncatesTo8Chars() {
        XCTAssertEqual(PlateNormalizer.normalize("ABCDEFGHIJ"), "ABCDEFGH")
    }

    func testRejectsTooShort() {
        XCTAssertNil(PlateNormalizer.normalize("A"))
    }

    func testRejectsEmpty() {
        XCTAssertNil(PlateNormalizer.normalize(""))
    }

    func testRejectsAllSymbols() {
        XCTAssertNil(PlateNormalizer.normalize("@#$"))
    }

    func testAcceptsMinLength() {
        XCTAssertEqual(PlateNormalizer.normalize("AB"), "AB")
    }

    func testAcceptsMaxLength() {
        XCTAssertEqual(PlateNormalizer.normalize("ABCD1234"), "ABCD1234")
    }
}
