import SwiftUI

struct DebugOverlayView: View {
    let detections: [FrameResult]
    let fps: Double
    let queueDepth: Int
    let isConnected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Debug header
            HStack(spacing: 16) {
                Text("FPS: \(Int(fps))")
                Text("Queue: \(queueDepth)")
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Online" : "Offline")
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)

            // Bounding boxes with labels
            GeometryReader { geo in
                ForEach(Array(detections.enumerated()), id: \.offset) { _, detection in
                    let rect = detection.boundingBox
                    let scaleX = geo.size.width / max(rect.maxX, geo.size.width)
                    let scaleY = geo.size.height / max(rect.maxY, geo.size.height)

                    VStack(spacing: 2) {
                        Text(detection.plateText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.green.opacity(0.7))

                        Rectangle()
                            .stroke(.green, lineWidth: 2)
                            .frame(
                                width: rect.width * scaleX,
                                height: rect.height * scaleY
                            )

                        Text(String(detection.hash.prefix(8)))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .position(
                        x: (rect.midX * scaleX),
                        y: (rect.midY * scaleY)
                    )
                }
            }

            // Debug mode label
            VStack {
                Spacer()
                HStack {
                    Text("[DEBUG MODE]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .padding(8)
                    Spacer()
                }
            }
        }
    }
}
