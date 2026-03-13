import SwiftUI

struct StatusBarView: View {
    let isConnected: Bool
    let lastDetection: Date?
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
                    .foregroundStyle(isConnected ? .green : .red)
                    .accessibilityIdentifier("status_text")
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
            Spacer()
            Text("Last: \(lastDetectionText)")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
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
