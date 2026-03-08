#if targetEnvironment(simulator)
import CoreVideo
import Foundation
import UIKit

final class SimulatorCamera {
    let previewImage: UIImage
    private let pixelBuffer: CVPixelBuffer?
    private var timer: DispatchSourceTimer?
    private let frameQueue = DispatchQueue(label: "simulator.camera.frames")
    weak var frameProcessor: FrameProcessor?

    init() {
        if let bundled = UIImage(named: "simulator_frame") {
            previewImage = bundled
        } else {
            previewImage = SimulatorCamera.generatePlaceholder()
        }
        pixelBuffer = SimulatorCamera.createPixelBuffer(from: previewImage)
    }

    func start() {
        guard timer == nil, let pixelBuffer else { return }
        let source = DispatchSource.makeTimerSource(queue: frameQueue)
        source.schedule(deadline: .now(), repeating: .milliseconds(100))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.frameProcessor?.processFrame(pixelBuffer, skipCount: 0)
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private static func generatePlaceholder() -> UIImage {
        let size = CGSize(width: 1920, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let text = "SIMULATOR" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 80, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.3),
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
        }
    }

    private static func createPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = Int(image.size.width)
        let height = Int(image.size.height)

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let data = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixelBuffer
    }
}
#endif
