import SwiftUI

struct StatusBarView: View {
    let isConnected: Bool
    let lastDetection: Date?
    let plateCount: Int
    let targetCount: Int
    let hasGPS: Bool

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(isConnected ? "Online" : "Offline")
            }
            Text("Last: \(lastDetectionText)")
            Text("Plates: \(plateCount)")
            Text("Targets: \(targetCount)")
            if !hasGPS {
                Text("No GPS")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6))
    }

    private var lastDetectionText: String {
        guard let last = lastDetection else { return "--" }
        let seconds = Int(Date().timeIntervalSince(last))
        if seconds < 60 {
            return "\(seconds)s ago"
        }
        return "\(seconds / 60)m ago"
    }
}
