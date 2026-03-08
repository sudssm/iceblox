import XCTest
@testable import CamerasApp

final class CamerasAppTests: XCTestCase {
    func testContentViewExists() throws {
        let view = ContentView()
        XCTAssertNotNil(view)
    }
}
