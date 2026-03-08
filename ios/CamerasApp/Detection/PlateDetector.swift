import CoreML
import os.log
import Vision
import CoreImage

struct DetectedPlate {
    let boundingBox: CGRect
    let confidence: Float
    let pixelBuffer: CVPixelBuffer
}

final class PlateDetector {
    private static let logger = Logger(subsystem: "com.cameras.app", category: "PlateDetector")
    private var visionModel: VNCoreMLModel?
    private let detectionQueue = DispatchQueue(label: "detection.inference")

    func loadModel() {
        do {
            let config = MLModelConfiguration()
            #if targetEnvironment(simulator)
            config.computeUnits = .cpuOnly
            #else
            config.computeUnits = .all
            #endif
            let model = try plate_detector(configuration: config).model
            visionModel = try VNCoreMLModel(for: model)
            DebugLog.shared.d("PlateDetector", "Model loaded successfully")
        } catch {
            DebugLog.shared.e("PlateDetector", "Failed to load plate detection model: \(error.localizedDescription)")
        }
    }

    func detect(pixelBuffer: CVPixelBuffer) -> [DetectedPlate] {
        guard let visionModel else { return [] }

        var results: [DetectedPlate] = []
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        for observation in observations {
            guard observation.confidence >= AppConfig.detectionConfidenceThreshold else { continue }

            // Convert Vision coordinates (bottom-left origin, normalized) to pixel coordinates
            let box = observation.boundingBox
            let pixelRect = CGRect(
                x: box.origin.x * imageWidth,
                y: (1 - box.origin.y - box.height) * imageHeight,
                width: box.width * imageWidth,
                height: box.height * imageHeight
            )

            results.append(DetectedPlate(
                boundingBox: pixelRect,
                confidence: observation.confidence,
                pixelBuffer: pixelBuffer
            ))
        }

        return results
    }

    static func cropPlateRegion(from pixelBuffer: CVPixelBuffer, rect: CGRect) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: rect)
        let context = CIContext()

        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 0, height > 0 else { return nil }

        var cropped: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &cropped)

        guard let output = cropped else { return nil }
        context.render(ciImage, to: output)
        return output
    }
}
