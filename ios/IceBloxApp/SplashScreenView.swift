import SwiftUI

struct SplashScreenView: View {
    let onStartCamera: () -> Void
    @State private var showReportSheet = false
    @State private var e2eTriggerTask: Task<Void, Never>?
    @State private var offlineQueue = OfflineQueue()
    @State private var queueCount = 0
    @State private var drainClient: APIClient?

    let queueTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("IceBlox")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                Button(action: onStartCamera) {
                    Text("Start Camera")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button { showReportSheet = true } label: {
                    Text("Report ICE Vehicle")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if queueCount > 0 {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Text("\(queueCount) uploads queued")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.yellow)
                        Button {
                            drainClient?.stopBatchTimer()
                            drainClient = nil
                            offlineQueue.clearAll()
                            queueCount = 0
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 48)
                }
            }
        }
        .onReceive(queueTimer) { _ in
            queueCount = offlineQueue.count
        }
        .onAppear {
            queueCount = offlineQueue.count
            if queueCount > 0 {
                let client = APIClient(offlineQueue: offlineQueue, currentSessionID: "")
                client.startBatchTimer()
                drainClient = client
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
    }
}
