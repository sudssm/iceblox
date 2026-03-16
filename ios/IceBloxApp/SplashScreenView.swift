import SwiftUI

struct SplashScreenView: View {
    let onStartCamera: () -> Void
    @State private var showReportSheet = false
    @State private var showMapSheet = false
    @State private var showSettingsSheet = false
    @State private var showHelpSheet = false
    @State private var showContactSheet = false
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

            VStack {
                HStack(spacing: 16) {
                    Spacer()

                    Button { showHelpSheet = true } label: {
                        Text("?")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.yellow)
                    }
                    .accessibilityLabel("Help")

                    Button { showContactSheet = true } label: {
                        Image(systemName: "bubble.left.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Contact")

                    Button { showSettingsSheet = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Settings")
                }
                .padding(.horizontal, 20)
                .padding(.top, 48)

                Spacer()
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
        .sheet(isPresented: $showHelpSheet) {
            HelpView()
        }
        .sheet(isPresented: $showContactSheet) {
            ContactView()
        }
    }
}
