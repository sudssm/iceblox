import CoreVideo
import Foundation
import OnnxRuntimeBindings

enum PlateOCR {
    private static let targetHeight = 64
    private static let targetWidth = 128
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_")
    private static let padChar: Character = "_"

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
        guard let session else { return "input" }
        return (try? session.inputNames().first) ?? "input"
    }()

    static func recognizeText(in pixelBuffer: CVPixelBuffer) -> String? {
        guard let session else {
            DebugLog.shared.e("PlateOCR", "ONNX session is nil — model not loaded")
            return nil
        }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard srcWidth > 0, srcHeight > 0 else {
            DebugLog.shared.w("PlateOCR", "Invalid crop dimensions: \(srcWidth)x\(srcHeight)")
            return nil
        }
        DebugLog.shared.d("PlateOCR", "OCR input: \(srcWidth)x\(srcHeight)")

        guard let inputData = preprocessImage(pixelBuffer, srcWidth: srcWidth, srcHeight: srcHeight) else {
            DebugLog.shared.w("PlateOCR", "Preprocessing failed")
            return nil
        }

        do {
            let inputShape: [NSNumber] = [1, NSNumber(value: targetHeight), NSNumber(value: targetWidth), 3]
            let data = NSMutableData(bytes: inputData, length: inputData.count)
            let inputTensor = try ORTValue(
                tensorData: data,
                elementType: .uInt8,
                shape: inputShape
            )

            let outputNames = try session.outputNames()
            let outputs = try session.run(
                withInputs: [inputName: inputTensor],
                outputNames: Set(outputNames),
                runOptions: nil
            )

            guard let outputTensor = outputs[outputNames[0]] else {
                DebugLog.shared.w("PlateOCR", "No output tensor from ONNX")
                return nil
            }
            let outputData = try outputTensor.tensorData()
            let shapeInfo = try outputTensor.tensorTypeAndShapeInfo()
            DebugLog.shared.d("PlateOCR", "ONNX output shape: \(shapeInfo.shape)")

            return fixedSlotDecode(data: outputData as Data, shape: shapeInfo.shape)
        } catch {
            DebugLog.shared.w("PlateOCR", "OCR failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func preprocessImage(
        _ pixelBuffer: CVPixelBuffer,
        srcWidth: Int,
        srcHeight: Int
    ) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Pack as HWC uint8 RGB, exact resize to 64x128
        let totalPixels = targetHeight * targetWidth
        var data = [UInt8](repeating: 0, count: totalPixels * 3)

        for y in 0..<targetHeight {
            let srcY = y * (srcHeight - 1) / max(targetHeight - 1, 1)
            let rowPtr = baseAddress.advanced(by: srcY * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)

            for x in 0..<targetWidth {
                let srcX = x * (srcWidth - 1) / max(targetWidth - 1, 1)
                let pixelOffset = srcX * 4

                // BGRA → RGB
                let blue = rowPtr[pixelOffset]
                let green = rowPtr[pixelOffset + 1]
                let red = rowPtr[pixelOffset + 2]

                let baseIdx = (y * targetWidth + x) * 3
                data[baseIdx]     = red
                data[baseIdx + 1] = green
                data[baseIdx + 2] = blue
            }
        }

        return data
    }

    private static func fixedSlotDecode(data: Data, shape: [NSNumber]) -> String? {
        let numSlots: Int
        let alphabetSize: Int

        if shape.count == 3 {
            numSlots = shape[1].intValue
            alphabetSize = shape[2].intValue
        } else if shape.count == 2 {
            numSlots = shape[0].intValue
            alphabetSize = shape[1].intValue
        } else {
            DebugLog.shared.w("PlateOCR", "Unexpected output shape rank: \(shape.count)")
            return nil
        }
        DebugLog.shared.d("PlateOCR", "Decode: numSlots=\(numSlots) alphabetSize=\(alphabetSize)")

        var decoded: [Character] = []
        var totalConfidence: Float = 0

        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let floatPtr = ptr.bindMemory(to: Float.self)

            for slot in 0..<numSlots {
                let base = slot * alphabetSize

                var maxIdx = 0
                var maxVal = floatPtr[base]
                for ci in 1..<alphabetSize {
                    let val = floatPtr[base + ci]
                    if val > maxVal {
                        maxVal = val
                        maxIdx = ci
                    }
                }

                guard maxIdx < alphabet.count else { continue }
                let ch = alphabet[maxIdx]
                if ch != padChar {
                    decoded.append(ch)
                    totalConfidence += maxVal
                }
            }
        }

        guard !decoded.isEmpty else {
            DebugLog.shared.w("PlateOCR", "Decode produced no characters (all padding)")
            return nil
        }

        let avgConfidence = totalConfidence / Float(decoded.count)
        let text = String(decoded)
        DebugLog.shared.d("PlateOCR", "Decoded: '\(text)' avgConf=\(String(format: "%.3f", avgConfidence)) threshold=\(AppConfig.ocrConfidenceThreshold)")
        guard avgConfidence >= AppConfig.ocrConfidenceThreshold else {
            DebugLog.shared.w("PlateOCR", "REJECTED low confidence: '\(text)' \(String(format: "%.3f", avgConfidence)) < \(AppConfig.ocrConfidenceThreshold)")
            return nil
        }

        return text
    }
}
