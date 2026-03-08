import SwiftUI

struct DebugLogPanel: View {
    let entries: [LogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        Text(formatEntry(entry))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(colorForLevel(entry.level))
                            .lineLimit(2)
                            .id(entry.id)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 140)
            .background(.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private func formatEntry(_ entry: LogEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let prefix: String
        switch entry.level {
        case .debug: prefix = "D"
        case .warning: prefix = "W"
        case .error: prefix = "E"
        }
        return "\(formatter.string(from: entry.timestamp)) \(prefix)/\(entry.tag): \(entry.message)"
    }
}
