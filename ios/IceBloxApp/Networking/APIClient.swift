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

struct BatchPlateRequest: Codable {
    let plates: [PlateSubmission]
}

struct BatchPlateResponse: Codable {
    let status: String
    let results: [PlateResult]?
}

struct PlateResult: Codable {
    let matched: Bool
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

        offlineQueue.removeExpired(olderThan: AppConfig.uploadTimeoutSeconds)

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let url = AppConfig.serverBaseURL.appendingPathComponent(AppConfig.platesEndpoint)
        let formatter = ISO8601DateFormatter()

        while true {
            let entries = offlineQueue.dequeue(limit: AppConfig.batchSize)
            guard !entries.isEmpty else { return }

            let submissions = entries.map { entry in
                PlateSubmission(
                    plate_hash: entry.plateHash,
                    latitude: entry.latitude,
                    longitude: entry.longitude,
                    timestamp: formatter.string(from: entry.timestamp),
                    substitutions: entry.substitutions
                )
            }
            let batch = BatchPlateRequest(plates: submissions)
            guard let body = try? JSONEncoder().encode(batch) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
            request.httpBody = body

            var shouldContinue = false
            let semaphore = DispatchSemaphore(value: 0)

            session.dataTask(with: request) { [weak self] data, response, error in
                defer { semaphore.signal() }

                if let error {
                    DebugLog.shared.w("APIClient", "Upload failed: \(error.localizedDescription)")
                    _ = self?.retryManager.handleFailure()
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
                    DebugLog.shared.d("APIClient", "Upload OK (\(entries.count) plates)")
                    self?.retryManager.reset()

                    let ids = entries.compactMap { $0.id }
                    self?.offlineQueue.remove(ids: ids)

                    if let data,
                       let batchResponse = try? JSONDecoder().decode(BatchPlateResponse.self, from: data),
                       let results = batchResponse.results {
                        for (i, result) in results.enumerated() where i < entries.count {
                            let entry = entries[i]
                            if result.matched, entry.sessionID == self?.currentSessionID {
                                DispatchQueue.main.async {
                                    self?.totalTargets += 1
                                }
                            }
                            self?.onPlateSent?(entry.plateHash, result.matched, entry.sessionID)
                        }
                    }
                    shouldContinue = true
                }
            }.resume()

            semaphore.wait()
            if !shouldContinue { return }
        }
    }
}
