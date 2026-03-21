import SwiftUI

struct SplashScreenView: View {
    let onStartCamera: () -> Void
    @State private var activeSheet: SheetType?
    @State private var e2eTriggerTask: Task<Void, Never>?
    @State private var offlineQueue = OfflineQueue()
    @State private var drainClient: APIClient?

    private enum SheetType: Identifiable {
        case report, map, settings, help, contact
        var id: Self { self }
    }

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

                Button { activeSheet = .map } label: {
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

                Button { activeSheet = .report } label: {
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

                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                    }
                    .accessibilityLabel("Help")

                    Button { activeSheet = .contact } label: {
                        Image(systemName: "bubble.left.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Contact")

                    Button { activeSheet = .settings } label: {
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
                activeSheet = .report
            }
            if AppConfig.autoShowSettings {
                activeSheet = .settings
            }
            if AppConfig.autoShowMap {
                activeSheet = .map
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
        #if APPSTORE_SCREENSHOTS
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .report:
                ReportICEView()
            case .map:
                MapView()
            case .settings:
                SettingsView()
            case .help:
                HelpView()
            case .contact:
                ContactView()
            }
        }
        #else
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .report:
                ReportICEView()
            case .map:
                MapView()
            case .settings:
                SettingsView()
            case .help:
                HelpView()
            case .contact:
                ContactView()
            }
        }
        #endif
    }
}
