import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @Environment(\.scenePhase) private var scenePhase

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
            StatusBarView()
        }
        .onAppear {
            cameraManager.checkPermissionAndStart()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if cameraManager.permissionGranted {
                    cameraManager.start()
                }
            case .background:
                cameraManager.stop()
            default:
                break
            }
        }
    }
}
