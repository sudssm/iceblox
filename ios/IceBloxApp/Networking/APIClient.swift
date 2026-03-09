import Combine
import Foundation
import UIKit

struct PlateSubmission: Codable {
    let plate_hash: String
    let latitude: Double?
    let longitude: Double?
    let timestamp: String?
    let substitutions: Int
}

struct PlateResponse: Codable {
    let status: String
    let matched: Bool?
}

final class APIClient {
    private let session = URLSession.shared
    private let retryManager = RetryManager()
    private let offlineQueue: OfflineQueue
    private let uploadQueue = DispatchQueue(label: "api.upload")
    private let currentSessionID: String

    private var batchTimer: Timer?
    @Published var totalTargets = 0
    var onPlateSent: ((String, Bool, String) -> Void)?

    init(offlineQueue: OfflineQueue, currentSessionID: String) {
        self.offlineQueue = offlineQueue
        self.currentSessionID = currentSessionID
    }

    func startBatchTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.batchTimer?.invalidate()
            self?.batchTimer = Timer.scheduledTimer(
                withTimeInterval: AppConfig.batchIntervalSeconds,
                repeats: true
            ) { [weak self] _ in
                self?.flushQueue()
            }
        }
    }

    func stopBatchTimer() {
        batchTimer?.invalidate()
        batchTimer = nil
    }

    func flushQueue() {
        uploadQueue.async { [weak self] in
            self?.sendBatch()
        }
    }

    func checkAndFlush() {
        let count = offlineQueue.count
        if count >= AppConfig.batchSize {
            flushQueue()
        }
    }

    private func sendBatch() {
        guard !retryManager.isRateLimited else { return }

        let entries = offlineQueue.dequeue(limit: AppConfig.batchSize)
        guard !entries.isEmpty else { return }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let url = AppConfig.serverBaseURL.appendingPathComponent(AppConfig.platesEndpoint)

        for entry in entries {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

            let formatter = ISO8601DateFormatter()
            let submission = PlateSubmission(
                plate_hash: entry.plateHash,
                latitude: entry.latitude,
                longitude: entry.longitude,
                timestamp: formatter.string(from: entry.timestamp),
                substitutions: entry.substitutions
            )

            guard let body = try? JSONEncoder().encode(submission) else { continue }
            request.httpBody = body

            let semaphore = DispatchSemaphore(value: 0)
            var shouldRemove = false

            session.dataTask(with: request) { [weak self] data, response, error in
                defer { semaphore.signal() }

                if let error {
                    DebugLog.shared.w("APIClient", "Upload failed: \(error.localizedDescription)")
                    if let delay = self?.retryManager.handleFailure() {
                        Thread.sleep(forTimeInterval: delay)
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else { return }

                if httpResponse.statusCode == 429 {
                    let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                    DebugLog.shared.w("APIClient", "Rate limited for \(retryAfter)s")
                    self?.retryManager.handleRateLimit(retryAfter: retryAfter)
                    return
                }

                if httpResponse.statusCode == 200 {
                    DebugLog.shared.d("APIClient", "Upload OK")
                    shouldRemove = true
                    self?.retryManager.reset()

                    let matched: Bool
                    if let data,
                       let plateResponse = try? JSONDecoder().decode(PlateResponse.self, from: data) {
                        matched = plateResponse.matched == true
                        if matched, entry.sessionID == self?.currentSessionID {
                            DispatchQueue.main.async {
                                self?.totalTargets += 1
                            }
                        }
                    } else {
                        matched = false
                    }
                    self?.onPlateSent?(entry.plateHash, matched, entry.sessionID)
                }
            }.resume()

            semaphore.wait()
            if shouldRemove, let id = entry.id {
                offlineQueue.remove(ids: [id])
            }
        }
    }
}
