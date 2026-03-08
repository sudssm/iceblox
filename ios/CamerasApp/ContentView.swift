import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var connectivityMonitor = ConnectivityMonitor()
    @Environment(\.scenePhase) private var scenePhase

    @State private var offlineQueue = OfflineQueue()
    @State private var frameProcessor: FrameProcessor?
    @State private var apiClient: APIClient?
    @State private var debugMode = false
    @State private var lastStatusUpdate = Date()

    let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            if cameraManager.permissionGranted {
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()
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
                                Text("Enable in Settings → CamerasApp → Camera")
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
            if debugMode, let fp = frameProcessor {
                DebugOverlayView(
                    detections: fp.currentDetections,
                    rawDetections: fp.rawDetections,
                    feedEntries: fp.detectionFeed,
                    fps: fp.fps,
                    queueDepth: offlineQueue.count,
                    isConnected: connectivityMonitor.isConnected
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            #endif

            StatusBarView(
                isConnected: connectivityMonitor.isConnected,
                lastDetection: frameProcessor?.lastDetectionTime,
                plateCount: frameProcessor?.totalPlates ?? 0,
                targetCount: apiClient?.totalTargets ?? 0,
                hasGPS: locationManager.hasPermission
            )
        }
        #if DEBUG
        .onTapGesture(count: 3) {
            debugMode.toggle()
        }
        #endif
        .onReceive(statusTimer) { _ in
            lastStatusUpdate = Date()
        }
        .onAppear {
            setupPipeline()
            cameraManager.checkPermissionAndStart()
            locationManager.requestPermission()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if cameraManager.permissionGranted {
                    cameraManager.start()
                }
                apiClient?.startBatchTimer()
            case .background:
                cameraManager.stop()
                apiClient?.flushQueue()
                apiClient?.stopBatchTimer()
            default:
                break
            }
        }
    }

    private func setupPipeline() {
        let client = APIClient(offlineQueue: offlineQueue)
        let processor = FrameProcessor(
            offlineQueue: offlineQueue,
            locationManager: locationManager,
            apiClient: client
        )

        client.onPlateSent = { [weak processor] hash, matched in
            processor?.onPlateSent(hash: hash, matched: matched)
        }

        connectivityMonitor.onReconnect = { [weak client] in
            client?.flushQueue()
        }

        cameraManager.frameProcessor = processor
        self.frameProcessor = processor
        self.apiClient = client

        client.startBatchTimer()
    }
}
