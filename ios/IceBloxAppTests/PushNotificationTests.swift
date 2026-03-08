import XCTest
@testable import IceBloxApp

final class PushNotificationTests: XCTestCase {

    // MARK: - Device Token Hex Conversion

    func testHexStringFromKnownBytes() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(DeviceTokenHelper.hexString(from: data), "deadbeef")
    }

    func testHexStringAllZeros() {
        let data = Data([0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(DeviceTokenHelper.hexString(from: data), "00000000")
    }

    func testHexStringAllFF() {
        let data = Data([0xFF, 0xFF])
        XCTAssertEqual(DeviceTokenHelper.hexString(from: data), "ffff")
    }

    func testHexStringEmptyData() {
        let data = Data()
        XCTAssertEqual(DeviceTokenHelper.hexString(from: data), "")
    }

    func testHexStringProducesLowercaseHex() {
        let data = Data([0xAB, 0xCD])
        let hex = DeviceTokenHelper.hexString(from: data)
        XCTAssertEqual(hex, hex.lowercased())
    }

    func testHexStringLength() {
        let data = Data(repeating: 0xAA, count: 32)
        XCTAssertEqual(DeviceTokenHelper.hexString(from: data).count, 64)
    }

    func testHexStringEachByteIsTwoChars() {
        let data = Data([0x0F])
        XCTAssertEqual(DeviceTokenHelper.hexString(from: data), "0f")
    }

    // MARK: - AppConfig Endpoints

    func testDevicesEndpointConfigured() {
        XCTAssertEqual(AppConfig.devicesEndpoint, "/api/v1/devices")
    }

    func testSubscribeEndpointConfigured() {
        XCTAssertEqual(AppConfig.subscribeEndpoint, "/api/v1/subscribe")
    }

    func testSubscribeIntervalIsTenMinutes() {
        XCTAssertEqual(AppConfig.subscribeIntervalSeconds, 600)
    }

    func testDefaultRadiusMiles() {
        XCTAssertEqual(AppConfig.defaultRadiusMiles, 100)
    }
}
