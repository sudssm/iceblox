import XCTest
@testable import IceBloxApp

final class FrameDifferTests: XCTestCase {

    func testFirstFrameReturnsTrue() {
        let differ = FrameDiffer()
        let buffer = makePixelBuffer(gray: 128)
        XCTAssertTrue(differ.shouldProcess(pixelBuffer: buffer))
    }

    func testIdenticalFramesReturnsFalse() {
        let differ = FrameDiffer()
        let buffer1 = makePixelBuffer(gray: 128)
        let buffer2 = makePixelBuffer(gray: 128)

        _ = differ.shouldProcess(pixelBuffer: buffer1)
        XCTAssertFalse(differ.shouldProcess(pixelBuffer: buffer2))
    }

    func testDifferentFramesReturnsTrue() {
        let differ = FrameDiffer()
        let buffer1 = makePixelBuffer(gray: 0)
        let buffer2 = makePixelBuffer(gray: 255)

        _ = differ.shouldProcess(pixelBuffer: buffer1)
        XCTAssertTrue(differ.shouldProcess(pixelBuffer: buffer2))
    }

    func testResetClearsPreviousThumbnail() {
        let differ = FrameDiffer()
        let buffer1 = makePixelBuffer(gray: 128)
        let buffer2 = makePixelBuffer(gray: 128)

        _ = differ.shouldProcess(pixelBuffer: buffer1)
        differ.reset()
        XCTAssertTrue(differ.shouldProcess(pixelBuffer: buffer2))
    }

    func testCounterIncrementsOnSkip() {
        let differ = FrameDiffer()
        let buffer1 = makePixelBuffer(gray: 128)
        let buffer2 = makePixelBuffer(gray: 128)
        let buffer3 = makePixelBuffer(gray: 128)

        _ = differ.shouldProcess(pixelBuffer: buffer1)
        _ = differ.shouldProcess(pixelBuffer: buffer2)
        _ = differ.shouldProcess(pixelBuffer: buffer3)

        XCTAssertEqual(differ.framesSkippedByDiff, 2)
    }

    func testMeanAbsoluteDifferenceWithIdenticalArrays() {
        let differ = FrameDiffer()
        let a: [UInt8] = [100, 150, 200]
        let b: [UInt8] = [100, 150, 200]
        XCTAssertEqual(differ.meanAbsoluteDifference(a: a, b: b), 0.0, accuracy: 0.001)
    }

    func testMeanAbsoluteDifferenceWithDifferentArrays() {
        let differ = FrameDiffer()
        let a: [UInt8] = [0, 0, 0]
        let b: [UInt8] = [30, 60, 90]
        XCTAssertEqual(differ.meanAbsoluteDifference(a: a, b: b), 60.0, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makePixelBuffer(gray: UInt8) -> CVPixelBuffer {
        let width = 128
        let height = 128
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard let buffer = pixelBuffer else {
            fatalError("Failed to create CVPixelBuffer for test")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            fatalError("Failed to get base address for test CVPixelBuffer")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                ptr[offset] = gray     // B
                ptr[offset + 1] = gray // G
                ptr[offset + 2] = gray // R
                ptr[offset + 3] = 255  // A
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }
}
