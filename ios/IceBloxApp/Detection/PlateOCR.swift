import Foundation
import Accelerate
import onnxruntime

enum PlateOCR {
    private static let targetHeight = 48
    private static let targetWidth = 320

    // PP-OCRv3 en_dict.txt character order (NOT ASCII order).
    // Index 0 = CTC blank; indices 1..95 map to characters in this string.
    // Index 96 = unknown/padding (ignored).
    // Order: space, 0-9, :-~, !-/
    private static let dictionary: [Character] = Array(
        " 0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~!\"#$%&'()*+,-./"
    )

    private static let env: ORTEnv? = {
        try? ORTEnv(loggingLevel: .warning)
    }()

    private static let session: ORTSession? = {
        guard let env else {
            DebugLog.shared.e("PlateOCR", "Failed to create ONNX Runtime environment")
            return nil
        }
        guard let modelPath = Bundle.main.path(forResource: "plate_ocr", ofType: "onnx") else {
            DebugLog.shared.e("PlateOCR", "plate_ocr.onnx not found in bundle")
            return nil
        }
        do {
            let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: nil)
            DebugLog.shared.d("PlateOCR", "ONNX Runtime OCR model loaded")
            return session
        } catch {
            DebugLog.shared.e("PlateOCR", "OCR model init failed: \(error.localizedDescription)")
            return nil
        }
    }()

    private static let inputName: String = {
        guard let session else { return "x" }
        return (try? session.inputNames().first) ?? "x"
    }()

    static func recognizeText(in pixelBuffer: CVPixelBuffer) -> String? {
        guard let session else { return nil }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard srcWidth > 0, srcHeight > 0 else { return nil }

        var inputData = preprocessImage(pixelBuffer, srcWidth: srcWidth, srcHeight: srcHeight)

        do {
            let inputShape: [NSNumber] = [1, 3, NSNumber(value: targetHeight), NSNumber(value: targetWidth)]
            let data = NSMutableData(
                bytes: &inputData,
                length: inputData.count * MemoryLayout<Float>.size
            )
            let inputTensor = try ORTValue(
                tensorData: data,
                elementType: .float,
                shape: inputShape
            )

            let outputNames = try session.outputNames()
            let outputs = try session.run(
                withInputs: [inputName: inputTensor],
                outputNames: Set(outputNames),
                runOptions: nil
            )

            guard let outputTensor = outputs[outputNames[0]] else { return nil }
            let outputData = try outputTensor.tensorData()
            let shapeInfo = try outputTensor.tensorTypeAndShapeInfo()

            return ctcDecode(data: outputData as Data, shape: shapeInfo.shape)
        } catch {
            DebugLog.shared.w("PlateOCR", "OCR failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func preprocessImage(
        _ pixelBuffer: CVPixelBuffer,
        srcWidth: Int,
        srcHeight: Int
    ) -> [Float] {
        let scale = Float(targetHeight) / Float(srcHeight)
        let scaledWidth = min(Int(Float(srcWidth) * scale), targetWidth)

        let hw = targetHeight * targetWidth
        var data = [Float](repeating: -1.0, count: 3 * hw)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return data }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

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

                let idx = y * targetWidth + x
                data[0 * hw + idx] = (r / 255.0 - 0.5) / 0.5
                data[1 * hw + idx] = (g / 255.0 - 0.5) / 0.5
                data[2 * hw + idx] = (b / 255.0 - 0.5) / 0.5
            }
        }

        return data
    }

    private static func ctcDecode(data: Data, shape: [NSNumber]) -> String? {
        let seqLen: Int
        let numClasses: Int

        if shape.count == 3 {
            seqLen = shape[1].intValue
            numClasses = shape[2].intValue
        } else if shape.count == 2 {
            seqLen = shape[0].intValue
            numClasses = shape[1].intValue
        } else {
            return nil
        }

        var decoded: [Character] = []
        var totalConfidence: Float = 0
        var prevIndex = -1

        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let floatPtr = ptr.bindMemory(to: Float.self)

            for t in 0..<seqLen {
                let base = t * numClasses

                var maxIdx = 0
                var maxVal = floatPtr[base]
                for c in 1..<numClasses {
                    let val = floatPtr[base + c]
                    if val > maxVal {
                        maxVal = val
                        maxIdx = c
                    }
                }

                // Skip blank (index 0) and collapse consecutive duplicates
                if maxIdx != 0 && maxIdx != prevIndex {
                    // Model outputs softmax probabilities — use max value directly
                    let charIdx = maxIdx - 1
                    if charIdx < dictionary.count {
                        decoded.append(dictionary[charIdx])
                        totalConfidence += maxVal
                    }
                }
                prevIndex = maxIdx
            }
        }

        guard !decoded.isEmpty else { return nil }

        let avgConfidence = totalConfidence / Float(decoded.count)
        guard avgConfidence >= AppConfig.ocrConfidenceThreshold else { return nil }

        return String(decoded)
    }
}
