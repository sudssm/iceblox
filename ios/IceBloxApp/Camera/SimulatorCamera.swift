#if targetEnvironment(simulator)
import CoreVideo
import Foundation
import UIKit

final class SimulatorCamera {
    private struct Frame {
        let image: UIImage
        let pixelBuffer: CVPixelBuffer
        let expectedPlate: String?
        let sourceName: String
    }

    private struct LoadedFrames {
        let frames: [Frame]
        let signature: String
    }

    let previewImage: UIImage
    var onPreviewImageChange: ((UIImage) -> Void)?

    private var frames: [Frame]
    private var frameSignature: String
    private var timer: DispatchSourceTimer?
    private let frameQueue = DispatchQueue(label: "simulator.camera.frames")
    private var currentFrameIndex = 0
    private var lastReloadCheck = Date.distantPast
    weak var frameProcessor: FrameProcessor?

    init() {
        let loadedFrames = SimulatorCamera.loadFrames()
        frames = loadedFrames.frames
        frameSignature = loadedFrames.signature
        DebugLog.shared.d("SimulatorCamera", "Initial frame source: \(frameSignature)")
        if let firstFrame = frames.first {
            previewImage = firstFrame.image
        } else {
            let placeholder = SimulatorCamera.generatePlaceholder()
            previewImage = placeholder
        }
    }

    func start() {
        guard timer == nil, !frames.isEmpty else { return }
        currentFrameIndex = 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onPreviewImageChange?(self.frames[self.currentFrameIndex].image)
        }
        let source = DispatchSource.makeTimerSource(queue: frameQueue)
        source.schedule(deadline: .now(), repeating: .milliseconds(AppConfig.simulatorFrameIntervalMilliseconds))
        source.setEventHandler { [weak self] in
            self?.emitCurrentFrame()
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func emitCurrentFrame() {
        reloadFramesIfNeeded()
        guard !frames.isEmpty else { return }
        if currentFrameIndex >= frames.count {
            currentFrameIndex = 0
        }

        let frame = frames[currentFrameIndex]
        if let expectedPlate = frame.expectedPlate {
            DebugLog.shared.d("SimulatorCamera", "Injecting plate override \(expectedPlate) for \(frame.sourceName)")
            frameProcessor?.processSimulatedPlate(
                expectedPlate,
                imageWidth: Int(frame.image.size.width),
                imageHeight: Int(frame.image.size.height)
            )
        } else {
            frameProcessor?.processFrame(frame.pixelBuffer, skipCount: 0)
        }

        if frames.count > 1 {
            currentFrameIndex = (currentFrameIndex + 1) % frames.count
            let nextImage = frames[currentFrameIndex].image
            DispatchQueue.main.async { [weak self] in
                self?.onPreviewImageChange?(nextImage)
            }
        }
    }

    private func reloadFramesIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastReloadCheck) >= 0.5 else { return }
        lastReloadCheck = now

        let loadedFrames = SimulatorCamera.loadFrames()
        guard loadedFrames.signature != frameSignature else { return }

        frames = loadedFrames.frames
        frameSignature = loadedFrames.signature
        currentFrameIndex = 0

        if let image = frames.first?.image {
            DispatchQueue.main.async { [weak self] in
                self?.onPreviewImageChange?(image)
            }
        }

        DebugLog.shared.d("SimulatorCamera", "Reloaded frame source: \(frameSignature)")
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
                .foregroundColor: UIColor.white.withAlphaComponent(0.3)
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

    private static func loadFrames() -> LoadedFrames {
        let runtimeImages = runtimeImageURLs()
        if !runtimeImages.isEmpty {
            let frames = runtimeImages.compactMap { imageURL -> Frame? in
                guard let image = UIImage(contentsOfFile: imageURL.path),
                      let pixelBuffer = createPixelBuffer(from: image) else {
                    DebugLog.shared.w("SimulatorCamera", "Skipping unreadable image at \(imageURL.lastPathComponent)")
                    return nil
                }
                return Frame(
                    image: image,
                    pixelBuffer: pixelBuffer,
                    expectedPlate: plateOverride(for: imageURL),
                    sourceName: imageURL.lastPathComponent
                )
            }

            if !frames.isEmpty {
                let signature = frames.map { "\($0.sourceName):\($0.expectedPlate ?? "-")" }.joined(separator: "|")
                return LoadedFrames(frames: frames, signature: "runtime:\(signature)")
            }
        }

        if let bundled = UIImage(named: "simulator_frame"),
           let pixelBuffer = createPixelBuffer(from: bundled) {
            return LoadedFrames(
                frames: [Frame(
                    image: bundled,
                    pixelBuffer: pixelBuffer,
                    expectedPlate: nil,
                    sourceName: "simulator_frame"
                )],
                signature: "bundled:simulator_frame"
            )
        }

        let placeholder = generatePlaceholder()
        guard let pixelBuffer = createPixelBuffer(from: placeholder) else {
            return LoadedFrames(frames: [], signature: "placeholder:empty")
        }
        return LoadedFrames(
            frames: [Frame(
                image: placeholder,
                pixelBuffer: pixelBuffer,
                expectedPlate: nil,
                sourceName: "placeholder"
            )],
            signature: "placeholder"
        )
    }

    private static func runtimeImageURLs() -> [URL] {
        let fm = FileManager.default
        let candidateDirectories = [
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent(AppConfig.simulatorTestImagesDirectoryName, isDirectory: true),
            fm.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent(AppConfig.simulatorTestImagesDirectoryName, isDirectory: true)
        ].compactMap { $0 }

        let supportedExtensions = Set(["png", "jpg", "jpeg", "bmp"])
        var urls: [URL] = []

        for directory in candidateDirectories {
            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            urls.append(contentsOf: contents.filter {
                supportedExtensions.contains($0.pathExtension.lowercased())
            })
        }

        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func plateOverride(for imageURL: URL) -> String? {
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("txt")
        guard let contents = try? String(contentsOf: sidecarURL, encoding: .utf8) else {
            return nil
        }
        let plate = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return plate.isEmpty ? nil : plate
    }
}
#endif
