import Foundation
import UIKit

struct ContactResponse: Codable {
    let status: String
    let contactId: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case contactId = "contact_id"
    }
}

final class ContactClient {
    private let session = URLSession.shared

    func submitContact(
        name: String,
        email: String,
        message: String,
        logs: String?,
        completion: @escaping (Result<ContactResponse, Error>) -> Void
    ) {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let url = AppConfig.serverBaseURL.appendingPathComponent(AppConfig.contactEndpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        var body: [String: Any] = [
            "name": name,
            "email": email,
            "message": message,
            "hardware_id": deviceId
        ]
        if let logs, !logs.isEmpty {
            body["logs"] = logs
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ContactError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200, let data else {
                completion(.failure(ContactError.serverError(httpResponse.statusCode)))
                return
            }

            do {
                let contactResponse = try JSONDecoder().decode(ContactResponse.self, from: data)
                completion(.success(contactResponse))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

enum ContactError: LocalizedError {
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}
