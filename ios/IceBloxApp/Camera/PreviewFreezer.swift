import AVFoundation
import UIKit

final class PreviewFreezer {
    private weak var parentView: UIView?
    private var frozenImageView: UIImageView?
    private var enhancingLabel: UIView?
    private let ciContext = CIContext()
    private(set) var isFrozen = false

    init(parentView: UIView) {
        self.parentView = parentView
    }

    func freeze(sampleBuffer: CMSampleBuffer, debugMode: Bool) {
        guard !isFrozen, let parentView else { return }

        if !debugMode {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.frame = parentView.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            if let image = imageFromSampleBuffer(sampleBuffer) {
                imageView.image = image
            }

            parentView.addSubview(imageView)
            frozenImageView = imageView
        }

        let label = makeEnhancingLabel()
        parentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: parentView.centerYAnchor)
        ])
        enhancingLabel = label

        isFrozen = true
    }

    func unfreeze() {
        frozenImageView?.removeFromSuperview()
        frozenImageView = nil
        enhancingLabel?.removeFromSuperview()
        enhancingLabel = nil
        isFrozen = false
    }

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func makeEnhancingLabel() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        container.layer.cornerRadius = 8

        let label = UILabel()
        label.text = "Enhancing..."
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }
}
