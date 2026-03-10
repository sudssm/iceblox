import SwiftUI

struct DebugOverlayView: View {
    let detections: [FrameResult]
    let rawDetections: [RawDetectionBox]
    let feedEntries: [DetectionFeedEntry]
    let fps: Double
    let queueDepth: Int
    let isConnected: Bool
    let logEntries: [LogEntry]

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
                Text("Det: \(rawDetections.count)")
                    .foregroundStyle(.yellow)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)

            // Bounding boxes
            GeometryReader { geo in
                // Yellow boxes: raw detections (pre-OCR)
                ForEach(Array(rawDetections.enumerated()), id: \.offset) { _, raw in
                    let rect = raw.boundingBox
                    let scaleX = geo.size.width / CGFloat(raw.imageWidth)
                    let scaleY = geo.size.height / CGFloat(raw.imageHeight)

                    VStack(spacing: 2) {
                        Rectangle()
                            .stroke(.yellow, lineWidth: 2)
                            .frame(
                                width: rect.width * scaleX,
                                height: rect.height * scaleY
                            )

                        Text(String(format: "%.0f%%", raw.confidence * 100))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                    .position(
                        x: rect.midX * scaleX,
                        y: rect.midY * scaleY
                    )
                }

                // Green boxes: OCR'd plates
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
                        x: rect.midX * scaleX,
                        y: rect.midY * scaleY
                    )
                }
            }

            // Detection feed (right side)
            if !feedEntries.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(feedEntries) { entry in
                                    HStack(spacing: 6) {
                                        Text(entry.plateText)
                                        Text(entry.hashPrefix)
                                            .foregroundStyle(.white.opacity(0.6))
                                        Text(stateLabel(entry.state))
                                            .foregroundStyle(stateColor(entry.state))
                                    }
                                    .font(.system(.caption2, design: .monospaced))
                                }
                            }
                            .padding(8)
                        }
                        .frame(width: 200)
                        .frame(maxHeight: 300)
                        .background(.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 40)
                        .padding(.trailing, 8)
                    }
                    Spacer()
                }
            }

            VStack {
                Spacer()
                DebugLogPanel(entries: logEntries)
                    .padding(.horizontal, 8)
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

    private func stateLabel(_ state: DetectionState) -> String {
        switch state {
        case .queued: return "[QUED]"
        case .sent: return "[SENT]"
        case .matched: return "[MTCH]"
        }
    }

    private func stateColor(_ state: DetectionState) -> Color {
        switch state {
        case .queued: return .white
        case .sent: return .green
        case .matched: return Color(red: 1.0, green: 0.84, blue: 0.0)
        }
    }
}
