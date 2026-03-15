import AVFoundation
import Combine
import CoreVideo
import UIKit

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

struct FailedDetection {
    let boundingBox: CGRect
    let imageWidth: Int
    let imageHeight: Int
}

struct DetectionResult {
    let results: [FrameResult]
    let rawBoxes: [RawDetectionBox]
    let failedDetections: [FailedDetection]
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
    let isExpanded: Bool
}

final class FrameProcessor: ObservableObject {
    let detector = PlateDetector()
    let dedupCache = DeduplicationCache()
    let offlineQueue: OfflineQueue
    let locationManager: LocationManager
    let apiClient: APIClient
    let sessionID: String
    let frameDiffer = FrameDiffer()

    @Published var totalPlates = 0
    @Published var lastDetectionTime: Date?
    @Published var currentDetections: [FrameResult] = []
    @Published var rawDetections: [RawDetectionBox] = []
    @Published var detectionFeed: [DetectionFeedEntry] = []
    @Published var fps: Double = 0
    @Published var framesSkippedByDiff = 0

    @Published var zoomRetryFrozen = false
    @Published var frozenPreviewImage: UIImage?

    var isAcceptingDetections = true
    var zoomController: ZoomController?
    var isThrottled = false
    var debugMode = false

    private var frameCount = 0
    private var fpsFrameCount = 0
    private var fpsTimer = Date()
    private var awaitingZoomedFrame = false
    private var zoomRetryStartTime: Date?
    private var framesToSkipAfterZoom = 0
    private let ciContext = CIContext()

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

        if awaitingZoomedFrame {
            if framesToSkipAfterZoom > 0 {
                framesToSkipAfterZoom -= 1
                return
            }
            processZoomedFrame(pixelBuffer)
            return
        }

        frameCount += 1
        if frameCount % (skipCount + 1) != 0 { return }

        updateFPS()

        if AppConfig.frameDiffEnabled && !frameDiffer.shouldProcess(pixelBuffer: pixelBuffer) {
            framesSkippedByDiff = frameDiffer.framesSkippedByDiff
            return
        }

        let detection = detectAndProcess(pixelBuffer: pixelBuffer)

        if !detection.failedDetections.isEmpty {
            attemptZoomRetry(failedDetections: detection.failedDetections, sampleBuffer: sampleBuffer)
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentDetections = detection.results
            self?.rawDetections = detection.rawBoxes
        }
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer, skipCount: Int) {
        guard isAcceptingDetections else { return }
        frameCount += 1
        if frameCount % (skipCount + 1) != 0 { return }

        updateFPS()

        if AppConfig.frameDiffEnabled && !frameDiffer.shouldProcess(pixelBuffer: pixelBuffer) {
            framesSkippedByDiff = frameDiffer.framesSkippedByDiff
            return
        }

        let detection = detectAndProcess(pixelBuffer: pixelBuffer)

        DispatchQueue.main.async { [weak self] in
            self?.currentDetections = detection.results
            self?.rawDetections = detection.rawBoxes
        }
    }

    private func detectAndProcess(pixelBuffer: CVPixelBuffer) -> DetectionResult {
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
        var failedDetections: [FailedDetection] = []

        for detection in detections {
            guard isAcceptingDetections else { break }
            guard let cropped = PlateDetector.cropPlateRegion(
                from: detection.pixelBuffer,
                rect: detection.boundingBox
            ) else {
                DebugLog.shared.w("FrameProcessor", "Crop failed for box: \(detection.boundingBox)")
                continue
            }

            if let ocrOutput = PlateOCR.recognizeText(in: cropped) {
                guard let normalized = PlateNormalizer.normalize(ocrOutput.text) else {
                    DebugLog.shared.w("FrameProcessor", "Normalization failed for raw text (\(ocrOutput.text.count) chars)")
                    continue
                }
                let charConfs = Array(ocrOutput.charConfidences.prefix(normalized.count))
                let slotCands = Array(ocrOutput.slotCandidates.prefix(normalized.count))
                guard let result = recordPlate(
                    rawText: ocrOutput.text,
                    normalizedText: normalized,
                    boundingBox: detection.boundingBox,
                    confidence: detection.confidence,
                    charConfidences: charConfs,
                    slotCandidates: slotCands
                ) else { continue }
                results.append(result)
            } else {
                failedDetections.append(FailedDetection(
                    boundingBox: detection.boundingBox,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight
                ))
            }
        }

        return DetectionResult(results: results, rawBoxes: rawBoxes, failedDetections: failedDetections)
    }

    private func attemptZoomRetry(
        failedDetections: [FailedDetection],
        sampleBuffer: CMSampleBuffer
    ) {
        guard let zoomController,
              zoomController.isZoomRetryAvailable,
              !zoomController.isOnCooldown(),
              !isThrottled else { return }

        guard zoomController.bestCandidateIndex(detections: failedDetections) != nil else { return }

        let frozenImage = debugMode ? nil : imageFromSampleBuffer(sampleBuffer)

        DispatchQueue.main.async { [weak self] in
            self?.frozenPreviewImage = frozenImage
            self?.zoomRetryFrozen = true
        }

        guard zoomController.zoomIn() else {
            DispatchQueue.main.async { [weak self] in
                self?.zoomRetryFrozen = false
                self?.frozenPreviewImage = nil
            }
            return
        }

        awaitingZoomedFrame = true
        zoomRetryStartTime = Date()
        framesToSkipAfterZoom = 2
        DebugLog.shared.d("FrameProcessor", "Zoom retry: zooming to \(zoomController.maxOpticalZoom)x")
    }

    private func processZoomedFrame(_ pixelBuffer: CVPixelBuffer) {
        defer {
            awaitingZoomedFrame = false
            zoomRetryStartTime = nil
            zoomController?.restoreZoom()
            DispatchQueue.main.async { [weak self] in
                self?.zoomRetryFrozen = false
                self?.frozenPreviewImage = nil
            }
        }

        if let startTime = zoomRetryStartTime {
            let elapsedMs = Date().timeIntervalSince(startTime) * 1000
            if elapsedMs > Double(AppConfig.zoomRetryMaxWaitMs) {
                DebugLog.shared.w("FrameProcessor", "Zoom retry timed out after \(Int(elapsedMs))ms")
                return
            }
        }

        let detections = detector.detect(pixelBuffer: pixelBuffer)
        DebugLog.shared.d("FrameProcessor", "Zoom retry: \(detections.count) detections in zoomed frame")

        var zoomedResults: [FrameResult] = []

        for detection in detections {
            guard isAcceptingDetections else { break }
            guard let cropped = PlateDetector.cropPlateRegion(
                from: detection.pixelBuffer,
                rect: detection.boundingBox
            ) else { continue }

            guard let ocrOutput = PlateOCR.recognizeText(in: cropped) else { continue }
            guard let normalized = PlateNormalizer.normalize(ocrOutput.text) else { continue }
            let charConfs = Array(ocrOutput.charConfidences.prefix(normalized.count))
            let slotCands = Array(ocrOutput.slotCandidates.prefix(normalized.count))
            guard let result = recordPlate(
                rawText: ocrOutput.text,
                normalizedText: normalized,
                boundingBox: detection.boundingBox,
                confidence: detection.confidence,
                charConfidences: charConfs,
                slotCandidates: slotCands
            ) else { continue }

            zoomedResults.append(result)
            zoomController?.recordSuccess()
            DebugLog.shared.d("FrameProcessor", "Zoom retry SUCCESS: \(normalized)")
        }

        if !zoomedResults.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var current = self.currentDetections
                current.append(contentsOf: zoomedResults)
                self.currentDetections = current
            }
        }
    }

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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

        let charConfs = [Float](repeating: 0, count: normalized.count)
        guard let result = recordPlate(
            rawText: plateText,
            normalizedText: normalized,
            boundingBox: boundingBox,
            confidence: 1.0,
            charConfidences: charConfs,
            slotCandidates: []
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
        let newState: DetectionState = matched ? .matched : .sent

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var feed = self.detectionFeed
            if let idx = feed.lastIndex(where: { $0.hashPrefix == prefix && $0.state == .queued }) {
                feed[idx] = DetectionFeedEntry(
                    plateText: feed[idx].plateText,
                    hashPrefix: feed[idx].hashPrefix,
                    state: newState,
                    timestamp: feed[idx].timestamp,
                    isExpanded: feed[idx].isExpanded
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
        confidence: Float,
        charConfidences: [Float],
        slotCandidates: [[PlateOCR.SlotCandidate]] = []
    ) -> FrameResult? {
        if dedupCache.isDuplicate(normalizedText) { return nil }

        let variants = LookalikeExpander.expand(normalizedText, charConfidences: charConfidences, slotCandidates: slotCandidates)
        let primaryHash = PlateHasher.hash(normalizedPlate: variants[0].0)

        DebugLog.shared.d("FrameProcessor", "Plate: \(normalizedText) hash=\(String(primaryHash.prefix(8))) variants=\(variants.count)")

        for (variantText, substitutions, variantConfidence) in variants {
            let hash = substitutions == 0 ? primaryHash : PlateHasher.hash(normalizedPlate: variantText)
            let prefix = String(hash.prefix(8))
            let isPrimary = substitutions == 0

            offlineQueue.enqueue(OfflineQueueEntry(
                plateHash: hash,
                latitude: locationManager.latitude,
                longitude: locationManager.longitude,
                sessionID: sessionID,
                confidence: variantConfidence,
                isPrimary: isPrimary
            ))

            addFeedEntry(DetectionFeedEntry(
                plateText: variantText,
                hashPrefix: prefix,
                state: .queued,
                timestamp: Date(),
                isExpanded: !isPrimary
            ))
        }

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
