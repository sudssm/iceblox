import Accelerate
import CoreVideo
import Foundation

final class FrameDiffer {
    private static let thumbnailSize = 64
    private static let pixelCount = thumbnailSize * thumbnailSize

    private var previousThumbnail: [UInt8]?
    private(set) var framesSkippedByDiff = 0

    func shouldProcess(pixelBuffer: CVPixelBuffer) -> Bool {
        let current = downsampleToGrayscale(pixelBuffer: pixelBuffer)

        guard let previous = previousThumbnail else {
            previousThumbnail = current
            return true
        }

        let diff = meanAbsoluteDifference(lhs: previous, rhs: current)
        previousThumbnail = current

        if diff >= AppConfig.frameDiffThreshold {
            return true
        }

        framesSkippedByDiff += 1
        return false
    }

    func reset() {
        previousThumbnail = nil
    }

    func downsampleToGrayscale(pixelBuffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return [UInt8](repeating: 0, count: Self.pixelCount)
        }

        var sourceBuffer = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )

        let thumbSize = Self.thumbnailSize
        var scaledData = [UInt8](repeating: 0, count: thumbSize * thumbSize * 4)
        var destBuffer = vImage_Buffer(
            data: &scaledData,
            height: vImagePixelCount(thumbSize),
            width: vImagePixelCount(thumbSize),
            rowBytes: thumbSize * 4
        )

        vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageNoFlags))

        var grayscale = [UInt8](repeating: 0, count: Self.pixelCount)
        for i in 0..<Self.pixelCount {
            let offset = i * 4
            let blue = Float(scaledData[offset])
            let green = Float(scaledData[offset + 1])
            let red = Float(scaledData[offset + 2])
            let lum = 0.299 * red + 0.587 * green + 0.114 * blue
            grayscale[i] = UInt8(min(255, max(0, lum)))
        }

        return grayscale
    }

    func meanAbsoluteDifference(lhs: [UInt8], rhs: [UInt8]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var sum: Int = 0
        for i in 0..<lhs.count {
            sum += abs(Int(lhs[i]) - Int(rhs[i]))
        }
        return Float(sum) / Float(lhs.count)
    }
}
