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

    /// The physical direction used by the active capture device. The service
    /// keeps this separate from AVFoundation's enum so the UI and view model
    /// do not need to import camera framework implementation details.
    public enum CameraPosition: String, CaseIterable, Equatable, Hashable, Sendable {
        case back
        case front

        public var title: String {
            switch self {
            case .back: "Back"
            case .front: "Front"
            }
        }

        public var systemImageName: String {
            switch self {
            case .back: "camera.fill"
            case .front: "camera.rotate"
            }
        }
    }

    /// A lens exposed by the active camera hardware. For a virtual camera,
    /// `zoomFactor` is the AVFoundation switch-over value for that lens. For
    /// a single physical camera it is the device's neutral zoom factor.
    public struct LensOption: Identifiable, Equatable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
        public let zoomFactor: CGFloat
        public let position: CameraPosition

        public init(
            id: String,
            title: String,
            detail: String,
            zoomFactor: CGFloat,
            position: CameraPosition
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.zoomFactor = zoomFactor
            self.position = position
        }
    }

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

    /// Resolves the state a stopped session should expose without turning a
    /// lifecycle pause into a permission decision. Authorization is checked
    /// before hardware availability so a denied camera remains denied even
    /// when the device currently has no usable camera input.
    public static func availabilityAfterStopping(
        authorizationStatus: AVAuthorizationStatus,
        hasCameraDevice: Bool,
        previousAvailability: Availability
    ) -> Availability {
        switch authorizationStatus {
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return hasCameraDevice ? .idle : .simulator
        case .authorized:
            switch previousAvailability {
            case .unavailable, .needsRecovery:
                return previousAvailability
            default:
                return hasCameraDevice ? .paused : .simulator
            }
        @unknown default:
            return .unavailable
        }
    }

    /// The still-photo flash request. `off` is intentionally the default so
    /// opening the camera never fires the flash without an explicit choice.
    public enum FlashMode: Int, CaseIterable, Equatable, Sendable {
        case off = 0
        case auto = 2
        case on = 1

        public var title: String {
            switch self {
            case .off: "Off"
            case .auto: "Auto"
            case .on: "On"
            }
        }

        public var systemImageName: String {
            switch self {
            case .off: "bolt.slash"
            case .auto: "bolt"
            case .on: "bolt.fill"
            }
        }
    }

    /// Flash support is separate from camera lifecycle availability. A
    /// Simulator or a camera without a flash is `.unsupported`; a supported
    /// flash that is temporarily unavailable (for example, due to thermal
    /// protection) is surfaced as `.temporarilyUnavailable`.
    public enum FlashAvailability: String, Equatable, Sendable {
        case unsupported
        case available
        case temporarilyUnavailable
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
    @Published public private(set) var flashMode: FlashMode = .off
    @Published public private(set) var flashAvailability: FlashAvailability = .unsupported
    @Published public private(set) var lowLightBoostSupported = false
    @Published public private(set) var isLowLightBoostEnabled = false
    @Published public private(set) var zoomFactor: CGFloat = 1
    @Published public private(set) var minZoomFactor: CGFloat = 1
    @Published public private(set) var maxZoomFactor: CGFloat = 1
    @Published public private(set) var cameraPosition: CameraPosition = .back
    @Published public private(set) var availableCameraPositions: [CameraPosition] = []
    @Published public private(set) var availableLenses: [LensOption] = []
    @Published public private(set) var selectedLensID: String?
    @Published public private(set) var exposureBias: Float = 0
    @Published public private(set) var isFocusExposureLocked = false
    @Published public private(set) var previewFrameSize: CGSize = .zero
    @Published public private(set) var previewViewportSize: CGSize = .zero

    /// Receives unfiltered live frames on the main queue.
    public var onFrame: FrameHandler?

    private var frameHandlerID: UUID?

    private let sessionQueue = DispatchQueue(
        label: "com.dheeraj.filmycamera.camera-session",
        qos: .userInitiated
    )
    private let sessionQueueKey = DispatchSpecificKey<Void>()
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
    private var sessionAvailability: Availability = .idle
    private var pendingPhotoCompletion: PhotoCompletion?
    private var pendingPhotoCapturedAt: Date?
    private var configuredPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
    private var focusExposureLocked = false
    private var requestedCameraPosition: CameraPosition = .back
    private var currentLensOptions: [LensOption] = []
    private var selectedLensIDs: [CameraPosition: String] = [:]
    private var selectedFlashMode: FlashMode = .off
    private var selectedExposureBias: Float = 0
    private var flashAvailabilityState: FlashAvailability = .unsupported
    private var pendingPhotoFlashFallback = false
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

        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
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

        let session = session
        var pendingCompletion: PhotoCompletion?
        let stopSession = { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            pendingCompletion = self.pendingPhotoCompletion
            self.pendingPhotoCompletion = nil
            self.pendingPhotoCapturedAt = nil
            self.pendingPhotoFlashFallback = false
        }
        if DispatchQueue.getSpecific(key: sessionQueueKey) == nil {
            sessionQueue.sync(execute: stopSession)
        } else {
            stopSession()
        }

        if let pendingCompletion {
            DispatchQueue.main.async {
                pendingCompletion(nil)
            }
        }
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
            let previousAvailability = self.sessionAvailability
            let nextAvailability = Self.availabilityAfterStopping(
                authorizationStatus: AVCaptureDevice.authorizationStatus(for: .video),
                hasCameraDevice: self.hasAnyCameraDeviceOnQueue(),
                previousAvailability: previousAvailability
            )
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.cancelPendingPhotoOnQueue(status: "Capture canceled.")
            self.focusExposureLocked = false
            self.publishFocusExposureLocked(false)
            self.publishRunning(false)

            self.publishAvailability(nextAvailability)
            switch nextAvailability {
            case .permissionDenied:
                self.publishStatus("Camera access is disabled in Settings.")
            case .simulator:
                self.publishStatus("Camera unavailable in Simulator. Use an iPhone to preview and capture.")
            case .idle:
                self.publishStatus("Camera is ready")
            case .unavailable:
                self.publishStatus("Camera access is unavailable.")
            case .needsRecovery:
                self.publishStatus("Camera needs to be reopened.")
            default:
                self.publishStatus("Camera paused")
            }
        }
    }

    /// Selects the front or back camera. On a running device this swaps only
    /// the session input, preserving the existing preview and photo outputs.
    /// On Simulator, where no camera device exists, the request is a safe
    /// no-op and the preview-only state remains unchanged.
    public func setCameraPosition(_ position: CameraPosition) {
        sessionQueue.async { [weak self] in
            self?.setCameraPositionOnQueue(position)
        }
    }

    /// Toggles between the available front and back cameras. If hardware
    /// exposes only one position, the request is ignored safely.
    public func toggleCameraPosition() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let nextPosition: CameraPosition = self.requestedCameraPosition == .back ? .front : .back
            self.setCameraPositionOnQueue(nextPosition)
        }
    }

    /// Selects a hardware-derived lens option. Virtual multi-camera devices
    /// stay in the session and move to the option's switch-over zoom factor;
    /// standalone physical devices are swapped into the session input.
    public func setLens(id: String) {
        sessionQueue.async { [weak self] in
            self?.setLensOnQueue(id: id)
        }
    }

    /// Installs a preview callback and returns an ownership token. A stale
    /// SwiftUI representable can only remove its own callback, so tearing down
    /// an older preview cannot freeze a newer one using the same service.
    @discardableResult
    public func installFrameHandler(_ handler: @escaping FrameHandler) -> UUID {
        let id = UUID()
        frameHandlerID = id
        onFrame = handler
        return id
    }

    public func removeFrameHandler(_ id: UUID) {
        guard frameHandlerID == id else { return }
        frameHandlerID = nil
        onFrame = nil
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

    /// Selects the flash mode used for the next still capture. Unsupported
    /// modes are rejected on the session queue instead of being passed to
    /// AVCapturePhotoOutput, which would otherwise raise an exception.
    public func setFlashMode(_ mode: FlashMode) {
        sessionQueue.async { [weak self] in
            self?.setFlashModeOnQueue(mode)
        }
    }

    /// Cycles through only the flash modes supported by the active photo
    /// output. The control is a no-op on Simulator and on cameras without a
    /// flash, while the safe `.off` mode remains available during thermal
    /// unavailability.
    public func cycleFlashMode() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.flashAvailabilityState == .available else {
                if self.flashAvailabilityState == .temporarilyUnavailable {
                    self.publishStatus("Flash is temporarily unavailable.")
                }
                return
            }

            let supported = self.supportedFlashModeRawValuesOnQueue()
            let modes = FlashMode.allCases.filter { supported.contains($0.rawValue) }
            guard let currentIndex = modes.firstIndex(of: self.selectedFlashMode), !modes.isEmpty else {
                self.setFlashModeOnQueue(.off)
                return
            }
            let nextMode = modes[(currentIndex + 1) % modes.count]
            self.setFlashModeOnQueue(nextMode)
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
                    self.applyExposureBiasOnQueue(to: device)
                }

                self.focusExposureLocked = false
                self.publishFocusExposureLocked(false)
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
                    self.applyExposureBiasOnQueue(to: device)
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
            self?.setZoomOnQueue(factor)
        }
    }

    /// Applies exposure compensation in EV while keeping the camera's own
    /// metering active. The device-specific range is respected on hardware;
    /// the public UI uses a conservative +/-2 EV contract for consistency.
    public func setExposureBias(_ bias: Float) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.activeDevice() else {
                self.publishStatus("Exposure control is available on iPhone.")
                return
            }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                guard let bounds = Self.exposureBiasBounds(
                    lowerBound: device.minExposureTargetBias,
                    upperBound: device.maxExposureTargetBias
                ) else {
                    self.publishStatus("Exposure control is unavailable right now.")
                    return
                }
                let nextBias = Self.clampedExposureBias(
                    Self.quantizedExposureBias(bias),
                    lowerBound: bounds.lower,
                    upperBound: bounds.upper
                )
                self.selectedExposureBias = nextBias
                self.applyExposureBiasOnQueue(to: device)
                self.publishExposureBias(nextBias)
            } catch {
                self.publishStatus("Exposure control is unavailable right now.")
            }
        }
    }

    /// Pure clamping used at the AVFoundation boundary and in unit tests.
    /// Invalid inputs return neutral exposure instead of reaching the device.
    public static func clampedExposureBias(
        _ value: Float,
        lowerBound: Float = -2,
        upperBound: Float = 2
    ) -> Float {
        guard value.isFinite else { return 0 }
        let lower = min(lowerBound, upperBound)
        let upper = max(lowerBound, upperBound)
        return min(max(value, lower), upper)
    }

    /// Snaps camera compensation to real one-third-stop increments so repeated
    /// touch adjustments stay symmetric and always return cleanly to neutral.
    public static func quantizedExposureBias(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return (value * 3).rounded() / 3
    }

    private static func exposureBiasBounds(
        lowerBound: Float,
        upperBound: Float
    ) -> (lower: Float, upper: Float)? {
        guard lowerBound.isFinite, upperBound.isFinite else { return nil }
        let hardwareLower = min(lowerBound, upperBound)
        let hardwareUpper = max(lowerBound, upperBound)
        let lower = max(hardwareLower, -2)
        let upper = min(hardwareUpper, 2)
        guard lower <= upper else { return nil }
        return (lower, upper)
    }

    private func requestAuthorizationAndStartOnQueue() {
        guard wantsToRun else { return }

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorizationStatus {
        case .denied, .restricted:
            if session.isRunning {
                session.stopRunning()
            }
            resetCaptureCapabilitiesOnQueue()
            publishRunning(false)
            publishAvailability(.permissionDenied)
            publishStatus("Camera access is disabled in Settings.")
            return
        case .authorized, .notDetermined:
            break
        @unknown default:
            if session.isRunning {
                session.stopRunning()
            }
            resetCaptureCapabilitiesOnQueue()
            publishRunning(false)
            publishAvailability(.unavailable)
            publishStatus("Camera access is unavailable.")
            return
        }

        guard !session.isRunning else {
            if let device = activeDevice() {
                refreshCaptureCapabilitiesOnQueue(for: device)
            } else {
                resetCaptureCapabilitiesOnQueue()
            }
            publishRunning(true)
            publishAvailability(.running)
            publishStatus("Camera ready")
            return
        }

        // AVCaptureDevice.default returns nil on the iOS Simulator without a
        // camera device. Checking before requesting access avoids presenting a
        // permission prompt for hardware that cannot exist in this process.
        guard hasAnyCameraDeviceOnQueue() else {
            resetCaptureCapabilitiesOnQueue()
            publishRunning(false)
            publishAvailability(.simulator)
            publishStatus("Camera unavailable in Simulator. Use an iPhone to preview and capture.")
            return
        }

        switch authorizationStatus {
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
                    if granted {
                        if self.wantsToRun {
                            self.configureAndStartOnQueue()
                        } else {
                            self.publishRunning(false)
                            self.publishAvailability(.paused)
                            self.publishStatus("Camera paused")
                        }
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
            if let device = activeDevice() {
                refreshCaptureCapabilitiesOnQueue(for: device)
            } else {
                resetCaptureCapabilitiesOnQueue()
            }
            publishRunning(true)
            publishAvailability(.running)
            publishStatus("Camera ready")
            return
        }

        // A stopped session keeps its inputs and outputs. Reuse the existing
        // graph when returning from background or another tab instead of
        // trying to add duplicate AVFoundation objects.
        if isConfigured {
            guard let device = activeDevice() else {
                resetCaptureCapabilitiesOnQueue()
                publishRunning(false)
                publishAvailability(.needsRecovery)
                publishStatus("Camera needs to be reopened.")
                return
            }
            refreshCaptureCapabilitiesOnQueue(for: device)
            configureOrientation()
            session.startRunning()
            let running = session.isRunning
            publishRunning(running)
            publishAvailability(running ? .running : .unavailable)
            publishStatus(running ? "Camera ready" : "Camera could not start.")
            return
        }

        guard let device = preferredCameraDeviceOnQueue(for: requestedCameraPosition) else {
            resetCaptureCapabilitiesOnQueue()
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

        configureCaptureCapabilitiesOnQueue(for: device)
        refreshCameraInventoryOnQueue(for: device)
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

    private static let discoveryDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .builtInTelephotoCamera,
        .builtInTrueDepthCamera
    ]

    private func discoveredCameraDevicesOnQueue(
        for position: CameraPosition
    ) -> [AVCaptureDevice] {
        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.discoveryDeviceTypes,
            mediaType: .video,
            position: avPosition
        ).devices
    }

    private func preferredCameraDeviceOnQueue(
        for position: CameraPosition
    ) -> AVCaptureDevice? {
        discoveredCameraDevicesOnQueue(for: position).first
    }

    private func hasAnyCameraDeviceOnQueue() -> Bool {
        CameraPosition.allCases.contains {
            !discoveredCameraDevicesOnQueue(for: $0).isEmpty
        }
    }

    private func cameraPosition(for device: AVCaptureDevice) -> CameraPosition {
        device.position == .front ? .front : .back
    }

    private func activeDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first
    }

    private func setCameraPositionOnQueue(_ position: CameraPosition) {
        guard let desiredDevice = preferredCameraDeviceOnQueue(for: position) else {
            publishStatus("Camera switching is available on iPhone.")
            publishAvailableCameraPositions([])
            return
        }

        requestedCameraPosition = position
        guard isConfigured else {
            refreshCameraInventoryOnQueue(for: desiredDevice)
            publishCameraPosition(position)
            return
        }

        if let activeDevice = activeDevice(), cameraPosition(for: activeDevice) == position {
            refreshCaptureCapabilitiesOnQueue(for: activeDevice)
            refreshCameraInventoryOnQueue(for: activeDevice)
            publishCameraPosition(position)
            return
        }

        guard replaceCameraInputOnQueue(with: desiredDevice) else {
            publishStatus("The \(position.title.lowercased()) camera is unavailable right now.")
            return
        }

        focusExposureLocked = false
        publishFocusExposureLocked(false)
        publishCameraPosition(position)
        refreshCaptureCapabilitiesOnQueue(for: desiredDevice)
        refreshCameraInventoryOnQueue(for: desiredDevice)
        configurePreviewFrameRate(for: desiredDevice)
        configureOrientation()
        publishStatus("\(position.title) camera ready")
    }

    private func setLensOnQueue(id: String) {
        guard let option = currentLensOptions.first(where: { $0.id == id }) else {
            publishStatus("That lens is unavailable on this camera.")
            return
        }
        guard let device = activeDevice() else {
            publishStatus("Lens selection is available on iPhone.")
            return
        }

        let position = cameraPosition(for: device)
        guard option.position == position else { return }
        selectedLensIDs[position] = option.id

        if device.isVirtualDevice {
            setZoomOnQueue(option.zoomFactor)
            publishSelectedLensID(option.id)
            return
        }

        guard option.id != device.uniqueID,
              let alternateDevice = discoveredCameraDevicesOnQueue(for: position)
                .first(where: { $0.uniqueID == option.id }) else {
            setZoomOnQueue(option.zoomFactor)
            publishSelectedLensID(option.id)
            return
        }

        guard replaceCameraInputOnQueue(with: alternateDevice) else {
            publishStatus("That lens is unavailable right now.")
            return
        }
        refreshCaptureCapabilitiesOnQueue(for: alternateDevice)
        refreshCameraInventoryOnQueue(for: alternateDevice)
        configurePreviewFrameRate(for: alternateDevice)
        publishSelectedLensID(option.id)
        publishStatus("\(option.title) lens ready")
    }

    private func setZoomOnQueue(_ factor: CGFloat) {
        guard let device = activeDevice() else { return }
        let lowerBound = device.minAvailableVideoZoomFactor
        let upperBound = min(device.maxAvailableVideoZoomFactor, 6)
        let nextFactor = min(max(factor, lowerBound), max(lowerBound, upperBound))
        guard nextFactor.isFinite else { return }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = nextFactor
            device.unlockForConfiguration()
            publishZoomRange(
                minimum: lowerBound,
                maximum: max(lowerBound, upperBound)
            )
            publishZoom(nextFactor)
            if let nearestLens = currentLensOptions.min(by: {
                abs($0.zoomFactor - nextFactor) < abs($1.zoomFactor - nextFactor)
            }) {
                selectedLensIDs[cameraPosition(for: device)] = nearestLens.id
                publishSelectedLensID(nearestLens.id)
            }
        } catch {
            publishStatus("Zoom is unavailable right now.")
        }
    }

    private func replaceCameraInputOnQueue(with device: AVCaptureDevice) -> Bool {
        guard let newInput = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        let oldInput = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first
        session.beginConfiguration()
        if let oldInput {
            session.removeInput(oldInput)
        }

        guard session.canAddInput(newInput) else {
            if let oldInput, session.canAddInput(oldInput) {
                session.addInput(oldInput)
            }
            session.commitConfiguration()
            return false
        }

        session.addInput(newInput)
        configurePhotoDimensions(for: device)
        configureOrientation()
        session.commitConfiguration()
        return true
    }

    private func refreshCameraInventoryOnQueue(for device: AVCaptureDevice) {
        let position = cameraPosition(for: device)
        let availablePositions = CameraPosition.allCases.filter {
            !discoveredCameraDevicesOnQueue(for: $0).isEmpty
        }
        let options = makeLensOptionsOnQueue(for: device, position: position)
        currentLensOptions = options

        let selectedID: String?
        if let savedID = selectedLensIDs[position], options.contains(where: { $0.id == savedID }) {
            selectedID = savedID
        } else {
            selectedID = options.min(by: {
                abs($0.zoomFactor - device.videoZoomFactor)
                    < abs($1.zoomFactor - device.videoZoomFactor)
            })?.id
        }
        if let selectedID {
            selectedLensIDs[position] = selectedID
        }

        publishAvailableCameraPositions(availablePositions)
        publishAvailableLenses(options)
        publishCameraPosition(position)
        publishSelectedLensID(selectedID)
        publishZoomRange(
            minimum: device.minAvailableVideoZoomFactor,
            maximum: min(device.maxAvailableVideoZoomFactor, 6)
        )
        publishZoom(device.videoZoomFactor)
    }

    private func makeLensOptionsOnQueue(
        for device: AVCaptureDevice,
        position: CameraPosition
    ) -> [LensOption] {
        let devices: [AVCaptureDevice]
        let zoomFactors: [CGFloat]

        if device.isVirtualDevice, !device.constituentDevices.isEmpty {
            devices = device.constituentDevices
            let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map {
                CGFloat(truncating: $0)
            }
            zoomFactors = devices.indices.map { index in
                if index == 0 {
                    return device.minAvailableVideoZoomFactor
                }
                return switchOvers.indices.contains(index - 1)
                    ? switchOvers[index - 1]
                    : device.minAvailableVideoZoomFactor
            }
        } else {
            devices = discoveredCameraDevicesOnQueue(for: position)
            zoomFactors = Array(repeating: 1, count: devices.count)
        }

        var seenIDs = Set<String>()
        return devices.enumerated().compactMap { index, lensDevice in
            guard seenIDs.insert(lensDevice.uniqueID).inserted else { return nil }
            let zoomFactor = max(zoomFactors[index], 0.1)
            return LensOption(
                id: lensDevice.uniqueID,
                title: Self.lensTitle(for: lensDevice, zoomFactor: zoomFactor),
                detail: Self.lensDetail(for: lensDevice),
                zoomFactor: zoomFactor,
                position: position
            )
        }
    }

    private static func lensTitle(
        for device: AVCaptureDevice,
        zoomFactor: CGFloat
    ) -> String {
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return "0.5×"
        case .builtInWideAngleCamera:
            return "1×"
        default:
            return String(format: "%.1f×", zoomFactor)
        }
    }

    private static func lensDetail(for device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return "Ultra wide"
        case .builtInWideAngleCamera:
            return "Wide"
        case .builtInTelephotoCamera:
            return "Telephoto"
        case .builtInTrueDepthCamera:
            return "TrueDepth"
        default:
            return "Smart camera"
        }
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

    /// Resolves flash support from the two independent AVFoundation signals:
    /// physical flash hardware and the photo output's current configuration.
    /// Keeping this pure makes the Simulator/unsupported path deterministic
    /// and prevents an unsupported setting from reaching capturePhoto.
    static func resolveFlashAvailability(
        hasFlash: Bool,
        supportedModeRawValues: Set<Int>,
        flashAvailable: Bool
    ) -> FlashAvailability {
        guard hasFlash,
              supportedModeRawValues.contains(FlashMode.on.rawValue)
                || supportedModeRawValues.contains(FlashMode.auto.rawValue) else {
            return .unsupported
        }
        return flashAvailable ? .available : .temporarilyUnavailable
    }

    private func configureCaptureCapabilitiesOnQueue(for device: AVCaptureDevice) {
        refreshFlashCapabilitiesOnQueue(for: device)
        configureLowLightBoostOnQueue(for: device)
        refreshExposureBiasOnQueue(for: device)
    }

    private func refreshCaptureCapabilitiesOnQueue(for device: AVCaptureDevice) {
        refreshFlashCapabilitiesOnQueue(for: device)
        publishLowLightBoostState(
            supported: device.isLowLightBoostSupported,
            enabled: device.isLowLightBoostEnabled
        )
        refreshExposureBiasOnQueue(for: device)
    }

    private func refreshExposureBiasOnQueue(for device: AVCaptureDevice) {
        guard let bounds = Self.exposureBiasBounds(
            lowerBound: device.minExposureTargetBias,
            upperBound: device.maxExposureTargetBias
        ) else {
            selectedExposureBias = 0
            publishExposureBias(0)
            return
        }

        selectedExposureBias = Self.clampedExposureBias(
            Self.quantizedExposureBias(selectedExposureBias),
            lowerBound: bounds.lower,
            upperBound: bounds.upper
        )
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            applyExposureBiasOnQueue(to: device)
        } catch {
            // Exposure compensation is optional; keep the camera session
            // usable even when a device refuses configuration at startup.
        }
        publishExposureBias(selectedExposureBias)
    }

    private func applyExposureBiasOnQueue(to device: AVCaptureDevice) {
        guard device.isExposureModeSupported(.continuousAutoExposure)
                || device.isExposureModeSupported(.autoExpose) else {
            return
        }
        guard let bounds = Self.exposureBiasBounds(
            lowerBound: device.minExposureTargetBias,
            upperBound: device.maxExposureTargetBias
        ) else {
            return
        }
        let bias = Self.clampedExposureBias(
            Self.quantizedExposureBias(selectedExposureBias),
            lowerBound: bounds.lower,
            upperBound: bounds.upper
        )
        device.setExposureTargetBias(bias, completionHandler: nil)
    }

    private func refreshFlashCapabilitiesOnQueue(for device: AVCaptureDevice) {
        let supportedModes = supportedFlashModeRawValuesOnQueue()
        let availability = Self.resolveFlashAvailability(
            hasFlash: device.hasFlash,
            supportedModeRawValues: supportedModes,
            flashAvailable: device.isFlashAvailable
        )
        flashAvailabilityState = availability
        publishFlashAvailability(availability)

        if availability == .unsupported {
            selectedFlashMode = .off
            publishFlashMode(.off)
            photoOutput.photoSettingsForSceneMonitoring = nil
            return
        }

        if !supportedModes.contains(selectedFlashMode.rawValue) {
            selectedFlashMode = .off
            publishFlashMode(.off)
        }
        configureFlashSceneMonitoringOnQueue(supportedModes: supportedModes)
    }

    private func supportedFlashModeRawValuesOnQueue() -> Set<Int> {
        Set(photoOutput.supportedFlashModes.map(\.rawValue))
    }

    private func configureFlashSceneMonitoringOnQueue(supportedModes: Set<Int>) {
        guard flashAvailabilityState != .unsupported else {
            photoOutput.photoSettingsForSceneMonitoring = nil
            return
        }

        let monitoringMode: FlashMode
        if selectedFlashMode == .off {
            monitoringMode = .off
        } else if supportedModes.contains(selectedFlashMode.rawValue) {
            monitoringMode = selectedFlashMode
        } else if supportedModes.contains(FlashMode.auto.rawValue) {
            monitoringMode = .auto
        } else {
            monitoringMode = .on
        }

        let settings = AVCapturePhotoSettings()
        switch monitoringMode {
        case .off:
            settings.flashMode = .off
        case .auto:
            settings.flashMode = .auto
        case .on:
            settings.flashMode = .on
        }
        settings.photoQualityPrioritization = .balanced
        photoOutput.photoSettingsForSceneMonitoring = settings
    }

    private func configureLowLightBoostOnQueue(for device: AVCaptureDevice) {
        guard device.isLowLightBoostSupported else {
            publishLowLightBoostState(supported: false, enabled: false)
            return
        }

        do {
            try device.lockForConfiguration()
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
            let enabled = device.isLowLightBoostEnabled
            device.unlockForConfiguration()
            publishLowLightBoostState(supported: true, enabled: enabled)
        } catch {
            publishLowLightBoostState(
                supported: true,
                enabled: device.isLowLightBoostEnabled
            )
        }
    }

    private func setFlashModeOnQueue(_ mode: FlashMode) {
        if mode != .off, flashAvailabilityState != .available {
            if flashAvailabilityState == .temporarilyUnavailable {
                publishStatus("Flash is temporarily unavailable.")
            } else {
                publishStatus("Flash is unavailable on this camera.")
            }
            return
        }

        let supportedModes = supportedFlashModeRawValuesOnQueue()
        guard mode == .off || supportedModes.contains(mode.rawValue) else {
            publishStatus("That flash mode is unavailable on this camera.")
            return
        }

        selectedFlashMode = mode
        publishFlashMode(mode)
        if isConfigured {
            configureFlashSceneMonitoringOnQueue(supportedModes: supportedModes)
        }
    }

    private func resetCaptureCapabilitiesOnQueue() {
        flashAvailabilityState = .unsupported
        selectedFlashMode = .off
        publishFlashAvailability(.unsupported)
        publishFlashMode(.off)
        publishLowLightBoostState(supported: false, enabled: false)
        selectedExposureBias = 0
        publishExposureBias(0)
        photoOutput.photoSettingsForSceneMonitoring = nil
        currentLensOptions = []
        publishAvailableCameraPositions([])
        publishAvailableLenses([])
        publishSelectedLensID(nil)
        publishZoomRange(minimum: 1, maximum: 1)
        publishZoom(1)
        publishCameraPosition(.back)
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

        guard let device = activeDevice() else {
            publishStatus("The camera is unavailable right now.")
            publishPhoto(nil, completion: completion)
            return
        }

        refreshCaptureCapabilitiesOnQueue(for: device)
        let requestedFlashMode = selectedFlashMode
        let effectiveFlashMode: FlashMode
        if requestedFlashMode == .off || flashAvailabilityState == .available {
            effectiveFlashMode = requestedFlashMode
        } else {
            // A flash can become unavailable after configuration (most
            // commonly from thermal protection). Falling back to off keeps
            // capture safe and avoids asking AVCapturePhotoOutput for a mode
            // that cannot currently fire.
            effectiveFlashMode = .off
        }

        pendingPhotoCompletion = completion
        pendingPhotoCapturedAt = Date()
        pendingPhotoFlashFallback = requestedFlashMode != .off && effectiveFlashMode == .off
        let settings = AVCapturePhotoSettings()
        switch effectiveFlashMode {
        case .off:
            settings.flashMode = .off
        case .auto:
            settings.flashMode = .auto
        case .on:
            settings.flashMode = .on
        }
        settings.photoQualityPrioritization = .quality
        if configuredPhotoDimensions.width > 0, configuredPhotoDimensions.height > 0 {
            settings.maxPhotoDimensions = configuredPhotoDimensions
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishPhotoOnQueue(_ photo: CapturedPhoto?) {
        let completion = pendingPhotoCompletion
        let flashFallback = pendingPhotoFlashFallback
        pendingPhotoCompletion = nil
        pendingPhotoCapturedAt = nil
        pendingPhotoFlashFallback = false
        guard let completion else { return }

        if photo == nil {
            publishStatus("The photo could not be processed.")
        } else if flashFallback {
            publishStatus("Photo captured without flash — flash is temporarily unavailable.")
        } else {
            publishStatus("Photo captured")
        }
        publishPhoto(photo, completion: completion)
    }

    private func cancelPendingPhotoOnQueue(status: String) {
        guard let completion = pendingPhotoCompletion else { return }
        pendingPhotoCompletion = nil
        pendingPhotoCapturedAt = nil
        pendingPhotoFlashFallback = false
        publishStatus(status)
        publishPhoto(nil, completion: completion)
    }

    private func publishRunning(_ running: Bool) {
        publishOnMain { [weak self] in
            self?.isRunning = running
        }
    }

    private func publishAvailability(_ availability: Availability) {
        sessionAvailability = availability
        publishOnMain { [weak self] in
            self?.availability = availability
        }
    }

    private func publishFlashMode(_ mode: FlashMode) {
        publishOnMain { [weak self] in
            self?.flashMode = mode
        }
    }

    private func publishFlashAvailability(_ availability: FlashAvailability) {
        publishOnMain { [weak self] in
            self?.flashAvailability = availability
        }
    }

    private func publishLowLightBoostState(supported: Bool, enabled: Bool) {
        publishOnMain { [weak self] in
            self?.lowLightBoostSupported = supported
            self?.isLowLightBoostEnabled = enabled
        }
    }

    private func publishZoom(_ factor: CGFloat) {
        publishOnMain { [weak self] in
            self?.zoomFactor = factor
        }
    }

    private func publishZoomRange(minimum: CGFloat, maximum: CGFloat) {
        let safeMinimum = minimum.isFinite ? max(minimum, 1) : 1
        let safeMaximum = maximum.isFinite ? max(maximum, safeMinimum) : safeMinimum
        publishOnMain { [weak self] in
            self?.minZoomFactor = safeMinimum
            self?.maxZoomFactor = safeMaximum
        }
    }

    private func publishCameraPosition(_ position: CameraPosition) {
        publishOnMain { [weak self] in
            self?.cameraPosition = position
        }
    }

    private func publishAvailableCameraPositions(_ positions: [CameraPosition]) {
        publishOnMain { [weak self] in
            self?.availableCameraPositions = positions
        }
    }

    private func publishAvailableLenses(_ lenses: [LensOption]) {
        publishOnMain { [weak self] in
            self?.availableLenses = lenses
        }
    }

    private func publishSelectedLensID(_ id: String?) {
        publishOnMain { [weak self] in
            self?.selectedLensID = id
        }
    }

    private func publishExposureBias(_ bias: Float) {
        publishOnMain { [weak self] in
            self?.exposureBias = bias
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
