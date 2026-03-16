import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        helpSection(
                            title: "Getting Started",
                            body: "Mount your phone on the dashboard with the camera facing forward."
                        )

                        helpSection(
                            title: "How It Works",
                            body: "IceBlox automatically scans license plates using your camera. If a match is found, nearby users are alerted via push notification."
                        )

                        helpSection(
                            title: "Push Notifications",
                            body: "Notifications are enabled by default. You can toggle them in Settings."
                        )

                        helpSection(
                            title: "Privacy",
                            body: "All plate data is hashed on-device before being sent to the server. No raw plate numbers leave your phone."
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func helpSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(body)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
