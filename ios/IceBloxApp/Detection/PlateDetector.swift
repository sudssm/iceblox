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
    private static let logger = Logger(subsystem: "com.iceblox.app", category: "PlateDetector")
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
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 0, height > 0 else { return nil }

        // Convert from top-left origin (UIKit) to bottom-left origin (CIImage)
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let ciRect = CGRect(
            x: rect.origin.x,
            y: imageHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        // Crop and translate to origin so it aligns with the output buffer at (0,0)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: ciRect)
            .transformed(by: CGAffineTransform(translationX: -ciRect.origin.x, y: -ciRect.origin.y))

        var cropped: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &cropped)

        guard let output = cropped else { return nil }
        let context = CIContext()
        context.render(ciImage, to: output)
        return output
    }
}
