import AVFoundation
import Combine
import UIKit

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let frameQueue = DispatchQueue(label: "camera.frames")
    private var videoOutput: AVCaptureVideoDataOutput?

    @Published var isRunning = false
    @Published var permissionGranted = false
    @Published var permissionDenied = false
    @Published var isThrottled = false

    var frameProcessor: FrameProcessor?

    var currentFrameSkip: Int {
        isThrottled ? AppConfig.throttledFrameSkipCount : AppConfig.frameSkipCount
    }

    override init() {
        super.init()
        observeThermalState()
        observeDeviceOrientation()
    }

    func checkPermissionAndStart() {
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
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func configureSession() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
    }

    private func updateVideoOrientation() {
        guard let connection = videoOutput?.connection(with: .video) else { return }
        let orientation = UIDevice.current.orientation
        if #available(iOS 17.0, *) {
            guard connection.isVideoRotationAngleSupported(0) else { return }
            switch orientation {
            case .portrait: connection.videoRotationAngle = 90
            case .portraitUpsideDown: connection.videoRotationAngle = 270
            case .landscapeLeft: connection.videoRotationAngle = 0
            case .landscapeRight: connection.videoRotationAngle = 180
            default: connection.videoRotationAngle = 0
            }
        } else {
            guard connection.isVideoOrientationSupported else { return }
            switch orientation {
            case .portrait: connection.videoOrientation = .portrait
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft: connection.videoOrientation = .landscapeRight
            case .landscapeRight: connection.videoOrientation = .landscapeLeft
            default: connection.videoOrientation = .landscapeRight
            }
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
        frameProcessor?.processFrame(sampleBuffer, skipCount: currentFrameSkip)
    }
}
