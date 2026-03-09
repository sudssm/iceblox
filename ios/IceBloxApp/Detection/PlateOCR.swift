import CoreML
import Accelerate

enum PlateOCR {
    private static let targetHeight = 48
    private static let targetWidth = 320

    // PP-OCRv3 en_dict.txt: 95 printable ASCII characters (space through tilde).
    // Index 0 = CTC blank; indices 1..N map to this array.
    private static let dictionary: [Character] = {
        (32...126).map { Character(UnicodeScalar($0)) }
    }()

    private static let model: MLModel? = {
        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly
        #else
        config.computeUnits = .all
        #endif
        do {
            let model = try plate_ocr(configuration: config).model
            DebugLog.shared.d("PlateOCR", "CoreML OCR model loaded")
            return model
        } catch {
            DebugLog.shared.e("PlateOCR", "Failed to load OCR model: \(error.localizedDescription)")
            return nil
        }
    }()

    private static let inputName: String = {
        guard let model else { return "x" }
        return model.modelDescription.inputDescriptionsByName.keys.first ?? "x"
    }()

    static func recognizeText(in pixelBuffer: CVPixelBuffer) -> String? {
        guard let model else { return nil }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard srcWidth > 0, srcHeight > 0 else { return nil }

        guard let input = preprocessImage(pixelBuffer, srcWidth: srcWidth, srcHeight: srcHeight) else {
            return nil
        }

        guard let features = try? MLDictionaryFeatureProvider(dictionary: [inputName: input]),
              let prediction = try? model.prediction(from: features) else {
            return nil
        }

        guard let outputName = prediction.featureNames.first,
              let logits = prediction.featureValue(for: outputName)?.multiArrayValue else {
            return nil
        }

        return ctcDecode(logits: logits)
    }

    private static func preprocessImage(
        _ pixelBuffer: CVPixelBuffer,
        srcWidth: Int,
        srcHeight: Int
    ) -> MLMultiArray? {
        guard let input = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: targetHeight), NSNumber(value: targetWidth)],
            dataType: .float32
        ) else { return nil }

        let scale = Float(targetHeight) / Float(srcHeight)
        let scaledWidth = min(Int(Float(srcWidth) * scale), targetWidth)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let ptr = input.dataPointer.bindMemory(
            to: Float.self,
            capacity: 3 * targetHeight * targetWidth
        )

        // Fill with -1.0 (normalized black: (0/255 - 0.5)/0.5 = -1)
        let count = 3 * targetHeight * targetWidth
        var fillValue: Float = -1.0
        vDSP_vfill(&fillValue, ptr, 1, vDSP_Length(count))

        // Nearest-neighbor resize + normalize into CHW layout
        let hw = targetHeight * targetWidth
        for y in 0..<targetHeight {
            let srcY = min(Int(Float(y) / scale), srcHeight - 1)
            let rowPtr = baseAddress.advanced(by: srcY * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)

            for x in 0..<scaledWidth {
                let srcX = min(Int(Float(x) / scale), srcWidth - 1)
                let pixelOffset = srcX * 4

                // BGRA pixel format
                let b = Float(rowPtr[pixelOffset])
                let g = Float(rowPtr[pixelOffset + 1])
                let r = Float(rowPtr[pixelOffset + 2])

                // Normalize: (pixel / 255.0 - 0.5) / 0.5
                ptr[0 * hw + y * targetWidth + x] = (r / 255.0 - 0.5) / 0.5
                ptr[1 * hw + y * targetWidth + x] = (g / 255.0 - 0.5) / 0.5
                ptr[2 * hw + y * targetWidth + x] = (b / 255.0 - 0.5) / 0.5
            }
        }

        return input
    }

    private static func ctcDecode(logits: MLMultiArray) -> String? {
        let shape = logits.shape.map { $0.intValue }
        let seqLen: Int
        let numClasses: Int

        if shape.count == 3 {
            seqLen = shape[1]
            numClasses = shape[2]
        } else if shape.count == 2 {
            seqLen = shape[0]
            numClasses = shape[1]
        } else {
            return nil
        }

        let totalElements = shape.count == 3 ? shape[0] * seqLen * numClasses : seqLen * numClasses
        let ptr = logits.dataPointer.bindMemory(to: Float.self, capacity: totalElements)

        var decoded: [Character] = []
        var totalConfidence: Float = 0
        var prevIndex = -1

        for t in 0..<seqLen {
            let base = t * numClasses

            // Argmax + track max value for softmax
            var maxIdx = 0
            var maxVal: Float = ptr[base]
            for c in 1..<numClasses {
                let val = ptr[base + c]
                if val > maxVal {
                    maxVal = val
                    maxIdx = c
                }
            }

            // Skip blank (index 0) and collapse consecutive duplicates
            if maxIdx != 0 && maxIdx != prevIndex {
                // Softmax probability of the winning class
                var sumExp: Float = 0
                for c in 0..<numClasses {
                    sumExp += exp(ptr[base + c] - maxVal)
                }
                let prob = 1.0 / sumExp

                let charIdx = maxIdx - 1
                if charIdx < dictionary.count {
                    decoded.append(dictionary[charIdx])
                    totalConfidence += prob
                }
            }
            prevIndex = maxIdx
        }

        guard !decoded.isEmpty else { return nil }

        let avgConfidence = totalConfidence / Float(decoded.count)
        guard avgConfidence >= AppConfig.ocrConfidenceThreshold else { return nil }

        return String(decoded)
    }
}
