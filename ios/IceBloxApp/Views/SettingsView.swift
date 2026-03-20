import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        Toggle("Push Notifications", isOn: $settings.pushNotificationsEnabled)
                            .tint(.blue)
                    }
                    .listRowBackground(Color.white.opacity(0.1))

                    Section {
                        Toggle("Debug Mode", isOn: $settings.userDebug)
                            .tint(.blue)
                    } footer: {
                        Text("Shows detection bounding boxes on the camera preview")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                }
                .scrollContentBackground(.hidden)

                VStack {
                    Spacer()
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
