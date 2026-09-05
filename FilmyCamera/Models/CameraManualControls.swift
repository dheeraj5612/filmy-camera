import Foundation

/// The applied sensor state and capability bounds for the active camera.
///
/// Values in this snapshot come from `AVCaptureDevice`; setting a control is
/// asynchronous, and the snapshot changes only after the device accepts the
/// request. Unsupported hardware therefore never presents simulated manual
/// state to the UI.
public struct CameraManualControls: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case auto
        case manual
    }

    /// A standalone physical camera that can be selected when the system's
    /// virtual multi-camera input does not expose manual sensor controls.
    public struct PhysicalLensOption: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
        public let supportsManualExposure: Bool
        public let supportsManualWhiteBalance: Bool
        public let supportsManualFocus: Bool
        public let isActive: Bool

        public init(
            id: String,
            title: String,
            detail: String,
            supportsManualExposure: Bool,
            supportsManualWhiteBalance: Bool,
            supportsManualFocus: Bool,
            isActive: Bool
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.supportsManualExposure = supportsManualExposure
            self.supportsManualWhiteBalance = supportsManualWhiteBalance
            self.supportsManualFocus = supportsManualFocus
            self.isActive = isActive
        }

        public var supportsAnyManualControl: Bool {
            supportsManualExposure || supportsManualWhiteBalance || supportsManualFocus
        }
    }

    public let activeDeviceID: String?
    public let activeDeviceName: String
    public let isVirtualDevice: Bool

    public let exposureMode: Mode
    public let manualExposureSupported: Bool
    public let iso: Float
    public let minimumISO: Float
    public let maximumISO: Float
    public let exposureDurationSeconds: Double
    public let minimumExposureDurationSeconds: Double
    public let maximumExposureDurationSeconds: Double

    public let whiteBalanceMode: Mode
    public let manualWhiteBalanceSupported: Bool
    public let kelvin: Float
    public let tint: Float
    public let minimumKelvin: Float
    public let maximumKelvin: Float
    public let minimumTint: Float
    public let maximumTint: Float

    public let focusMode: Mode
    public let manualFocusSupported: Bool
    public let lensPosition: Float
    public let minimumLensPosition: Float
    public let maximumLensPosition: Float

    public let physicalLensOptions: [PhysicalLensOption]
    public let requiresPhysicalLensSelection: Bool
    /// True while AVFoundation is applying an asynchronous sensor request.
    /// Capture controls should remain disabled until this becomes false.
    public let isApplying: Bool
    /// Filmy Camera keeps still flash off during manual exposure so the saved
    /// frame consistently honors the selected ISO and shutter duration.
    public let flashRequiresAutoExposure: Bool

    public var isAnyManualModeEnabled: Bool {
        exposureMode == .manual || whiteBalanceMode == .manual || focusMode == .manual
    }

    public static let unavailable = CameraManualControls(
        activeDeviceID: nil,
        activeDeviceName: "Unavailable",
        isVirtualDevice: false,
        exposureMode: .auto,
        manualExposureSupported: false,
        iso: 0,
        minimumISO: 0,
        maximumISO: 0,
        exposureDurationSeconds: 0,
        minimumExposureDurationSeconds: 0,
        maximumExposureDurationSeconds: 0,
        whiteBalanceMode: .auto,
        manualWhiteBalanceSupported: false,
        kelvin: 0,
        tint: 0,
        minimumKelvin: 2_500,
        maximumKelvin: 10_000,
        minimumTint: -150,
        maximumTint: 150,
        focusMode: .auto,
        manualFocusSupported: false,
        lensPosition: 0,
        minimumLensPosition: 0,
        maximumLensPosition: 1,
        physicalLensOptions: [],
        requiresPhysicalLensSelection: false,
        isApplying: false,
        flashRequiresAutoExposure: false
    )

    static let supportedKelvinRange: ClosedRange<Float> = 2_500...10_000
    static let supportedTintRange: ClosedRange<Float> = -150...150

    static func clampedFinite(_ value: Float, to range: ClosedRange<Float>, fallback: Float) -> Float {
        guard value.isFinite else {
            let safeFallback = fallback.isFinite ? fallback : range.lowerBound
            return min(max(safeFallback, range.lowerBound), range.upperBound)
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func clampedFinite(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else {
            let safeFallback = fallback.isFinite ? fallback : range.lowerBound
            return min(max(safeFallback, range.lowerBound), range.upperBound)
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func sanitizedExposureRequest(
        iso: Float,
        durationSeconds: Double,
        currentISO: Float,
        currentDurationSeconds: Double,
        isoRange: ClosedRange<Float>,
        durationRange: ClosedRange<Double>
    ) -> (iso: Float, durationSeconds: Double) {
        (
            clampedFinite(iso, to: isoRange, fallback: currentISO),
            clampedFinite(
                durationSeconds,
                to: durationRange,
                fallback: currentDurationSeconds
            )
        )
    }

    static func sanitizedWhiteBalanceRequest(
        kelvin: Float,
        tint: Float,
        currentKelvin: Float,
        currentTint: Float
    ) -> (kelvin: Float, tint: Float) {
        (
            clampedFinite(kelvin, to: supportedKelvinRange, fallback: currentKelvin),
            clampedFinite(tint, to: supportedTintRange, fallback: currentTint)
        )
    }

    static func sanitizedLensPosition(_ value: Float, current: Float) -> Float {
        clampedFinite(value, to: 0...1, fallback: current)
    }

    static func resolvedMode(requested: Mode, supported: Bool) -> Mode {
        requested == .manual && supported ? .manual : .auto
    }
}
