import SwiftUI

struct StatusBarView: View {
    let isConnected: Bool
    let lastDetection: Date?
    let plateCount: Int
    let matchCount: Int
    let pendingCount: Int
    let hasGPS: Bool
    var nearbySightings: Int = 0

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                    .accessibilityIdentifier("status_indicator")
                Text(isConnected ? "Online" : "Offline")
                    .accessibilityIdentifier("status_text")
            }
            Text("Last: \(lastDetectionText)")
            Text("Plates: \(plateCount)")
                .accessibilityIdentifier("plate_count")
            Text("Matches: \(matchCount)")
                .accessibilityIdentifier("match_count")
            if pendingCount > 0 {
                Text("Pending: \(pendingCount)")
                    .foregroundStyle(.yellow)
                    .accessibilityIdentifier("pending_count")
            }
            if nearbySightings > 0 {
                Text("Nearby: \(nearbySightings)")
                    .foregroundStyle(.cyan)
            }
            if !hasGPS {
                Text("No GPS")
                    .foregroundStyle(Color(red: 1.0, green: 0.596, blue: 0.0))
                    .accessibilityIdentifier("gps_warning")
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6), ignoresSafeAreaEdges: .top)
        .accessibilityIdentifier("status_bar")
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
