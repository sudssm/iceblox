import SwiftUI

struct SplashScreenView: View {
    let onStartCamera: () -> Void
    @State private var showReportSheet = false
    @State private var showMapSheet = false
    @State private var showSettingsSheet = false
    @State private var e2eTriggerTask: Task<Void, Never>?
    @State private var offlineQueue = OfflineQueue()
    @State private var drainClient: APIClient?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("IceBlox")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                let buttonMinWidth: CGFloat = 260

                Button(action: onStartCamera) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .frame(width: 28)
                        Text("Start Camera")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .foregroundStyle(.white)
                    .frame(width: buttonMinWidth)
                    .padding(.vertical, 14)
                    .background(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button { showMapSheet = true } label: {
                    HStack {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .frame(width: 28)
                        Text("View Map")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .foregroundStyle(.black)
                    .frame(width: buttonMinWidth)
                    .padding(.vertical, 14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button { showSettingsSheet = true } label: {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .frame(width: buttonMinWidth)
                        .padding(.vertical, 14)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Settings")

                Button { showReportSheet = true } label: {
                    HStack {
                        Image(systemName: "megaphone.fill")
                            .font(.title2)
                            .frame(width: 28)
                        Text("Report ICE Activity")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .foregroundStyle(.white)
                    .frame(width: buttonMinWidth)
                    .padding(.vertical, 14)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear {
            if !offlineQueue.isEmpty {
                let client = APIClient(offlineQueue: offlineQueue, currentSessionID: "")
                client.startBatchTimer()
                drainClient = client
            }
            if AppConfig.autoShowReport {
                showReportSheet = true
            }
            if AppConfig.autoShowSettings {
                showSettingsSheet = true
            }
            if AppConfig.autoShowMap {
                showMapSheet = true
            }
            guard AppConfig.useSplashTrigger else { return }

            e2eTriggerTask?.cancel()
            e2eTriggerTask = Task {
                while !Task.isCancelled {
                    if let triggerURL = AppConfig.splashTriggerURL,
                       FileManager.default.fileExists(atPath: triggerURL.path) {
                        try? FileManager.default.removeItem(at: triggerURL)
                        await MainActor.run {
                            onStartCamera()
                        }
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
        .onDisappear {
            drainClient?.stopBatchTimer()
            drainClient = nil
            e2eTriggerTask?.cancel()
            e2eTriggerTask = nil
        }
        .sheet(isPresented: $showReportSheet) {
            ReportICEView()
        }
        .sheet(isPresented: $showMapSheet) {
            MapView()
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
        }
    }
}
