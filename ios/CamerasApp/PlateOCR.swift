import Vision
import CoreVideo

struct OCRResult {
    let text: String
    let confidence: Float
}

final class PlateOCR {
    private let confidenceThreshold: Float = 0.6

    func recognizeText(in pixelBuffer: CVPixelBuffer, region: CGRect) -> OCRResult? {
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Convert pixel rect (top-left origin) back to normalized Vision coordinates (bottom-left origin)
        let normalizedRegion = CGRect(
            x: region.origin.x / imageWidth,
            y: 1 - (region.origin.y + region.height) / imageHeight,
            width: region.width / imageWidth,
            height: region.height / imageHeight
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard !normalizedRegion.isEmpty else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.regionOfInterest = normalizedRegion

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results,
              let topCandidate = observations.first?.topCandidates(1).first,
              topCandidate.confidence >= confidenceThreshold else {
            return nil
        }

        return OCRResult(text: topCandidate.string, confidence: topCandidate.confidence)
    }
}
