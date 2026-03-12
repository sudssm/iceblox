import AVFoundation
import Combine
import UIKit

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let frameQueue = DispatchQueue(label: "camera.frames")
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var captureDevice: AVCaptureDevice?
    private(set) var zoomController: ZoomController?

    @Published var isRunning = false
    @Published var permissionGranted = false
    @Published var permissionDenied = false
    @Published var isThrottled = false

    #if targetEnvironment(simulator)
    private var simulatorCamera: SimulatorCamera?
    @Published var simulatorImage: UIImage?
    #endif

    var frameProcessor: FrameProcessor? {
        didSet {
            frameProcessor?.zoomController = zoomController
            #if targetEnvironment(simulator)
            simulatorCamera?.frameProcessor = frameProcessor
            #endif
        }
    }

    var currentFrameSkip: Int {
        isThrottled ? AppConfig.throttledFrameSkipCount : AppConfig.frameSkipCount
    }

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        let simCam = SimulatorCamera()
        simCam.onPreviewImageChange = { [weak self] image in
            self?.simulatorImage = image
        }
        simulatorCamera = simCam
        simulatorImage = simCam.previewImage
        #else
        observeThermalState()
        observeDeviceOrientation()
        #endif
    }

    func checkPermissionAndStart() {
        #if targetEnvironment(simulator)
        permissionGranted = true
        start()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    self?.permissionDenied = !granted
                }
                if granted {
                    self?.start()
                }
            }
        default:
            permissionDenied = true
        }
        #endif
    }

    func start() {
        #if targetEnvironment(simulator)
        simulatorCamera?.frameProcessor = frameProcessor
        simulatorCamera?.start()
        DispatchQueue.main.async { [weak self] in self?.isRunning = true }
        #else
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
        #endif
    }

    func stop() {
        #if targetEnvironment(simulator)
        simulatorCamera?.stop()
        DispatchQueue.main.async { [weak self] in self?.isRunning = false }
        #else
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
        #endif
    }

    private func bestAvailableCamera() -> AVCaptureDevice? {
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        for deviceType in preferredTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                DebugLog.shared.d("CameraManager", "Selected camera: \(deviceType)")
                return device
            }
        }
        return nil
    }

    private func configureSession() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()

        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else {
            session.sessionPreset = .hd1920x1080
            DebugLog.shared.w("CameraManager", "4K not supported, falling back to 1080p")
        }

        guard let camera = bestAvailableCamera(),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: frameQueue)
        output.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output
            updateVideoOrientation()
        }

        session.commitConfiguration()

        let switchOverFactors = camera.virtualDeviceSwitchOverVideoZoomFactors
        let baselineZoom = switchOverFactors.first?.doubleValue ?? 1.0
        DebugLog.shared.d("CameraManager", "switchOverFactors=\(switchOverFactors) baselineZoom=\(baselineZoom)")

        if baselineZoom > 1.0 {
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = CGFloat(baselineZoom)
                camera.unlockForConfiguration()
            } catch {
                DebugLog.shared.e("CameraManager", "Failed to set baseline zoom: \(error.localizedDescription)")
            }
        }

        captureDevice = camera
        zoomController = ZoomController(device: camera, baselineZoom: CGFloat(baselineZoom))
    }

    private func updateVideoOrientation() {
        guard let connection = videoOutput?.connection(with: .video) else { return }
        let angle: CGFloat
        switch UIDevice.current.orientation {
        case .portrait: angle = 90
        case .portraitUpsideDown: angle = 270
        case .landscapeLeft: angle = 0
        case .landscapeRight: angle = 180
        default: angle = 0
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func observeDeviceOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async {
                self?.updateVideoOrientation()
            }
        }
    }

    private func observeThermalState() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            self?.isThrottled = state == .serious || state == .critical
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameProcessor?.isThrottled = isThrottled
        frameProcessor?.processFrame(sampleBuffer, skipCount: currentFrameSkip)
    }
}
