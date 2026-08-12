@preconcurrency import AVFoundation
import Combine
import CoreImage
import CoreMedia
import Foundation
import UIKit

/// Owns the AVFoundation session and provides CIImage frames to the preview.
///
/// Session configuration and capture callbacks stay on a private serial queue.
/// Published state and `onFrame` are delivered on the main queue so SwiftUI
/// callers do not need to coordinate AVFoundation's worker threads.
public final class CameraService: NSObject, ObservableObject, @unchecked Sendable {
    public typealias FrameHandler = (CIImage) -> Void
    public typealias PhotoCompletion = (UIImage?) -> Void

    public let session: AVCaptureSession

    @Published public private(set) var isRunning = false
    @Published public private(set) var statusMessage = "Camera is ready"
    @Published public private(set) var zoomFactor: CGFloat = 1

    /// Receives unfiltered live frames on the main queue.
    public var onFrame: FrameHandler?

    private let sessionQueue = DispatchQueue(
        label: "com.dheeraj.filmycamera.camera-session",
        qos: .userInitiated
    )
    private let videoQueue = DispatchQueue(
        label: "com.dheeraj.filmycamera.camera-frames",
        qos: .userInitiated
    )
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    // These values are accessed only by sessionQueue, except for immutable
    // AVFoundation objects used by the public session property.
    private var isConfigured = false
    private var authorizationRequestInFlight = false
    private var pendingPhotoCompletion: PhotoCompletion?

    private final class PhotoCompletionBox: @unchecked Sendable {
        let completion: PhotoCompletion

        init(_ completion: @escaping PhotoCompletion) {
            self.completion = completion
        }
    }

    private final class MainWorkBox: @unchecked Sendable {
        let work: () -> Void

        init(_ work: @escaping () -> Void) {
            self.work = work
        }
    }

    public override init() {
        self.session = AVCaptureSession()
        super.init()

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
    }

    deinit {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
    }

    /// Requests camera permission when needed and starts the session. On a
    /// simulator or a device without a camera this becomes a clean empty state.
    public func start() {
        sessionQueue.async { [weak self] in
            self?.requestAuthorizationAndStartOnQueue()
        }
    }

    /// Stops capture while retaining the configured session for a later start.
    public func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.publishRunning(false)
            self.publishStatus("Camera paused")
        }
    }

    /// Captures a still through AVCapturePhotoOutput. The completion is
    /// delivered on the main queue and receives nil for permission, hardware,
    /// or photo-processing failures.
    public func capturePhoto(completion: @escaping PhotoCompletion) {
        let completionBox = PhotoCompletionBox(completion)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.capturePhotoOnQueue(completion: completionBox.completion)
        }
    }

    /// Sets continuous focus and exposure at a normalized preview location.
    /// The point uses the camera's metadata coordinate system: (0, 0) is the
    /// top-left and (1, 1) is the bottom-right of the displayed preview.
    public func focus(at normalizedPoint: CGPoint) {
        let point = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )

        sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice() else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    } else if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
            } catch {
                self.publishStatus("Focus is unavailable right now.")
            }
        }
    }

    /// Sets a bounded optical/digital zoom factor for the active camera.
    public func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice() else { return }
            let upperBound = min(device.maxAvailableVideoZoomFactor, 6)
            let nextFactor = min(max(factor, device.minAvailableVideoZoomFactor), upperBound)
            guard nextFactor.isFinite else { return }

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = nextFactor
                device.unlockForConfiguration()
                self.publishZoom(nextFactor)
            } catch {
                self.publishStatus("Zoom is unavailable right now.")
            }
        }
    }

    private func requestAuthorizationAndStartOnQueue() {
        guard !session.isRunning else {
            publishRunning(true)
            publishStatus("Camera ready")
            return
        }

        // AVCaptureDevice.default returns nil on the iOS Simulator without a
        // camera device. Checking before requesting access avoids presenting a
        // permission prompt for hardware that cannot exist in this process.
        guard defaultCameraDevice() != nil else {
            publishRunning(false)
            publishStatus("Camera unavailable in Simulator. Use an iPhone to preview and capture.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartOnQueue()
        case .notDetermined:
            guard !authorizationRequestInFlight else { return }
            authorizationRequestInFlight = true
            publishStatus("Requesting camera access…")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.sessionQueue.async { [weak self] in
                    guard let self else { return }
                    self.authorizationRequestInFlight = false
                    if granted {
                        self.configureAndStartOnQueue()
                    } else {
                        self.publishRunning(false)
                        self.publishStatus("Camera access is required to preview and capture.")
                    }
                }
            }
        case .denied, .restricted:
            publishRunning(false)
            publishStatus("Camera access is disabled in Settings.")
        @unknown default:
            publishRunning(false)
            publishStatus("Camera access is unavailable.")
        }
    }

    private func configureAndStartOnQueue() {
        guard !session.isRunning else {
            publishRunning(true)
            publishStatus("Camera ready")
            return
        }

        guard let device = defaultCameraDevice() else {
            publishRunning(false)
            publishStatus("Camera unavailable in Simulator. Use an iPhone to preview and capture.")
            return
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            publishRunning(false)
            publishStatus("Camera could not be configured.")
            return
        }

        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            publishRunning(false)
            publishStatus("Camera input is unavailable.")
            return
        }
        session.addInput(input)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            publishRunning(false)
            publishStatus("Live preview is unavailable.")
            return
        }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            publishRunning(false)
            publishStatus("Still capture is unavailable.")
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()

        configureOrientation()
        isConfigured = true
        session.startRunning()

        let running = session.isRunning
        publishRunning(running)
        publishStatus(running ? "Camera ready" : "Camera could not start.")
    }

    private func defaultCameraDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
    }

    private func activeDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first
    }

    private func configureOrientation() {
        let portraitAngle: CGFloat = 90
        configureRotation(videoOutput.connection(with: .video), angle: portraitAngle)
        configureRotation(photoOutput.connection(with: .video), angle: portraitAngle)
    }

    private func configureRotation(
        _ connection: AVCaptureConnection?,
        angle: CGFloat
    ) {
        guard let connection,
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }
        connection.videoRotationAngle = angle
    }

    private func capturePhotoOnQueue(completion: @escaping PhotoCompletion) {
        guard isConfigured, session.isRunning else {
            publishStatus("Start the camera before capturing.")
            publishPhoto(nil, completion: completion)
            return
        }

        guard pendingPhotoCompletion == nil else {
            publishStatus("Finishing the previous capture…")
            publishPhoto(nil, completion: completion)
            return
        }

        pendingPhotoCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishPhotoOnQueue(_ image: UIImage?) {
        let completion = pendingPhotoCompletion
        pendingPhotoCompletion = nil
        guard let completion else { return }

        if image == nil {
            publishStatus("The photo could not be processed.")
        } else {
            publishStatus("Photo captured")
        }
        publishPhoto(image, completion: completion)
    }

    private func publishRunning(_ running: Bool) {
        publishOnMain { [weak self] in
            self?.isRunning = running
        }
    }

    private func publishZoom(_ factor: CGFloat) {
        publishOnMain { [weak self] in
            self?.zoomFactor = factor
        }
    }

    private func publishStatus(_ message: String) {
        publishOnMain { [weak self] in
            self?.statusMessage = message
        }
    }

    private func publishPhoto(_ image: UIImage?, completion: @escaping PhotoCompletion) {
        publishOnMain {
            completion(image)
        }
    }

    private func publishOnMain(_ work: @escaping () -> Void) {
        let workBox = MainWorkBox(work)
        if Thread.isMainThread {
            workBox.work()
        } else {
            DispatchQueue.main.async {
                workBox.work()
            }
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoOutput,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let image: CIImage
        if let sRGBColorSpace {
            image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: sRGBColorSpace])
        } else {
            image = CIImage(cvPixelBuffer: pixelBuffer)
        }

        // CIImage is immutable and the callback is intentionally delivered on
        // main, where SwiftUI/Metal preview views can consume it safely.
        publishOnMain { [weak self] in
            self?.onFrame?(image)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage?
        if error == nil,
           let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = nil
        }

        // Photo delegate callbacks are not required to arrive on our session
        // queue, so serialize completion state before hopping to main.
        sessionQueue.async { [weak self] in
            self?.finishPhotoOnQueue(image)
        }
    }
}
