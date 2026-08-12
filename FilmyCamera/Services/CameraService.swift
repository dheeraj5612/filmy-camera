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

    /// A typed lifecycle contract for the camera UI. `statusMessage` remains
    /// user-facing copy, but views should use this value for branching so a
    /// wording change cannot silently break recovery behavior.
    public enum Availability: String, Equatable, Sendable {
        case idle
        case starting
        case requestingPermission
        case running
        case paused
        case simulator
        case permissionDenied
        case interrupted
        case needsRecovery
        case unavailable
    }

    public struct CapturedPhoto: @unchecked Sendable {
        public let fileData: Data
        public let capturedAt: Date
        public let dimensions: CMVideoDimensions

        public init(
            fileData: Data,
            capturedAt: Date,
            dimensions: CMVideoDimensions
        ) {
            self.fileData = fileData
            self.capturedAt = capturedAt
            self.dimensions = dimensions
        }
    }

    public typealias PhotoCompletion = (CapturedPhoto?) -> Void

    /// Keeps only the newest frame while the main thread is busy rendering.
    /// Camera preview is inherently latest-value data; queuing every frame
    /// makes the UI chase stale images and increases memory pressure.
    private final class FrameDeliveryGate: @unchecked Sendable {
        weak var owner: CameraService?

        private let lock = NSLock()
        private var pendingImage: CIImage?
        private var deliveryScheduled = false

        func submit(_ image: CIImage) {
            lock.lock()
            pendingImage = image
            guard !deliveryScheduled else {
                lock.unlock()
                return
            }
            deliveryScheduled = true
            lock.unlock()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.lock.lock()
                let nextImage = self.pendingImage
                self.pendingImage = nil
                self.deliveryScheduled = false
                self.lock.unlock()

                if let nextImage {
                    self.owner?.onFrame?(nextImage)
                }
            }
        }
    }

    public let session: AVCaptureSession

    @Published public private(set) var isRunning = false
    @Published public private(set) var statusMessage = "Camera is ready"
    @Published public private(set) var availability: Availability = .idle
    @Published public private(set) var zoomFactor: CGFloat = 1
    @Published public private(set) var isFocusExposureLocked = false
    @Published public private(set) var previewFrameSize: CGSize = .zero
    @Published public private(set) var previewViewportSize: CGSize = .zero

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
    private let frameDeliveryGate = FrameDeliveryGate()

    // These values are accessed only by sessionQueue, except for immutable
    // AVFoundation objects used by the public session property.
    private var isConfigured = false
    private var wantsToRun = false
    private var authorizationRequestInFlight = false
    private var pendingPhotoCompletion: PhotoCompletion?
    private var pendingPhotoCapturedAt: Date?
    private var configuredPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
    private var focusExposureLocked = false
    private var sessionObservers: [NSObjectProtocol] = []
    private var rotationAngle: CGFloat = 90
    private var lastDeliveredFrameSize: CGSize = .zero

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

        frameDeliveryGate.owner = self
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        installSessionObservers()
    }

    deinit {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
    }

    /// Requests camera permission when needed and starts the session. On a
    /// simulator or a device without a camera this becomes a clean empty state.
    public func start() {
        sessionQueue.async { [weak self] in
            self?.publishAvailability(.starting)
            self?.wantsToRun = true
            self?.requestAuthorizationAndStartOnQueue()
        }
    }

    /// Stops capture while retaining the configured session for a later start.
    public func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsToRun = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.cancelPendingPhotoOnQueue(status: "Capture canceled.")
            self.focusExposureLocked = false
            self.publishFocusExposureLocked(false)
            self.publishRunning(false)
            self.publishAvailability(.paused)
            self.publishStatus("Camera paused")
        }
    }

    /// Keeps the preview and still output aligned with the current camera
    /// surface when the phone rotates or enters a split-screen layout.
    public func updateOrientation(for viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        publishPreviewViewportSize(viewSize)
        let nextAngle: CGFloat = viewSize.width > viewSize.height ? 0 : 90

        sessionQueue.async { [weak self] in
            guard let self, self.rotationAngle != nextAngle else { return }
            self.rotationAngle = nextAngle
            guard self.isConfigured else { return }
            self.configureOrientation()
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
        let point = clampedNormalizedPoint(normalizedPoint)

        sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice() else { return }
            do {
                self.focusExposureLocked = false
                self.publishFocusExposureLocked(false)
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

    /// Locks focus and exposure at the selected preview point. The explicit
    /// control keeps the camera usable with VoiceOver and avoids making a
    /// long-press gesture the only way to create a lock.
    public func toggleFocusExposureLock(at normalizedPoint: CGPoint) {
        let point = clampedNormalizedPoint(normalizedPoint)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice() else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if self.focusExposureLocked {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    } else if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    } else if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                    self.focusExposureLocked = false
                    self.publishFocusExposureLocked(false)
                    self.publishStatus("Focus and exposure unlocked")
                    return
                }

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                }

                let canLockFocus = device.isFocusModeSupported(.locked)
                let canLockExposure = device.isExposureModeSupported(.locked)
                guard canLockFocus || canLockExposure else {
                    self.publishStatus("Focus lock is unavailable right now.")
                    return
                }

                if canLockFocus {
                    device.focusMode = .locked
                }
                if canLockExposure {
                    device.exposureMode = .locked
                }
                self.focusExposureLocked = true
                self.publishFocusExposureLocked(true)
                self.publishStatus("Focus and exposure locked")
            } catch {
                self.publishStatus("Focus lock is unavailable right now.")
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
        guard wantsToRun else { return }
        guard !session.isRunning else {
            publishRunning(true)
            publishAvailability(.running)
            publishStatus("Camera ready")
            return
        }

        // AVCaptureDevice.default returns nil on the iOS Simulator without a
        // camera device. Checking before requesting access avoids presenting a
        // permission prompt for hardware that cannot exist in this process.
        guard defaultCameraDevice() != nil else {
            publishRunning(false)
            publishAvailability(.simulator)
            publishStatus("Camera unavailable in Simulator. Use an iPhone to preview and capture.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartOnQueue()
        case .notDetermined:
            guard !authorizationRequestInFlight else { return }
            authorizationRequestInFlight = true
            publishAvailability(.requestingPermission)
            publishStatus("Requesting camera access…")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.sessionQueue.async { [weak self] in
                    guard let self else { return }
                    self.authorizationRequestInFlight = false
                    if granted, self.wantsToRun {
                        self.configureAndStartOnQueue()
                    } else {
                        self.publishRunning(false)
                        self.publishAvailability(.permissionDenied)
                        self.publishStatus("Camera access is required to preview and capture.")
                    }
                }
            }
        case .denied, .restricted:
            publishRunning(false)
            publishAvailability(.permissionDenied)
            publishStatus("Camera access is disabled in Settings.")
        @unknown default:
            publishRunning(false)
            publishAvailability(.unavailable)
            publishStatus("Camera access is unavailable.")
        }
    }

    private func configureAndStartOnQueue() {
        guard wantsToRun else { return }
        guard !session.isRunning else {
            publishRunning(true)
            publishAvailability(.running)
            publishStatus("Camera ready")
            return
        }

        // A stopped session keeps its inputs and outputs. Reuse the existing
        // graph when returning from background or another tab instead of
        // trying to add duplicate AVFoundation objects.
        if isConfigured {
            configureOrientation()
            session.startRunning()
            let running = session.isRunning
            publishRunning(running)
            publishAvailability(running ? .running : .unavailable)
            publishStatus(running ? "Camera ready" : "Camera could not start.")
            return
        }

        guard let device = defaultCameraDevice() else {
            publishRunning(false)
            publishAvailability(.simulator)
            publishStatus("Camera unavailable in Simulator. Use an iPhone to preview and capture.")
            return
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            publishRunning(false)
            publishAvailability(.unavailable)
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
            publishAvailability(.unavailable)
            publishStatus("Camera input is unavailable.")
            return
        }
        session.addInput(input)

        guard session.canAddOutput(videoOutput) else {
            session.removeInput(input)
            session.commitConfiguration()
            publishRunning(false)
            publishAvailability(.unavailable)
            publishStatus("Live preview is unavailable.")
            return
        }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else {
            session.removeOutput(videoOutput)
            session.removeInput(input)
            session.commitConfiguration()
            publishRunning(false)
            publishAvailability(.unavailable)
            publishStatus("Still capture is unavailable.")
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        configurePhotoDimensions(for: device)
        session.commitConfiguration()

        configurePreviewFrameRate(for: device)
        configureOrientation()
        isConfigured = true
        session.startRunning()

        let running = session.isRunning
        publishRunning(running)
        publishAvailability(running ? .running : .unavailable)
        publishStatus(running ? "Camera ready" : "Camera could not start.")
    }

    private func installSessionObservers() {
        let notificationCenter = NotificationCenter.default
        sessionObservers = [
            notificationCenter.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                let errorCode = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code.rawValue
                self?.sessionQueue.async { [weak self] in
                    self?.handleRuntimeError(codeRawValue: errorCode)
                }
            },
            notificationCenter.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in
                    guard let self, self.wantsToRun else { return }
                    self.publishRunning(false)
                    self.publishAvailability(.interrupted)
                    self.publishStatus("Camera temporarily unavailable.")
                }
            },
            notificationCenter.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in
                    guard let self,
                          self.wantsToRun,
                          AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                        return
                    }
                    self.session.startRunning()
                    let running = self.session.isRunning
                    self.publishRunning(running)
                    self.publishAvailability(running ? .running : .needsRecovery)
                    self.publishStatus(running ? "Camera ready" : "Camera could not start.")
                }
            }
        ]
    }

    private func handleRuntimeError(codeRawValue: Int?) {
        // Apple recommends restarting after media services reset. Other
        // runtime errors remain visible so the UI can explain the recovery
        // path instead of silently presenting a frozen preview.
        guard wantsToRun else { return }
        if codeRawValue == AVError.Code.mediaServicesWereReset.rawValue, isConfigured {
            session.startRunning()
            let running = session.isRunning
            publishRunning(running)
            publishAvailability(running ? .running : .needsRecovery)
            publishStatus(running ? "Camera ready" : "Camera needs to be reopened.")
            return
        }

        publishRunning(false)
        publishAvailability(.needsRecovery)
        publishStatus("Camera needs to be reopened.")
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
        configureRotation(videoOutput.connection(with: .video), angle: rotationAngle)
        configureRotation(photoOutput.connection(with: .video), angle: rotationAngle)
    }

    private func configurePreviewFrameRate(for device: AVCaptureDevice) {
        let targetDuration = CMTime(value: 1, timescale: 30)
        let supportsTargetDuration = device.activeFormat.videoSupportedFrameRateRanges.contains {
            CMTimeCompare(targetDuration, $0.minFrameDuration) >= 0
                && CMTimeCompare(targetDuration, $0.maxFrameDuration) <= 0
        }
        guard supportsTargetDuration else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // The preview view renders at 30 fps. Match the active camera
            // cadence so the device does not create frames that the renderer
            // will immediately drop on a 60 fps-capable format.
            device.activeVideoMinFrameDuration = targetDuration
            device.activeVideoMaxFrameDuration = targetDuration
        } catch {
            // Frame-rate capping is an optimization only; the session remains
            // valid if a device refuses this configuration.
        }
    }

    private func configurePhotoDimensions(for device: AVCaptureDevice) {
        let supportedDimensions = device.activeFormat.supportedMaxPhotoDimensions
        guard let maximum = supportedDimensions.max(by: { lhs, rhs in
            Int64(lhs.width) * Int64(lhs.height) < Int64(rhs.width) * Int64(rhs.height)
        }) else {
            return
        }

        photoOutput.maxPhotoDimensions = maximum
        configuredPhotoDimensions = maximum
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
        pendingPhotoCapturedAt = Date()
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.photoQualityPrioritization = .quality
        if configuredPhotoDimensions.width > 0, configuredPhotoDimensions.height > 0 {
            settings.maxPhotoDimensions = configuredPhotoDimensions
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishPhotoOnQueue(_ photo: CapturedPhoto?) {
        let completion = pendingPhotoCompletion
        pendingPhotoCompletion = nil
        pendingPhotoCapturedAt = nil
        guard let completion else { return }

        if photo == nil {
            publishStatus("The photo could not be processed.")
        } else {
            publishStatus("Photo captured")
        }
        publishPhoto(photo, completion: completion)
    }

    private func cancelPendingPhotoOnQueue(status: String) {
        guard let completion = pendingPhotoCompletion else { return }
        pendingPhotoCompletion = nil
        pendingPhotoCapturedAt = nil
        publishStatus(status)
        publishPhoto(nil, completion: completion)
    }

    private func publishRunning(_ running: Bool) {
        publishOnMain { [weak self] in
            self?.isRunning = running
        }
    }

    private func publishAvailability(_ availability: Availability) {
        publishOnMain { [weak self] in
            self?.availability = availability
        }
    }

    private func publishZoom(_ factor: CGFloat) {
        publishOnMain { [weak self] in
            self?.zoomFactor = factor
        }
    }

    private func publishFocusExposureLocked(_ locked: Bool) {
        publishOnMain { [weak self] in
            self?.isFocusExposureLocked = locked
        }
    }

    private func publishPreviewFrameSize(_ size: CGSize) {
        publishOnMain { [weak self] in
            self?.previewFrameSize = size
        }
    }

    private func publishPreviewViewportSize(_ size: CGSize) {
        publishOnMain { [weak self] in
            self?.previewViewportSize = size
        }
    }

    private func publishStatus(_ message: String) {
        publishOnMain { [weak self] in
            self?.statusMessage = message
        }
    }

    private func publishPhoto(_ photo: CapturedPhoto?, completion: @escaping PhotoCompletion) {
        publishOnMain {
            completion(photo)
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

    private func clampedNormalizedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
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

        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        if frameSize != lastDeliveredFrameSize {
            lastDeliveredFrameSize = frameSize
            publishPreviewFrameSize(frameSize)
        }

        let image: CIImage
        if let sRGBColorSpace {
            image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: sRGBColorSpace])
        } else {
            image = CIImage(cvPixelBuffer: pixelBuffer)
        }

        // CIImage is immutable and the callback is intentionally delivered on
        // main, where SwiftUI/Metal preview views can consume it safely. The
        // gate drops stale frames if rendering is slower than capture.
        frameDeliveryGate.submit(image)
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data: Data?
        if error == nil,
           let fileData = photo.fileDataRepresentation() {
            data = fileData
        } else {
            data = nil
        }
        let dimensions = photo.resolvedSettings.photoDimensions

        // Photo delegate callbacks are not required to arrive on our session
        // queue, so serialize completion state before hopping to main.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let capturedPhoto = data.flatMap { fileData in
                CapturedPhoto(
                    fileData: fileData,
                    capturedAt: self.pendingPhotoCapturedAt ?? Date(),
                    dimensions: dimensions
                )
            }
            self.finishPhotoOnQueue(capturedPhoto)
        }
    }
}
