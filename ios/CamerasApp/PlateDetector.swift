import CoreML
import Vision

struct DetectedPlate {
    let boundingBox: CGRect
    let confidence: Float
}

final class PlateDetector {
    private var visionModel: VNCoreMLModel?
    private let confidenceThreshold: Float = 0.7

    init() {
        loadModel()
    }

    private func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "plate_detector", withExtension: "mlmodelc") else {
            print("[PlateDetector] Model not found in bundle — detection disabled")
            return
        }
        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            visionModel = try VNCoreMLModel(for: mlModel)
        } catch {
            print("[PlateDetector] Failed to load model: \(error)")
        }
    }

    func detect(in pixelBuffer: CVPixelBuffer) -> [DetectedPlate] {
        guard let visionModel else { return [] }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        return results
            .filter { $0.confidence >= confidenceThreshold }
            .map { observation in
                // Vision coordinates: normalized, bottom-left origin
                // Convert to pixel coordinates with top-left origin
                let bbox = observation.boundingBox
                let pixelRect = CGRect(
                    x: bbox.origin.x * imageWidth,
                    y: (1 - bbox.origin.y - bbox.height) * imageHeight,
                    width: bbox.width * imageWidth,
                    height: bbox.height * imageHeight
                )
                return DetectedPlate(boundingBox: pixelRect, confidence: observation.confidence)
            }
    }
}
