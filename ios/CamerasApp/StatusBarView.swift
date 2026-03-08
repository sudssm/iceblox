import SwiftUI

struct StatusBarView: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Online")
            }
            Text("Last: --")
            Text("Plates: 0")
            Text("Targets: 0")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6))
    }
}
