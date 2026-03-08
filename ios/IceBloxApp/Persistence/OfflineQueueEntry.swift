import Foundation

struct OfflineQueueEntry: Codable {
    let id: Int64?
    let plateHash: String
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?

    init(plateHash: String, timestamp: Date = Date(), latitude: Double? = nil, longitude: Double? = nil) {
        self.id = nil
        self.plateHash = plateHash
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
    }

    init(id: Int64, plateHash: String, timestamp: Date, latitude: Double?, longitude: Double?) {
        self.id = id
        self.plateHash = plateHash
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
    }
}
