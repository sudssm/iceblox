import AVFoundation
import Combine
import CoreVideo

struct FrameResult {
    let plateText: String
    let hash: String
    let boundingBox: CGRect
    let confidence: Float
}

struct RawDetectionBox {
    let boundingBox: CGRect
    let confidence: Float
    let imageWidth: Int
    let imageHeight: Int
}

enum DetectionState {
    case queued, sent, matched
}

struct DetectionFeedEntry: Identifiable {
    let id = UUID()
    let plateText: String
    let hashPrefix: String
    var state: DetectionState
    let timestamp: Date
}

final class FrameProcessor: ObservableObject {
    let detector = PlateDetector()
    let dedupCache = DeduplicationCache()
    let offlineQueue: OfflineQueue
    let locationManager: LocationManager
    let apiClient: APIClient

    @Published var totalPlates = 0
    @Published var lastDetectionTime: Date?
    @Published var currentDetections: [FrameResult] = []
    @Published var rawDetections: [RawDetectionBox] = []
    @Published var detectionFeed: [DetectionFeedEntry] = []
    @Published var fps: Double = 0

    private var frameCount = 0
    private var fpsFrameCount = 0
    private var fpsTimer = Date()

    init(offlineQueue: OfflineQueue, locationManager: LocationManager, apiClient: APIClient) {
        self.offlineQueue = offlineQueue
        self.locationManager = locationManager
        self.apiClient = apiClient
        detector.loadModel()
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer, skipCount: Int) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer, skipCount: skipCount)
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer, skipCount: Int) {
        frameCount += 1
        if frameCount % (skipCount + 1) != 0 { return }

        updateFPS()

        let detections = detector.detect(pixelBuffer: pixelBuffer)
        DebugLog.shared.d("FrameProcessor", "\(detections.count) raw detections")

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let rawBoxes = detections.map { detection in
            RawDetectionBox(
                boundingBox: detection.boundingBox,
                confidence: detection.confidence,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        }

        var results: [FrameResult] = []

        for detection in detections {
            guard let cropped = PlateDetector.cropPlateRegion(
                from: detection.pixelBuffer,
                rect: detection.boundingBox
            ) else { continue }

            guard let rawText = PlateOCR.recognizeText(in: cropped) else { continue }
            guard let normalized = PlateNormalizer.normalize(rawText) else { continue }

            if dedupCache.isDuplicate(normalized) { continue }

            let hash = PlateHasher.hash(normalizedPlate: normalized)
            DebugLog.shared.d("FrameProcessor", "Plate: \(normalized) hash=\(String(hash.prefix(8)))")

            // Immediately discard normalized text from further use (privacy: REQ-M-13)
            let entry = OfflineQueueEntry(
                plateHash: hash,
                latitude: locationManager.latitude,
                longitude: locationManager.longitude
            )
            offlineQueue.enqueue(entry)

            let feedEntry = DetectionFeedEntry(
                plateText: normalized,
                hashPrefix: String(hash.prefix(8)),
                state: .queued,
                timestamp: Date()
            )
            addFeedEntry(feedEntry)

            results.append(FrameResult(
                plateText: rawText,
                hash: hash,
                boundingBox: detection.boundingBox,
                confidence: detection.confidence
            ))

            DispatchQueue.main.async { [weak self] in
                self?.totalPlates += 1
                self?.lastDetectionTime = Date()
            }

            apiClient.checkAndFlush()
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentDetections = results
            self?.rawDetections = rawBoxes
        }
    }

    func onPlateSent(hash: String, matched: Bool) {
        let prefix = String(hash.prefix(8))
        let newState: DetectionState = matched ? .matched : .sent
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var feed = self.detectionFeed
            if let idx = feed.lastIndex(where: { $0.hashPrefix == prefix && $0.state == .queued }) {
                feed[idx] = DetectionFeedEntry(
                    plateText: feed[idx].plateText,
                    hashPrefix: feed[idx].hashPrefix,
                    state: newState,
                    timestamp: feed[idx].timestamp
                )
                self.detectionFeed = feed
            }
        }
    }

    private func addFeedEntry(_ entry: DetectionFeedEntry) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var feed = self.detectionFeed
            feed.insert(entry, at: 0)
            if feed.count > 20 {
                feed = Array(feed.prefix(20))
            }
            self.detectionFeed = feed
        }
    }

    private func updateFPS() {
        fpsFrameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(fpsTimer)
        if elapsed >= 1.0 {
            let count = fpsFrameCount
            DispatchQueue.main.async { [weak self] in
                self?.fps = Double(count) / elapsed
            }
            fpsFrameCount = 0
            fpsTimer = now
        }
    }
}
