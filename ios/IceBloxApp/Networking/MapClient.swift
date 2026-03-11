import Foundation

struct MapSighting: Codable {
    let latitude: Double
    let longitude: Double
    let confidence: Double
    let seenAt: String
    let type: String
    let description: String?
    let photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, confidence, type, description
        case seenAt = "seen_at"
        case photoUrl = "photo_url"
    }
}

struct MapSightingsResponse: Codable {
    let status: String
    let sightings: [MapSighting]
}

final class MapClient {
    private let session = URLSession.shared

    func fetchSightings(lat: Double, lng: Double, radius: Double) async throws -> [MapSighting] {
        guard var components = URLComponents(
            url: AppConfig.serverBaseURL.appendingPathComponent(AppConfig.mapSightingsEndpoint),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius", value: String(radius))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(MapSightingsResponse.self, from: data)
        return decoded.sightings
    }
}
