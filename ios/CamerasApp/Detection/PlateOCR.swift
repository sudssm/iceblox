import Vision

enum PlateOCR {
    static func recognizeText(in pixelBuffer: CVPixelBuffer) -> String? {
        var recognizedText: String?

        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  let topCandidate = observations.first?.topCandidates(1).first else {
                return
            }
            guard topCandidate.confidence >= AppConfig.ocrConfidenceThreshold else { return }
            recognizedText = topCandidate.string
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])

        return recognizedText
    }
}
