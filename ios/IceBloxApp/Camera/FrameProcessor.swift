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
    let sessionID: String

    @Published var totalPlates = 0
    @Published var lastDetectionTime: Date?
    @Published var currentDetections: [FrameResult] = []
    @Published var rawDetections: [RawDetectionBox] = []
    @Published var detectionFeed: [DetectionFeedEntry] = []
    @Published var fps: Double = 0

    var isAcceptingDetections = true

    private var frameCount = 0
    private var fpsFrameCount = 0
    private var fpsTimer = Date()
    private var variantHashMap: [String: String] = [:]
    private let variantHashQueue = DispatchQueue(label: "com.iceblox.variantHashMap")

    init(offlineQueue: OfflineQueue, locationManager: LocationManager, apiClient: APIClient, sessionID: String) {
        self.offlineQueue = offlineQueue
        self.locationManager = locationManager
        self.apiClient = apiClient
        self.sessionID = sessionID
        detector.loadModel()
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer, skipCount: Int) {
        guard isAcceptingDetections else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer, skipCount: skipCount)
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer, skipCount: Int) {
        guard isAcceptingDetections else { return }
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
            guard isAcceptingDetections else { break }
            guard let cropped = PlateDetector.cropPlateRegion(
                from: detection.pixelBuffer,
                rect: detection.boundingBox
            ) else { continue }

            guard let rawText = PlateOCR.recognizeText(in: cropped) else { continue }
            guard let normalized = PlateNormalizer.normalize(rawText) else { continue }
            guard let result = recordPlate(
                rawText: rawText,
                normalizedText: normalized,
                boundingBox: detection.boundingBox,
                confidence: detection.confidence
            ) else {
                continue
            }
            results.append(result)
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentDetections = results
            self?.rawDetections = rawBoxes
        }
    }

    func processSimulatedPlate(_ plateText: String, imageWidth: Int, imageHeight: Int) {
        guard isAcceptingDetections else { return }
        updateFPS()

        guard let normalized = PlateNormalizer.normalize(plateText) else { return }

        let boundingBox = CGRect(
            x: CGFloat(imageWidth) * 0.2,
            y: CGFloat(imageHeight) * 0.4,
            width: CGFloat(imageWidth) * 0.6,
            height: CGFloat(imageHeight) * 0.2
        )

        guard let result = recordPlate(
            rawText: plateText,
            normalizedText: normalized,
            boundingBox: boundingBox,
            confidence: 1.0
        ) else {
            return
        }

        DebugLog.shared.d("FrameProcessor", "Simulated plate: \(normalized) hash=\(String(result.hash.prefix(8)))")

        DispatchQueue.main.async { [weak self] in
            self?.currentDetections = [result]
            self?.rawDetections = [
                RawDetectionBox(
                    boundingBox: boundingBox,
                    confidence: 1.0,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight
                )
            ]
        }
    }

    func onPlateSent(hash: String, matched: Bool) {
        let prefix = String(hash.prefix(8))
        let primaryPrefix = variantHashQueue.sync { variantHashMap[prefix] } ?? prefix
        let newState: DetectionState = matched ? .matched : .sent
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var feed = self.detectionFeed
            let idx: Int? = if matched {
                feed.lastIndex(where: { $0.hashPrefix == primaryPrefix && $0.state != .matched })
            } else {
                feed.lastIndex(where: { $0.hashPrefix == primaryPrefix && $0.state == .queued })
            }
            if let idx {
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

    private func recordPlate(
        rawText: String,
        normalizedText: String,
        boundingBox: CGRect,
        confidence: Float
    ) -> FrameResult? {
        if dedupCache.isDuplicate(normalizedText) { return nil }

        let variants = LookalikeExpander.expand(normalizedText)
        let primaryHash = PlateHasher.hash(normalizedPlate: variants[0].0)
        let primaryPrefix = String(primaryHash.prefix(8))

        DebugLog.shared.d("FrameProcessor", "Plate: \(normalizedText) hash=\(primaryPrefix) variants=\(variants.count)")

        for (variantText, substitutions) in variants {
            let hash = substitutions == 0 ? primaryHash : PlateHasher.hash(normalizedPlate: variantText)
            let prefix = String(hash.prefix(8))
            if prefix != primaryPrefix {
                variantHashQueue.sync { variantHashMap[prefix] = primaryPrefix }
            }
            let entry = OfflineQueueEntry(
                plateHash: hash,
                latitude: locationManager.latitude,
                longitude: locationManager.longitude,
                sessionID: sessionID,
                substitutions: substitutions
            )
            offlineQueue.enqueue(entry)
        }

        let extraCount = variants.count - 1
        let feedText = extraCount > 0 ? "\(normalizedText) (+\(extraCount))" : normalizedText

        let feedEntry = DetectionFeedEntry(
            plateText: feedText,
            hashPrefix: primaryPrefix,
            state: .queued,
            timestamp: Date()
        )
        addFeedEntry(feedEntry)

        DispatchQueue.main.async { [weak self] in
            self?.totalPlates += 1
            self?.lastDetectionTime = Date()
        }

        apiClient.checkAndFlush()

        return FrameResult(
            plateText: rawText,
            hash: primaryHash,
            boundingBox: boundingBox,
            confidence: confidence
        )
    }
}
