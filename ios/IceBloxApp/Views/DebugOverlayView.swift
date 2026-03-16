import SwiftUI

struct DebugOverlayView: View {
    let detections: [FrameResult]
    let rawDetections: [RawDetectionBox]
    let feedEntries: [DetectionFeedEntry]
    let fps: Double
    let queueDepth: Int
    let isConnected: Bool
    let logEntries: [LogEntry]
    var framesSkippedByDiff: Int = 0
    var showLogs: Bool = true

    private var screenSize: CGSize { UIScreen.main.bounds.size }

    private var topSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return 0 }
        return window.safeAreaInsets.top
    }

    private var bottomSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return 0 }
        return window.safeAreaInsets.bottom
    }

    var body: some View {
        ZStack {
            // Bounding boxes - yellow (raw detections)
            ForEach(Array(rawDetections.enumerated()), id: \.offset) { _, raw in
                let rect = raw.boundingBox
                let scaleX = screenSize.width / CGFloat(raw.imageWidth)
                let scaleY = screenSize.height / CGFloat(raw.imageHeight)

                VStack(spacing: 2) {
                    Rectangle()
                        .stroke(.yellow, lineWidth: 2)
                        .frame(width: rect.width * scaleX, height: rect.height * scaleY)
                    Text(String(format: "%.0f%%", raw.confidence * 100))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
                .position(x: rect.midX * scaleX, y: rect.midY * scaleY)
            }

            // Bounding boxes - green (OCR'd plates)
            ForEach(Array(detections.enumerated()), id: \.offset) { _, detection in
                let rect = detection.boundingBox
                let scaleX = screenSize.width / max(rect.maxX, screenSize.width)
                let scaleY = screenSize.height / max(rect.maxY, screenSize.height)

                VStack(spacing: 2) {
                    Text(detection.plateText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.green.opacity(0.7))
                    Rectangle()
                        .stroke(.green, lineWidth: 2)
                        .frame(width: rect.width * scaleX, height: rect.height * scaleY)
                    Text(String(detection.hash.prefix(8)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .position(x: rect.midX * scaleX, y: rect.midY * scaleY)
            }

            // Debug header (top-left, below status bar + 40pt gap)
            debugHeader
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, topSafeArea + 40)
                .padding(.leading, 8)

            // Detection feed (top-right, same vertical offset as header)
            if !feedEntries.isEmpty {
                detectionFeed
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, topSafeArea + 40)
                    .padding(.trailing, 8)
                    .padding(.bottom, 40)
            }

            if showLogs {
                // Log panel (bottom-center)
                DebugLogPanel(entries: logEntries)
                    .frame(maxWidth: screenSize.width - 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 32)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    private var debugHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                Text("FPS: \(Int(fps))")
                Text("Queue: \(queueDepth)")
            }
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Online" : "Offline")
                }
                Text("Det: \(rawDetections.count)")
                    .foregroundStyle(.yellow)
                Text("Diff skip: \(framesSkippedByDiff)")
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var detectionFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Detection Feed")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
                ForEach(feedEntries) { entry in
                    HStack(spacing: 6) {
                        Text(entry.plateText)
                            .italic(entry.isExpanded)
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
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
