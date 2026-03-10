import Foundation
import UIKit

struct ReportResponse: Codable {
    let status: String
    let reportId: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case reportId = "report_id"
    }
}

struct ReportSubmission {
    let photo: UIImage
    let description: String
    let plateNumber: String?
    let latitude: Double
    let longitude: Double
}

final class ReportClient {
    private let session = URLSession.shared

    func submitReport(
        _ submission: ReportSubmission,
        completion: @escaping (Result<ReportResponse, Error>) -> Void
    ) {
        guard let jpegData = submission.photo.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ReportError.photoCompression))
            return
        }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let url = AppConfig.serverBaseURL.appendingPathComponent(AppConfig.reportsEndpoint)
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        appendField("description", submission.description)
        appendField("latitude", String(submission.latitude))
        appendField("longitude", String(submission.longitude))
        if let plate = submission.plateNumber, !plate.isEmpty {
            appendField("plate_number", plate)
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"report.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpegData)
        body.append(Data("\r\n".utf8))

        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ReportError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200, let data else {
                completion(.failure(ReportError.serverError(httpResponse.statusCode)))
                return
            }

            do {
                let reportResponse = try JSONDecoder().decode(ReportResponse.self, from: data)
                completion(.success(reportResponse))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

enum ReportError: LocalizedError {
    case photoCompression
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .photoCompression:
            return "Failed to compress photo"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}
