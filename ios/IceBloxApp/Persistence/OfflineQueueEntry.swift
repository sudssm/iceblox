import Foundation

struct OfflineQueueEntry: Codable {
    let id: Int64?
    let plateHash: String
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let sessionID: String
    let confidence: Float
    let isPrimary: Bool

    init(
        plateHash: String,
        timestamp: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        sessionID: String,
        confidence: Float = 0,
        isPrimary: Bool = false
    ) {
        self.id = nil
        self.plateHash = plateHash
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.sessionID = sessionID
        self.confidence = confidence
        self.isPrimary = isPrimary
    }

    // swiftlint:disable:next line_length
    init(id: Int64, plateHash: String, timestamp: Date, latitude: Double?, longitude: Double?, sessionID: String, confidence: Float = 0, isPrimary: Bool = false) {
        self.id = id
        self.plateHash = plateHash
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.sessionID = sessionID
        self.confidence = confidence
        self.isPrimary = isPrimary
    }
}
