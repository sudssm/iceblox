import AVFoundation
import CoreVideo

final class ZoomController {
    private let device: AVCaptureDevice
    let maxOpticalZoom: CGFloat
    let isZoomRetryAvailable: Bool

    private var lastRetryTime: Date = .distantPast
    private let cooldown: TimeInterval = AppConfig.zoomRetryCooldownSeconds
    private let margin: Double = AppConfig.zoomRetryMargin

    var zoomRetryAttempts = 0
    var zoomRetrySuccesses = 0

    init(device: AVCaptureDevice) {
        self.device = device
        let threshold = device.activeFormat.videoZoomFactorUpscaleThreshold
        self.maxOpticalZoom = threshold > 1.0 ? threshold : 1.0
        self.isZoomRetryAvailable = AppConfig.isZoomRetryEnabled && threshold > 1.0
        DebugLog.shared.d("ZoomController", "maxOpticalZoom=\(maxOpticalZoom) available=\(isZoomRetryAvailable)")
    }

    func isOnCooldown() -> Bool {
        Date().timeIntervalSince(lastRetryTime) < cooldown
    }

    func isPlateEligibleForZoom(boundingBox: CGRect, imageWidth: Int, imageHeight: Int) -> Bool {
        ZoomController.isPlateEligible(
            boundingBox: boundingBox,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            maxOpticalZoom: maxOpticalZoom,
            margin: margin
        )
    }

    static func isPlateEligible(
        boundingBox: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        maxOpticalZoom: CGFloat,
        margin: Double
    ) -> Bool {
        guard maxOpticalZoom > 1.0 else { return false }

        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)
        guard w > 0, h > 0 else { return false }

        let nx0 = boundingBox.minX / w
        let ny0 = boundingBox.minY / h
        let nx1 = boundingBox.maxX / w
        let ny1 = boundingBox.maxY / h

        let limit = 0.5 * (1.0 / maxOpticalZoom) * CGFloat(margin)

        let corners: [(CGFloat, CGFloat)] = [
            (nx0, ny0), (nx1, ny0), (nx0, ny1), (nx1, ny1)
        ]
        for (cx, cy) in corners {
            if abs(cx - 0.5) > limit || abs(cy - 0.5) > limit {
                return false
            }
        }
        return true
    }

    func bestCandidateIndex(detections: [(boundingBox: CGRect, imageWidth: Int, imageHeight: Int)]) -> Int? {
        var bestIdx: Int?
        var bestDist = Double.greatestFiniteMagnitude

        for (i, det) in detections.enumerated() {
            guard isPlateEligibleForZoom(boundingBox: det.boundingBox, imageWidth: det.imageWidth, imageHeight: det.imageHeight) else {
                continue
            }
            let w = CGFloat(det.imageWidth)
            let h = CGFloat(det.imageHeight)
            let cx = (det.boundingBox.midX / w) - 0.5
            let cy = (det.boundingBox.midY / h) - 0.5
            let dist = sqrt(cx * cx + cy * cy)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }

    func zoomIn() -> Bool {
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = maxOpticalZoom
            device.unlockForConfiguration()
            lastRetryTime = Date()
            zoomRetryAttempts += 1
            return true
        } catch {
            DebugLog.shared.e("ZoomController", "Failed to zoom in: \(error.localizedDescription)")
            return false
        }
    }

    func restoreZoom() {
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = 1.0
            device.unlockForConfiguration()
        } catch {
            DebugLog.shared.e("ZoomController", "Failed to restore zoom: \(error.localizedDescription)")
        }
    }

    func recordSuccess() {
        zoomRetrySuccesses += 1
    }
}
