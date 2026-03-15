import SwiftUI
import UserNotifications

private struct SessionSummaryCard: View {
    let platesSeen: Int
    let iceVehicles: Int
    let durationText: String
    let pendingUploads: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Session Summary")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                Text("Plates seen: \(platesSeen)")
                if iceVehicles > 0 {
                    Text("ICE Vehicles Scanned: \(iceVehicles)")
                        .foregroundStyle(.orange)
                }
                Text("Duration: \(durationText)")
                if pendingUploads > 0 {
                    Text("Pending sync: \(pendingUploads) uploads")
                        .foregroundStyle(.yellow)
                    Text("ICE vehicles reflects confirmed matches received so far.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.black.opacity(0.9))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(24)
    }
}

struct ContentView: View {
    let onExitToSplash: () -> Void

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var connectivityMonitor = ConnectivityMonitor()
    @Environment(\.scenePhase) private var scenePhase

    @State private var offlineQueue = OfflineQueue()
    @State private var frameProcessor: FrameProcessor?
    @State private var apiClient: APIClient?
    @State private var alertClient: AlertClient?
    @State private var debugMode = AppConfig.forceDebugMode
    @ObservedObject private var debugLog = DebugLog.shared
    @ObservedObject private var userSettings = UserSettings.shared
    @State private var lastStatusUpdate = Date()
    @State private var sessionID = UUID().uuidString
    @State private var sessionStartedAt = Date()
    @State private var stopRequestedAt: Date?
    @State private var pendingSessionUploads = 0
    @State private var pendingSessionPlates = 0
    @State private var showingSummary = false
    @State private var debugMinimized = false
    @State private var e2eStopTask: Task<Void, Never>?
    @State private var brightnessManager = BrightnessManager()
    @StateObject private var motionStateManager = MotionStateManager()
    @State private var showingMotionPauseOverlay = false

    let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if showingSummary {
                Color.black.ignoresSafeArea()
            } else if cameraManager.permissionGranted {
                #if targetEnvironment(simulator)
                if let image = cameraManager.simulatorImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: UIScreen.main.bounds.height)
                        .clipped()
                        .ignoresSafeArea()
                }
                #else
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()

                if let fp = frameProcessor, fp.zoomRetryFrozen {
                    if !debugMode, let frozenImage = fp.frozenPreviewImage {
                        Image(uiImage: frozenImage)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    }

                    Text("Enhancing...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if debugMode {
                        Text("ZOOM RETRY")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .offset(y: 30)
                    }
                }
                #endif
            } else {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48))
                            if cameraManager.permissionDenied {
                                Text("Camera access denied")
                                    .font(.headline)
                                Text("Enable in Settings → IceBlox → Camera")
                                    .font(.subheadline)
                            } else {
                                Text("Requesting camera access…")
                                    .font(.headline)
                            }
                        }
                        .foregroundStyle(.white)
                    }
            }

            #if DEBUG
            if debugMode || userSettings.userDebugEnabled, !showingSummary, cameraManager.permissionGranted {
                DebugOverlayView(
                    detections: frameProcessor?.currentDetections ?? [],
                    rawDetections: frameProcessor?.rawDetections ?? [],
                    feedEntries: frameProcessor?.detectionFeed ?? [],
                    fps: frameProcessor?.fps ?? 0,
                    queueDepth: offlineQueue.count,
                    isConnected: connectivityMonitor.isConnected,
                    logEntries: debugLog.entries,
                    framesSkippedByDiff: frameProcessor?.framesSkippedByDiff ?? 0,
                    showFeedAndLogs: debugMode && !debugMinimized
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            if debugMode, !showingSummary, cameraManager.permissionGranted {
                Button {
                    debugMinimized.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text("[DEBUG]")
                            .font(.system(.caption, design: .monospaced))
                        Text(debugMinimized ? "+" : "\u{2212}")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 16)
                .padding(.bottom, 186)
            }
            #endif

            if !showingSummary, !showingMotionPauseOverlay, cameraManager.permissionGranted {
                VStack {
                    StatusBarView(
                        isConnected: connectivityMonitor.isConnected,
                        lastDetection: frameProcessor?.lastDetectionTime,
                        hasGPS: locationManager.hasPermission,
                        nearbySightings: alertClient?.nearbySightings ?? 0,
                        totalPlates: frameProcessor?.totalPlates ?? 0
                    )

                    Spacer()

                    Text("Leaving the app will pause scanning")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.bottom, 8)

                    Button(action: stopRecordingSession) {
                        Text("Stop Scanning")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.red.opacity(0.85))
                            .clipShape(Capsule())
                    }
                    .accessibilityIdentifier("stop_recording_button")
                    .padding(.bottom, 12)

                    #if DEBUG
                    if debugMode, !offlineQueue.isEmpty {
                        HStack(spacing: 8) {
                            Text("\(offlineQueue.count) uploads queued")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.yellow)
                            Button(action: clearUploadQueue) {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 4)
                    }
                    #endif
                }
            }

            if showingSummary {
                SessionSummaryCard(
                    platesSeen: frameProcessor?.totalPlates ?? 0,
                    iceVehicles: apiClient?.totalTargets ?? 0,
                    durationText: sessionDurationText,
                    pendingUploads: pendingSessionUploads,
                    onDone: returnToSplash
                )
            }

            if showingMotionPauseOverlay {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)

                    Text("Scanning Paused")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Waiting for motion to resume")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    Button(action: resumeFromMotionPause) {
                        Text("Resume Now")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
            }
        }
        #if DEBUG
        .onTapGesture(count: 3) {
            if !showingSummary {
                debugMode.toggle()
                frameProcessor?.debugMode = debugMode
                if debugMode {
                    brightnessManager.restore()
                } else {
                    brightnessManager.dim()
                }
            }
        }
        #endif
        .onTapGesture(count: 1) {
            if !debugMode, !showingSummary {
                brightnessManager.temporarilyRestore()
            }
        }
        .onReceive(statusTimer) { _ in
            lastStatusUpdate = Date()
            pendingSessionUploads = offlineQueue.count(sessionID: sessionID)
            pendingSessionPlates = offlineQueue.pendingPlateCount(sessionID: sessionID)
            if showingSummary {
                syncSessionSummaryArtifact()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            brightnessManager.dim()
            if apiClient == nil {
                sessionStartedAt = Date()
                stopRequestedAt = nil
                setupPipeline()
            }
            if !showingSummary {
                resumeActiveSession()
            }
            motionStateManager.startMonitoring()
            if AppConfig.requestLocationPermission {
                locationManager.requestPermission()
            }
            pendingSessionUploads = offlineQueue.count(sessionID: sessionID)
            pendingSessionPlates = offlineQueue.pendingPlateCount(sessionID: sessionID)
            clearSessionSummaryArtifact()
            startE2EStopWatcher()
        }
        .onDisappear {
            brightnessManager.teardown()
            UIApplication.shared.isIdleTimerDisabled = false
            motionStateManager.stopMonitoring()
            e2eStopTask?.cancel()
            e2eStopTask = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                brightnessManager.dim()
                if showingMotionPauseOverlay && !motionStateManager.isMotionPaused {
                    resumeFromMotionPause()
                } else if !showingMotionPauseOverlay && !showingSummary {
                    resumeActiveSession()
                }
            case .background:
                brightnessManager.restore()
                pauseForBackground()
            default:
                break
            }
        }
        .onChange(of: motionStateManager.isMotionPaused) { _, isPaused in
            if isPaused {
                pauseForMotion()
            } else if showingMotionPauseOverlay {
                resumeFromMotionPause()
            }
        }
        .onChange(of: showingSummary) { _, isShowing in
            if isShowing {
                syncSessionSummaryArtifact()
            } else {
                clearSessionSummaryArtifact()
            }
        }
    }
}

// MARK: - Private Helpers

extension ContentView {
    func setupPipeline() {
        let activeSessionID = sessionID
        let client = APIClient(offlineQueue: offlineQueue, currentSessionID: activeSessionID)
        let processor = FrameProcessor(
            offlineQueue: offlineQueue,
            locationManager: locationManager,
            apiClient: client,
            sessionID: activeSessionID
        )

        client.onPlateSent = { [weak processor] hash, matched, sentSessionID in
            guard sentSessionID == activeSessionID else { return }
            processor?.onPlateSent(hash: hash, matched: matched)
        }

        connectivityMonitor.onReconnect = { [weak client] in
            client?.flushQueue()
        }

        client.startSession(sessionID: activeSessionID)

        cameraManager.frameProcessor = processor
        self.frameProcessor = processor
        self.apiClient = client

        let alerts = AlertClient(locationManager: locationManager)
        self.alertClient = alerts
        alerts.startTimer()

        client.startBatchTimer()
    }

    func resumeActiveSession() {
        UIApplication.shared.isIdleTimerDisabled = true
        frameProcessor?.isAcceptingDetections = true
        if cameraManager.permissionGranted {
            cameraManager.start()
        } else {
            cameraManager.checkPermissionAndStart()
        }
        locationManager.startUpdatingLocation()
        apiClient?.startBatchTimer()
        alertClient?.startTimer()
    }

    func pauseForMotion() {
        showingMotionPauseOverlay = true
        frameProcessor?.isAcceptingDetections = false
        cameraManager.stop()
        locationManager.stopUpdatingLocation()
        apiClient?.flushQueue()
        apiClient?.stopBatchTimer()
        alertClient?.stopTimer()

        let content = UNMutableNotificationContent()
        content.title = "Scanning paused"
        content.body = "Stationary for too long. Tap to resume."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: "motion-pause", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func resumeFromMotionPause() {
        showingMotionPauseOverlay = false
        motionStateManager.manualResume()
        resumeActiveSession()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["motion-pause"])
    }

    func pauseForBackground() {
        frameProcessor?.isAcceptingDetections = false
        cameraManager.stop()
        apiClient?.flushQueue()
        apiClient?.stopBatchTimer()
        alertClient?.subscribe()
        alertClient?.stopTimer()

        if !showingSummary && !showingMotionPauseOverlay {
            let content = UNMutableNotificationContent()
            content.title = "Scanning paused"
            content.body = "Open IceBlox to resume"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: "background-pause", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func stopRecordingSession() {
        guard !showingSummary else { return }
        brightnessManager.teardown()
        showingMotionPauseOverlay = false
        motionStateManager.stopMonitoring()
        stopRequestedAt = Date()

        if let fp = frameProcessor {
            apiClient?.endSession(
                sessionID: sessionID,
                maxDetConf: fp.maxDetectionConfidence,
                totalDetConf: fp.totalDetectionConfidence,
                maxOCRConf: fp.maxOCRConfidence,
                totalOCRConf: fp.totalOCRConfidence
            )
        }

        frameProcessor?.isAcceptingDetections = false
        cameraManager.stop()
        apiClient?.stopBatchTimer()
        apiClient?.flushQueue()
        alertClient?.stopTimer()
        pendingSessionUploads = offlineQueue.count(sessionID: sessionID)
        showingSummary = true
    }

    func clearUploadQueue() {
        apiClient?.stopBatchTimer()
        offlineQueue.clearAll()
        pendingSessionUploads = 0
        apiClient?.startBatchTimer()
    }

    func returnToSplash() {
        showingSummary = false
        onExitToSplash()
    }

    func startE2EStopWatcher() {
        guard AppConfig.stopRecordingTriggerURL != nil else { return }

        e2eStopTask?.cancel()
        e2eStopTask = Task {
            while !Task.isCancelled {
                if let triggerURL = AppConfig.stopRecordingTriggerURL,
                   FileManager.default.fileExists(atPath: triggerURL.path) {
                    try? FileManager.default.removeItem(at: triggerURL)
                    await MainActor.run {
                        stopRecordingSession()
                    }
                }

                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func syncSessionSummaryArtifact() {
        guard showingSummary, let artifactURL = AppConfig.sessionSummaryArtifactURL else { return }

        let durationSeconds = max(0, Int((stopRequestedAt ?? Date()).timeIntervalSince(sessionStartedAt)))
        let payload = """
        session_id=\(sessionID)
        plates_seen=\(frameProcessor?.totalPlates ?? 0)
        ice_vehicles=\(apiClient?.totalTargets ?? 0)
        duration_seconds=\(durationSeconds)
        duration_text=\(sessionDurationText)
        pending_uploads=\(pendingSessionUploads)
        """

        try? FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? payload.write(to: artifactURL, atomically: true, encoding: .utf8)
    }

    func clearSessionSummaryArtifact() {
        guard let artifactURL = AppConfig.sessionSummaryArtifactURL else { return }
        try? FileManager.default.removeItem(at: artifactURL)
    }

    var sessionDurationText: String {
        let endDate = stopRequestedAt ?? Date()
        let totalSeconds = max(0, Int(endDate.timeIntervalSince(sessionStartedAt)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
