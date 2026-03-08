import Combine
import Foundation
import UIKit

struct SubscribeRequest: Codable {
    let latitude: Double
    let longitude: Double
    let radiusMiles: Double

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case radiusMiles = "radius_miles"
    }
}

struct RecentSighting: Codable {
    let plate: String
    let latitude: Double
    let longitude: Double
    let seenAt: String

    enum CodingKeys: String, CodingKey {
        case plate
        case latitude
        case longitude
        case seenAt = "seen_at"
    }
}

struct SubscribeResponse: Codable {
    let status: String
    let recentSightings: [RecentSighting]?

    enum CodingKeys: String, CodingKey {
        case status
        case recentSightings = "recent_sightings"
    }
}

final class AlertClient: ObservableObject {
    private let session = URLSession.shared
    private var timer: Timer?
    private let locationManager: LocationManager

    @Published var nearbySightings: Int = 0

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    func startTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.subscribe()
            self?.timer = Timer.scheduledTimer(
                withTimeInterval: AppConfig.subscribeIntervalSeconds,
                repeats: true
            ) { [weak self] _ in
                self?.subscribe()
            }
        }
    }

    func stopTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    func subscribe() {
        guard let lat = locationManager.latitude,
              let lng = locationManager.longitude else {
            DebugLog.shared.d("AlertClient", "No location available, skipping subscribe")
            return
        }

        let truncatedLat = AlertClient.truncateCoordinate(lat)
        let truncatedLng = AlertClient.truncateCoordinate(lng)

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let url = AppConfig.serverBaseURL.appendingPathComponent(AppConfig.subscribeEndpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        let body = SubscribeRequest(
            latitude: truncatedLat,
            longitude: truncatedLng,
            radiusMiles: AppConfig.defaultRadiusMiles
        )
        guard let httpBody = try? JSONEncoder().encode(body) else {
            DebugLog.shared.e("AlertClient", "Failed to encode subscribe request")
            return
        }
        request.httpBody = httpBody

        session.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                DebugLog.shared.w("AlertClient", "Subscribe failed: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode != 200 {
                DebugLog.shared.w("AlertClient", "Subscribe returned status \(httpResponse.statusCode)")
                return
            }

            guard let data else { return }

            do {
                let subscribeResponse = try JSONDecoder().decode(SubscribeResponse.self, from: data)
                if let sightings = subscribeResponse.recentSightings {
                    for sighting in sightings {
                        DebugLog.shared.d("AlertClient", "Nearby sighting at (\(sighting.latitude), \(sighting.longitude)) seen \(sighting.seenAt)")
                    }
                    DispatchQueue.main.async {
                        self?.nearbySightings += sightings.count
                    }
                }
            } catch {
                DebugLog.shared.w("AlertClient", "Failed to decode subscribe response: \(error.localizedDescription)")
            }
        }.resume()
    }

    static func truncateCoordinate(_ value: Double) -> Double {
        floor(value * 100) / 100
    }

    deinit {
        timer?.invalidate()
    }
}
