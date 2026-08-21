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

    /// Returns the constituent index that AVFoundation should be using for a
    /// virtual device at the supplied zoom. An active constituent wins when
    /// the hardware reports one; the switch-over thresholds are the fallback
    /// because the active device can be temporarily unavailable during a
    /// configuration transaction.
    static func selectedVirtualLensIndex(
        zoomFactor: CGFloat,
        switchOverZoomFactors: [CGFloat],
        constituentCount: Int,
        activeConstituentIndex: Int? = nil
    ) -> Int? {
        guard constituentCount > 0 else { return nil }
        if let activeConstituentIndex,
           (0..<constituentCount).contains(activeConstituentIndex) {
            return activeConstituentIndex
        }
        guard zoomFactor.isFinite else { return nil }

        var selectedIndex = 0
        for index in 1..<constituentCount {
            guard switchOverZoomFactors.indices.contains(index - 1) else { break }
            let switchOver = switchOverZoomFactors[index - 1]
            guard switchOver.isFinite else { break }
            if zoomFactor >= switchOver {
                selectedIndex = index
            }
        }
        return selectedIndex
    }

    /// Estimates the optical magnification of a standalone lens from its
    /// field of view relative to the standard wide camera. FOV is angular,
    /// so the tangent ratio is a closer approximation than a raw degree
    /// ratio, especially for ultra-wide lenses.
    static func standaloneLensMagnification(
        wideFieldOfView: Float,
        lensFieldOfView: Float
    ) -> CGFloat? {
        guard wideFieldOfView.isFinite,
              lensFieldOfView.isFinite,
              wideFieldOfView > 0,
              lensFieldOfView > 0,
              wideFieldOfView < 180,
              lensFieldOfView < 180 else {
            return nil
        }

        let wideTangent = tan(Double(wideFieldOfView) * .pi / 360)
        let lensTangent = tan(Double(lensFieldOfView) * .pi / 360)
        let magnification = wideTangent / lensTangent
        guard magnification.isFinite, magnification > 0 else { return nil }
        return CGFloat(magnification)
    }

    /// Converts AVFoundation's virtual-device zoom into the user-facing scale
    /// whose 1× anchor is the standard wide constituent.
    static func normalizedUserZoomFactor(
        hardwareZoomFactor: CGFloat,
        wideReferenceHardwareZoomFactor: CGFloat
    ) -> CGFloat {
        guard hardwareZoomFactor.isFinite else { return 1 }
        guard wideReferenceHardwareZoomFactor.isFinite,
              wideReferenceHardwareZoomFactor > 0 else {
            return hardwareZoomFactor
        }
        return hardwareZoomFactor / wideReferenceHardwareZoomFactor
    }

    /// Converts a standalone camera's device-local zoom into the total
    /// user-facing magnification relative to the standard wide camera.
    static func standaloneUserFacingZoomFactor(
        hardwareZoomFactor: CGFloat,
        opticalMagnification: CGFloat
    ) -> CGFloat {
        guard hardwareZoomFactor.isFinite,
              opticalMagnification.isFinite,
              opticalMagnification > 0 else {
            return hardwareZoomFactor.isFinite ? hardwareZoomFactor : 1
        }
        return hardwareZoomFactor * opticalMagnification
    }

    /// Converts a total user-facing magnification into the device-local zoom
    /// needed by a standalone camera while retaining its optical scale.
    static func standaloneHardwareZoomFactor(
        userFacingZoomFactor: CGFloat,
        opticalMagnification: CGFloat
    ) -> CGFloat {
        guard userFacingZoomFactor.isFinite,
              opticalMagnification.isFinite,
              opticalMagnification > 0 else {
            return userFacingZoomFactor
        }
        return userFacingZoomFactor / opticalMagnification
    }

    static func shouldRestoreStandaloneLens(
        origin: LensSelectionOrigin?
    ) -> Bool {
        origin == .standalone
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

    /// The grain phase used by both the live preview and the still renderer
    /// for the current camera session. A session-scoped phase keeps the
    /// preview and captured frame visually aligned without repeating the same
    /// phase across app launches.
    public let previewGrainSeed: UInt32

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
    @Published public private(set) var previewRotationAngle: CGFloat = 90
    @Published public private(set) var previewMirrored = false

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
    private var pendingPhotoUniqueID: Int64?
    private var configuredPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
    private var focusExposureLocked = false
    private var requestedCameraPosition: CameraPosition = .back
    private var currentLensOptions: [LensOption] = []
    private var selectedLensIDs: [CameraPosition: String] = [:]
    private var selectedLensOrigins: [CameraPosition: LensSelectionOrigin] = [:]
    private var selectedFlashMode: FlashMode = .off
    private var selectedExposureBias: Float = 0
    private var flashAvailabilityState: FlashAvailability = .unsupported
    private var pendingPhotoFlashFallback = false
    private var sessionObservers: [NSObjectProtocol] = []
    private var activeConstituentObservation: NSKeyValueObservation?
    private var observedVirtualDeviceID: String?
    private var previewRotationAngleState: CGFloat = 90
    private var captureRotationAngleState: CGFloat = 90
    private var rotationCoordinatorToken = UUID()
    private var rotationCoordinatorDeviceID: String?
    private var activeRotationToken: UUID?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?
    private weak var rotationPreviewLayer: CALayer?
    private var rotationPreviewLayerID: UUID?
    private var rotationDevice: AVCaptureDevice?
    private var lastDeliveredFrameSize: CGSize = .zero

    /// Identifies whether a saved lens ID belongs to a virtual input's
    /// constituent inventory or to a standalone physical input. A constituent
    /// can also appear in discovery as a physical device, so the ID alone is
    /// not enough to safely restore a session input.
    enum LensSelectionOrigin: Equatable {
        case virtual
        case standalone
    }

    private final class PhotoCompletionBox: @unchecked Sendable {
        let completion: PhotoCompletion

        init(_ completion: @escaping PhotoCompletion) {
            self.completion = completion
        }
    }

    private final class CaptureDeviceBox: @unchecked Sendable {
        let device: AVCaptureDevice

        init(_ device: AVCaptureDevice) {
            self.device = device
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
        self.previewGrainSeed = UInt32.random(in: UInt32.min...UInt32.max)
        super.init()

        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
        frameDeliveryGate.owner = self
        videoOutput.alwaysDiscardsLateVideoFrames = true
        let previewPixelFormat = Self.preferredPreviewPixelFormat(
            available: videoOutput.availableVideoPixelFormatTypes
        )
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: previewPixelFormat
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        installSessionObservers()
    }

    deinit {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        activeConstituentObservation?.invalidate()
        activeConstituentObservation = nil
        previewRotationObservation?.invalidate()
        captureRotationObservation?.invalidate()
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
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
            self.pendingPhotoUniqueID = nil
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

    /// Registers the CALayer used by the custom Metal preview. Ownership is
    /// tokenized so dismantling an older SwiftUI representable cannot detach a
    /// newer preview layer from the active rotation coordinator.
    @MainActor
    @discardableResult
    public func installPreviewLayer(_ layer: CALayer) -> UUID {
        let id = UUID()
        rotationPreviewLayerID = id
        rotationPreviewLayer = layer
        if let rotationDevice, let activeRotationToken {
            installRotationCoordinatorOnMain(
                for: rotationDevice,
                token: activeRotationToken
            )
        }
        return id
    }

    @MainActor
    public func removePreviewLayer(_ id: UUID) {
        guard rotationPreviewLayerID == id else { return }
        rotationPreviewLayerID = nil
        rotationPreviewLayer = nil
        if let rotationDevice, let activeRotationToken {
            installRotationCoordinatorOnMain(
                for: rotationDevice,
                token: activeRotationToken
            )
        }
    }

    /// Keeps the preview and still output aligned with the current camera
    /// surface when the phone rotates or enters a split-screen layout.
    @MainActor
    public func updateOrientation(for viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        publishPreviewViewportSize(viewSize)
        let activeWindowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        let interfaceOrientation: UIInterfaceOrientation?
        if #available(iOS 26.0, *) {
            interfaceOrientation = activeWindowScene?.effectiveGeometry.interfaceOrientation
        } else {
            interfaceOrientation = activeWindowScene?.interfaceOrientation
        }
        let fallbackAngle = Self.videoRotationAngle(
            for: interfaceOrientation,
            fallbackViewSize: viewSize
        )

        // RotationCoordinator owns physical-camera angles once an input is
        // installed. The interface-orientation mapping remains only as a safe
        // simulator and preconfiguration fallback.
        sessionQueue.async { [weak self] in
            guard let self,
                  self.rotationCoordinatorDeviceID == nil,
                  self.previewRotationAngleState != fallbackAngle
                    || self.captureRotationAngleState != fallbackAngle else {
                return
            }
            self.previewRotationAngleState = fallbackAngle
            self.captureRotationAngleState = fallbackAngle
            self.configureOrientation()
            self.publishPreviewRotationAngle(fallbackAngle)
        }
    }

    static func videoRotationAngle(
        for interfaceOrientation: UIInterfaceOrientation?,
        fallbackViewSize: CGSize
    ) -> CGFloat {
        switch interfaceOrientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .unknown, .none:
            fallbackViewSize.width > fallbackViewSize.height ? 0 : 90
        @unknown default:
            fallbackViewSize.width > fallbackViewSize.height ? 0 : 90
        }
    }

    /// Converts a point in the physically rotated and optionally mirrored
    /// preview buffer back into the unrotated capture-device coordinate space
    /// required by focusPointOfInterest and exposurePointOfInterest.
    static func captureDevicePoint(
        fromRotatedPreviewPoint point: CGPoint,
        rotationAngle: CGFloat,
        mirrored: Bool
    ) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        var previewX = min(max(point.x, 0), 1)
        let previewY = min(max(point.y, 0), 1)
        if mirrored {
            previewX = 1 - previewX
        }

        let finiteAngle = rotationAngle.isFinite ? rotationAngle : 0
        let normalizedAngle = (finiteAngle.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let quarterTurns = Int((normalizedAngle / 90).rounded()) % 4

        let devicePoint: CGPoint
        switch quarterTurns {
        case 1:
            devicePoint = CGPoint(x: previewY, y: 1 - previewX)
        case 2:
            devicePoint = CGPoint(x: 1 - previewX, y: 1 - previewY)
        case 3:
            devicePoint = CGPoint(x: 1 - previewY, y: previewX)
        default:
            devicePoint = CGPoint(x: previewX, y: previewY)
        }

        return CGPoint(
            x: min(max(devicePoint.x, 0), 1),
            y: min(max(devicePoint.y, 0), 1)
        )
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

                let focusMode = Self.preferredFocusLockMode(
                    supportsAutoFocus: device.isFocusModeSupported(.autoFocus),
                    supportsLocked: device.isFocusModeSupported(.locked)
                )
                let exposureMode = Self.preferredExposureLockMode(
                    supportsAutoExpose: device.isExposureModeSupported(.autoExpose),
                    supportsLocked: device.isExposureModeSupported(.locked)
                )
                guard focusMode != nil || exposureMode != nil else {
                    self.publishStatus("Focus lock is unavailable right now.")
                    return
                }

                // One-shot autofocus and autoexposure meter at the selected
                // point before AVFoundation transitions them to locked. A
                // direct `.locked` assignment would freeze the preexisting
                // lens and exposure state, potentially before the tap-driven
                // adjustment has completed.
                if let focusMode {
                    device.focusMode = focusMode
                }
                if let exposureMode {
                    device.exposureMode = exposureMode
                    self.applyExposureBiasOnQueue(to: device)
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

    /// A point-based lock should meter once before freezing the lens. Prefer
    /// `.autoFocus`, which performs one adjustment and then locks, while
    /// retaining `.locked` as a fallback for devices with narrower support.
    static func preferredFocusLockMode(
        supportsAutoFocus: Bool,
        supportsLocked: Bool
    ) -> AVCaptureDevice.FocusMode? {
        if supportsAutoFocus { return .autoFocus }
        if supportsLocked { return .locked }
        return nil
    }

    /// A point-based exposure lock should meter once before freezing exposure.
    /// Prefer `.autoExpose`, which performs one adjustment and then locks,
    /// while retaining `.locked` as a fallback for unusual capture devices.
    static func preferredExposureLockMode(
        supportsAutoExpose: Bool,
        supportsLocked: Bool
    ) -> AVCaptureDevice.ExposureMode? {
        if supportsAutoExpose { return .autoExpose }
        if supportsLocked { return .locked }
        return nil
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

        guard let device = cameraDeviceForPositionOnQueue(requestedCameraPosition) else {
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

        installRotationCoordinatorOnQueue(for: device)
        configureCaptureCapabilitiesOnQueue(for: device)
        configureStartupLensOnQueue(for: device)
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

    private func installRotationCoordinatorOnQueue(for device: AVCaptureDevice) {
        let token = UUID()
        rotationCoordinatorToken = token
        rotationCoordinatorDeviceID = device.uniqueID
        let deviceBox = CaptureDeviceBox(device)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.installRotationCoordinatorOnMain(
                for: deviceBox.device,
                token: token
            )
        }
    }

    @MainActor
    private func installRotationCoordinatorOnMain(
        for device: AVCaptureDevice,
        token: UUID
    ) {
        activeRotationToken = token
        rotationDevice = device
        previewRotationObservation?.invalidate()
        captureRotationObservation?.invalidate()

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: rotationPreviewLayer
        )
        rotationCoordinator = coordinator

        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, change in
            let angle = change.newValue
                ?? coordinator.videoRotationAngleForHorizonLevelPreview
            MainActor.assumeIsolated {
                self?.applyPreviewRotationOnMain(angle, token: token)
            }
        }

        captureRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self] coordinator, change in
            let angle = change.newValue
                ?? coordinator.videoRotationAngleForHorizonLevelCapture
            MainActor.assumeIsolated {
                self?.applyCaptureRotationOnMain(angle, token: token)
            }
        }
    }

    @MainActor
    private func applyPreviewRotationOnMain(_ angle: CGFloat, token: UUID) {
        guard activeRotationToken == token, angle.isFinite else { return }
        publishPreviewRotationAngle(angle)
        sessionQueue.async { [weak self] in
            guard let self, self.rotationCoordinatorToken == token else { return }
            self.previewRotationAngleState = angle
            self.configureOrientation()
        }
    }

    @MainActor
    private func applyCaptureRotationOnMain(_ angle: CGFloat, token: UUID) {
        guard activeRotationToken == token, angle.isFinite else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.rotationCoordinatorToken == token else { return }
            self.captureRotationAngleState = angle
            self.configureOrientation()
        }
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
                    self.cancelPendingPhotoOnQueue(status: "Camera temporarily unavailable.")
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
            cancelPendingPhotoOnQueue(
                status: running
                    ? "Capture was interrupted. Try again."
                    : "Camera needs to be reopened."
            )
            return
        }

        publishRunning(false)
        publishAvailability(.needsRecovery)
        publishStatus("Camera needs to be reopened.")
        cancelPendingPhotoOnQueue(status: "Camera needs to be reopened.")
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
        let devices = discoveredCameraDevicesOnQueue(for: position)
        guard position == .back else { return devices.first }

        // Prefer the system's virtual back camera when it exposes the normal
        // wide constituent. A discovery session can otherwise return an
        // ultra-wide device first, which changes the app's established 1×
        // startup experience.
        let preferredVirtualTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera
        ]
        for deviceType in preferredVirtualTypes {
            if let virtualDevice = devices.first(where: {
                $0.deviceType == deviceType
                    && $0.constituentDevices.contains {
                        $0.deviceType == .builtInWideAngleCamera
                    }
            }) {
                return virtualDevice
            }
        }

        return devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? devices.first
    }

    /// Restores a previously selected standalone device only when that exact
    /// device is about to become the session input. Virtual-device constituent
    /// IDs are handled after the virtual input is active via its zoom state.
    private func cameraDeviceForPositionOnQueue(
        _ position: CameraPosition
    ) -> AVCaptureDevice? {
        let devices = discoveredCameraDevicesOnQueue(for: position)
        if Self.shouldRestoreStandaloneLens(origin: selectedLensOrigins[position]),
           let savedID = selectedLensIDs[position],
           let savedDevice = devices.first(where: { $0.uniqueID == savedID }),
           !savedDevice.isVirtualDevice {
            return savedDevice
        }
        return preferredCameraDeviceOnQueue(for: position)
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
        guard let desiredDevice = cameraDeviceForPositionOnQueue(position) else {
            publishStatus("Camera switching is available on iPhone.")
            publishAvailableCameraPositions([])
            return
        }

        guard isConfigured else {
            requestedCameraPosition = position
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

        // Commit the requested position only after the replacement input is
        // installed. A failed swap must leave toggleCameraPosition pointed at
        // the still-active camera.
        requestedCameraPosition = position
        focusExposureLocked = false
        publishFocusExposureLocked(false)
        publishCameraPosition(position)
        configureCaptureCapabilitiesOnQueue(for: desiredDevice)
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

        if device.isVirtualDevice {
            // setZoomOnQueue publishes the active constituent selected by
            // AVFoundation (or by its switch-over thresholds), not merely
            // the option the user requested.
            _ = setHardwareZoomOnQueue(option.zoomFactor)
            return
        }

        if option.id == device.uniqueID {
            // Reapply the advertised optical magnification through the
            // user-facing conversion so a reselected standalone lens clears
            // any digital zoom accumulated on that input.
            guard setZoomOnQueue(option.zoomFactor) else { return }
            selectedLensIDs[position] = device.uniqueID
            selectedLensOrigins[position] = .standalone
            publishSelectedLensID(option.id)
            return
        }

        guard let alternateDevice = discoveredCameraDevicesOnQueue(for: position)
            .first(where: { $0.uniqueID == option.id }) else {
            publishStatus("That lens is unavailable right now.")
            return
        }

        guard replaceCameraInputOnQueue(with: alternateDevice) else {
            publishStatus("That lens is unavailable right now.")
            return
        }

        focusExposureLocked = false
        publishFocusExposureLocked(false)
        configureCaptureCapabilitiesOnQueue(for: alternateDevice)
        refreshCameraInventoryOnQueue(for: alternateDevice)
        configurePreviewFrameRate(for: alternateDevice)
        publishStatus("\(option.title) lens ready")
    }

    @discardableResult
    private func setZoomOnQueue(_ factor: CGFloat) -> Bool {
        guard let device = activeDevice() else { return false }
        let hardwareFactor = hardwareZoomFactorOnQueue(
            for: device,
            userFacingFactor: factor
        )
        return setHardwareZoomOnQueue(hardwareFactor)
    }

    @discardableResult
    private func setHardwareZoomOnQueue(_ factor: CGFloat) -> Bool {
        guard let device = activeDevice() else { return false }
        let lowerBound = device.minAvailableVideoZoomFactor
        let upperBound = min(device.maxAvailableVideoZoomFactor, 6)
        let nextFactor = min(max(factor, lowerBound), max(lowerBound, upperBound))
        guard nextFactor.isFinite else { return false }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = nextFactor
            device.unlockForConfiguration()
            let userFacingFactor = userFacingZoomFactorOnQueue(
                for: device,
                hardwareFactor: nextFactor
            )
            publishZoomRange(
                minimum: userFacingZoomFactorOnQueue(
                    for: device,
                    hardwareFactor: lowerBound
                ),
                maximum: userFacingZoomFactorOnQueue(
                    for: device,
                    hardwareFactor: max(lowerBound, upperBound)
                )
            )
            publishZoom(userFacingFactor)
            if let selectedID = activeLensOptionIDOnQueue(for: device, options: currentLensOptions) {
                let position = cameraPosition(for: device)
                selectedLensIDs[position] = selectedID
                selectedLensOrigins[position] = device.isVirtualDevice
                    ? .virtual
                    : .standalone
                publishSelectedLensID(selectedID)
            }
            return true
        } catch {
            publishStatus("Zoom is unavailable right now.")
            return false
        }
    }

    private func hardwareZoomFactorOnQueue(
        for device: AVCaptureDevice,
        userFacingFactor: CGFloat
    ) -> CGFloat {
        guard !device.isVirtualDevice else {
            let reference = wideReferenceZoomFactorOnQueue(for: device)
            guard userFacingFactor.isFinite, reference.isFinite else {
                return userFacingFactor
            }
            return userFacingFactor * reference
        }

        return Self.standaloneHardwareZoomFactor(
            userFacingZoomFactor: userFacingFactor,
            opticalMagnification: standaloneOpticalMagnificationOnQueue(for: device)
        )
    }

    private func standaloneOpticalMagnificationOnQueue(
        for device: AVCaptureDevice
    ) -> CGFloat {
        guard !device.isVirtualDevice else { return 1 }

        if let option = currentLensOptions.first(where: { $0.id == device.uniqueID }),
           option.zoomFactor.isFinite,
           option.zoomFactor > 0 {
            return option.zoomFactor
        }

        let wideDevice = discoveredCameraDevicesOnQueue(for: cameraPosition(for: device))
            .first(where: { $0.deviceType == .builtInWideAngleCamera })
        return Self.standaloneLensMagnification(
            wideFieldOfView: wideDevice?.activeFormat.videoFieldOfView ?? 0,
            lensFieldOfView: device.activeFormat.videoFieldOfView
        ) ?? Self.standaloneFallbackZoomFactor(for: device)
    }

    private func userFacingZoomFactorOnQueue(
        for device: AVCaptureDevice,
        hardwareFactor: CGFloat
    ) -> CGFloat {
        guard device.isVirtualDevice else {
            return Self.standaloneUserFacingZoomFactor(
                hardwareZoomFactor: hardwareFactor,
                opticalMagnification: standaloneOpticalMagnificationOnQueue(for: device)
            )
        }

        return Self.normalizedUserZoomFactor(
            hardwareZoomFactor: hardwareFactor,
            wideReferenceHardwareZoomFactor: wideReferenceZoomFactorOnQueue(for: device)
        )
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
        installRotationCoordinatorOnQueue(for: device)
        return true
    }

    private func configureStartupLensOnQueue(for device: AVCaptureDevice) {
        guard device.isVirtualDevice else { return }
        let startupZoom = wideReferenceZoomFactorOnQueue(for: device)

        // The virtual device's first constituent can be ultra-wide. Set the
        // hardware to the wide constituent before inventory is published so
        // the first frame and the lens control both start at 1×.
        _ = setHardwareZoomOnQueue(startupZoom)
    }

    private func wideReferenceZoomFactorOnQueue(
        for device: AVCaptureDevice
    ) -> CGFloat {
        guard device.isVirtualDevice,
              let wideIndex = device.constituentDevices.firstIndex(where: {
                  $0.deviceType == .builtInWideAngleCamera
              }) else {
            return 1
        }

        if wideIndex == 0 {
            return max(device.minAvailableVideoZoomFactor, 0.1)
        }

        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map {
            CGFloat(truncating: $0)
        }
        guard switchOvers.indices.contains(wideIndex - 1) else { return 1 }
        return max(switchOvers[wideIndex - 1], device.minAvailableVideoZoomFactor)
    }

    private func activeLensOptionIDOnQueue(
        for device: AVCaptureDevice,
        options: [LensOption]
    ) -> String? {
        guard !options.isEmpty else { return nil }

        if device.isVirtualDevice {
            if let activeConstituent = device.activePrimaryConstituent,
               let activeOption = options.first(where: {
                   $0.id == activeConstituent.uniqueID
               }) {
                return activeOption.id
            }

            let activeIndex = device.constituentDevices.firstIndex {
                $0.uniqueID == device.activePrimaryConstituent?.uniqueID
            }
            let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map {
                CGFloat(truncating: $0)
            }
            guard let selectedIndex = Self.selectedVirtualLensIndex(
                zoomFactor: device.videoZoomFactor,
                switchOverZoomFactors: switchOvers,
                constituentCount: device.constituentDevices.count,
                activeConstituentIndex: activeIndex
            ),
            device.constituentDevices.indices.contains(selectedIndex) else {
                return nil
            }
            let selectedID = device.constituentDevices[selectedIndex].uniqueID
            return options.first(where: { $0.id == selectedID })?.id
        }

        return options.first(where: { $0.id == device.uniqueID })?.id
    }

    private func updateActiveConstituentObservationOnQueue(
        for device: AVCaptureDevice
    ) {
        guard device.isVirtualDevice else {
            activeConstituentObservation?.invalidate()
            activeConstituentObservation = nil
            observedVirtualDeviceID = nil
            return
        }

        guard observedVirtualDeviceID != device.uniqueID else { return }

        activeConstituentObservation?.invalidate()
        observedVirtualDeviceID = device.uniqueID
        let deviceID = device.uniqueID
        activeConstituentObservation = device.observe(
            \AVCaptureDevice.activePrimaryConstituent,
            options: [.new]
        ) { [weak self] _, _ in
            self?.sessionQueue.async { [weak self] in
                guard let self,
                      let activeDevice = self.activeDevice(),
                      activeDevice.isVirtualDevice,
                      activeDevice.uniqueID == deviceID else { return }
                self.refreshActiveLensSelectionOnQueue(for: activeDevice)
            }
        }
    }

    private func refreshActiveLensSelectionOnQueue(for device: AVCaptureDevice) {
        let position = cameraPosition(for: device)
        let selectedID = activeLensOptionIDOnQueue(
            for: device,
            options: currentLensOptions
        )
        if let selectedID {
            selectedLensIDs[position] = selectedID
            selectedLensOrigins[position] = .virtual
        }
        publishSelectedLensID(selectedID)
    }

    private func refreshCameraInventoryOnQueue(for device: AVCaptureDevice) {
        let position = cameraPosition(for: device)
        let availablePositions = CameraPosition.allCases.filter {
            !discoveredCameraDevicesOnQueue(for: $0).isEmpty
        }
        let options = makeLensOptionsOnQueue(for: device, position: position)
        currentLensOptions = options
        updateActiveConstituentObservationOnQueue(for: device)

        // Never restore a saved ID merely because it is present in the
        // inventory. The active input/constituent is the source of truth;
        // this prevents a saved rear telephoto from being shown while the
        // session is actually using the rear wide camera.
        let selectedID = activeLensOptionIDOnQueue(for: device, options: options)
        if let selectedID {
            selectedLensIDs[position] = selectedID
            selectedLensOrigins[position] = device.isVirtualDevice
                ? .virtual
                : .standalone
        }

        publishAvailableCameraPositions(availablePositions)
        publishAvailableLenses(options)
        publishCameraPosition(position)
        publishSelectedLensID(selectedID)
        publishZoomRange(
            minimum: userFacingZoomFactorOnQueue(
                for: device,
                hardwareFactor: device.minAvailableVideoZoomFactor
            ),
            maximum: userFacingZoomFactorOnQueue(
                for: device,
                hardwareFactor: min(device.maxAvailableVideoZoomFactor, 6)
            )
        )
        publishZoom(
            userFacingZoomFactorOnQueue(
                for: device,
                hardwareFactor: device.videoZoomFactor
            )
        )
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
            let wideDevice = devices.first(where: {
                $0.deviceType == .builtInWideAngleCamera
            })
            zoomFactors = devices.map { lensDevice in
                Self.standaloneLensMagnification(
                    wideFieldOfView: wideDevice?.activeFormat.videoFieldOfView ?? 0,
                    lensFieldOfView: lensDevice.activeFormat.videoFieldOfView
                ) ?? Self.standaloneFallbackZoomFactor(for: lensDevice)
            }
        }

        var seenIDs = Set<String>()
        return devices.enumerated().compactMap { index, lensDevice in
            guard seenIDs.insert(lensDevice.uniqueID).inserted else { return nil }
            let zoomFactor = max(zoomFactors[index], 0.1)
            let titleZoomFactor = device.isVirtualDevice
                ? Self.normalizedUserZoomFactor(
                    hardwareZoomFactor: zoomFactor,
                    wideReferenceHardwareZoomFactor: wideReferenceZoomFactorOnQueue(for: device)
                )
                : zoomFactor
            return LensOption(
                id: lensDevice.uniqueID,
                title: Self.lensTitle(for: lensDevice, zoomFactor: titleZoomFactor),
                detail: Self.lensDetail(for: lensDevice),
                zoomFactor: zoomFactor,
                position: position
            )
        }
    }

    private static func standaloneFallbackZoomFactor(
        for device: AVCaptureDevice
    ) -> CGFloat {
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return 0.5
        case .builtInWideAngleCamera:
            return 1
        default:
            return 1
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
        case .builtInTelephotoCamera:
            guard zoomFactor > 1.05 else { return "Tele" }
            return String(format: "%.1f×", zoomFactor)
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
        let previewConnection = videoOutput.connection(with: .video)
        configureRotation(
            previewConnection,
            angle: previewRotationAngleState
        )
        configureRotation(
            photoOutput.connection(with: .video),
            angle: captureRotationAngleState
        )
        publishPreviewMirroring(previewConnection?.isVideoMirrored ?? false)
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
        publishPreviewMirroring(false)
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
        pendingPhotoCompletion = completion
        pendingPhotoCapturedAt = Date()
        pendingPhotoUniqueID = settings.uniqueID
        pendingPhotoFlashFallback = requestedFlashMode != .off && effectiveFlashMode == .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishPhotoOnQueue(_ photo: CapturedPhoto?, uniqueID: Int64) {
        guard Self.acceptsPhotoCallback(
            pendingUniqueID: pendingPhotoUniqueID,
            callbackUniqueID: uniqueID
        ) else {
            // AVCapturePhotoOutput may deliver a late callback after a
            // cancellation or interruption. Never let it consume state for a
            // newer request.
            return
        }

        let completion = pendingPhotoCompletion
        let flashFallback = pendingPhotoFlashFallback
        pendingPhotoCompletion = nil
        pendingPhotoCapturedAt = nil
        pendingPhotoUniqueID = nil
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
        pendingPhotoUniqueID = nil
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
        let safeMinimum = minimum.isFinite ? max(minimum, 0.1) : 1
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

    private func publishPreviewRotationAngle(_ angle: CGFloat) {
        publishOnMain { [weak self] in
            self?.previewRotationAngle = angle
        }
    }

    private func publishPreviewMirroring(_ mirrored: Bool) {
        publishOnMain { [weak self] in
            self?.previewMirrored = mirrored
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
        guard point.x.isFinite, point.y.isFinite else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    /// Prefer the camera's native bi-planar YUV video buffers. They avoid an
    /// intermediate BGRA conversion on physical devices while retaining a
    /// BGRA fallback for older hardware and simulator implementations.
    static func preferredPreviewPixelFormat(available: [OSType]) -> OSType {
        if available.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
        if available.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            return kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        return kCVPixelFormatType_32BGRA
    }

    static func acceptsPhotoCallback(
        pendingUniqueID: Int64?,
        callbackUniqueID: Int64
    ) -> Bool {
        pendingUniqueID == callbackUniqueID
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
        let uniqueID = photo.resolvedSettings.uniqueID

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
            self.finishPhotoOnQueue(capturedPhoto, uniqueID: uniqueID)
        }
    }
}
