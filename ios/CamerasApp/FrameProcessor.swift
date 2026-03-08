import CoreVideo

struct ProcessedPlate {
    let normalizedText: String
    let boundingBox: CGRect
    let confidence: Float
}

final class FrameProcessor {
    private let detector = PlateDetector()
    private let ocr = PlateOCR()

    func process(pixelBuffer: CVPixelBuffer) -> [ProcessedPlate] {
        let detections = detector.detect(in: pixelBuffer)

        var plates: [ProcessedPlate] = []
        for detection in detections {
            guard let ocrResult = ocr.recognizeText(in: pixelBuffer, region: detection.boundingBox),
                  let normalized = PlateNormalizer.normalize(ocrResult.text) else {
                continue
            }
            plates.append(ProcessedPlate(
                normalizedText: normalized,
                boundingBox: detection.boundingBox,
                confidence: detection.confidence
            ))
        }
        return plates
    }
}
