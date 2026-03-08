import AVFoundation
import CoreVideo

struct FrameResult {
    let plateText: String
    let hash: String
    let boundingBox: CGRect
    let confidence: Float
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
    @Published var fps: Double = 0

    private var frameCount = 0
    private var fpsTimer: Date = Date()

    init(offlineQueue: OfflineQueue, locationManager: LocationManager, apiClient: APIClient) {
        self.offlineQueue = offlineQueue
        self.locationManager = locationManager
        self.apiClient = apiClient
        detector.loadModel()
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer, skipCount: Int) {
        frameCount += 1
        if frameCount % (skipCount + 1) != 0 { return }

        updateFPS()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let detections = detector.detect(pixelBuffer: pixelBuffer)
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

            // Immediately discard normalized text from further use (privacy: REQ-M-13)
            let entry = OfflineQueueEntry(
                plateHash: hash,
                latitude: locationManager.latitude,
                longitude: locationManager.longitude
            )
            offlineQueue.enqueue(entry)

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
        }
    }

    private func updateFPS() {
        let now = Date()
        let elapsed = now.timeIntervalSince(fpsTimer)
        if elapsed >= 1.0 {
            DispatchQueue.main.async { [weak self] in
                self?.fps = Double(self?.frameCount ?? 0) / elapsed
            }
            frameCount = 0
            fpsTimer = now
        }
    }
}
