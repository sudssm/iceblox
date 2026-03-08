import XCTest
@testable import CamerasApp

final class AlertClientTests: XCTestCase {

    // MARK: - GPS Truncation

    func testTruncatePositiveCoordinate() {
        XCTAssertEqual(AlertClient.truncateCoordinate(34.0567), 34.05)
    }

    func testTruncateNegativeCoordinate() {
        XCTAssertEqual(AlertClient.truncateCoordinate(-118.2437), -118.25)
    }

    func testTruncateAlreadyTwoDecimals() {
        XCTAssertEqual(AlertClient.truncateCoordinate(40.71), 40.71)
    }

    func testTruncateZero() {
        XCTAssertEqual(AlertClient.truncateCoordinate(0.0), 0.0)
    }

    func testTruncateRoundsDown() {
        XCTAssertEqual(AlertClient.truncateCoordinate(34.999), 34.99)
    }

    func testTruncateNegativeRoundsTowardNegativeInfinity() {
        XCTAssertEqual(AlertClient.truncateCoordinate(-0.001), -0.01)
    }

    // MARK: - Subscribe Request Encoding

    func testSubscribeRequestEncoding() throws {
        let request = SubscribeRequest(latitude: 34.05, longitude: -118.24, radius_miles: 100)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(decoded["latitude"] as? Double, 34.05)
        XCTAssertEqual(decoded["longitude"] as? Double, -118.24)
        XCTAssertEqual(decoded["radius_miles"] as? Double, 100)
    }

    // MARK: - Subscribe Response Parsing

    func testSubscribeResponseWithSightings() throws {
        let json = """
        {
            "status": "ok",
            "recent_sightings": [
                {
                    "plate": "ABC1234",
                    "latitude": 34.05,
                    "longitude": -118.24,
                    "seen_at": "2024-01-01T00:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SubscribeResponse.self, from: json)
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.recent_sightings?.count, 1)
        XCTAssertEqual(response.recent_sightings?.first?.plate, "ABC1234")
        XCTAssertEqual(response.recent_sightings?.first?.latitude, 34.05)
        XCTAssertEqual(response.recent_sightings?.first?.longitude, -118.24)
    }

    func testSubscribeResponseWithoutSightings() throws {
        let json = """
        {"status": "ok"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SubscribeResponse.self, from: json)
        XCTAssertEqual(response.status, "ok")
        XCTAssertNil(response.recent_sightings)
    }

    func testSubscribeResponseEmptySightings() throws {
        let json = """
        {"status": "ok", "recent_sightings": []}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SubscribeResponse.self, from: json)
        XCTAssertEqual(response.recent_sightings?.count, 0)
    }

    // MARK: - AlertClient Initial State

    func testInitialSightingsCountIsZero() {
        let lm = LocationManager()
        let client = AlertClient(locationManager: lm)
        XCTAssertEqual(client.nearbySightings, 0)
    }
}
