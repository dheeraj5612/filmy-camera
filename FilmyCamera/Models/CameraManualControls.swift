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

// MARK: - Capture workflow policies (independent of camera hardware)

enum CaptureDelay: Int, CaseIterable, Identifiable {
    case off = 0, three = 3, five = 5, ten = 10
    var id: Int { rawValue }
    var title: String { self == .off ? "Off" : "\(rawValue)s" }
}

enum CaptureAspect: String, CaseIterable, Identifiable {
    case viewfinder, fourThree, square, threeTwo, sixteenNine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .viewfinder: return "Fit screen"
        case .fourThree: return "4:3"
        case .square: return "1:1"
        case .threeTwo: return "3:2"
        case .sixteenNine: return "16:9"
        }
    }
    func ratio(isLandscape: Bool) -> Double? {
        let ratio: Double
        switch self {
        case .viewfinder: return nil
        case .fourThree: ratio = 4.0 / 3.0
        case .square: ratio = 1
        case .threeTwo: ratio = 3.0 / 2.0
        case .sixteenNine: ratio = 16.0 / 9.0
        }
        return isLandscape ? ratio : 1 / ratio
    }
}

enum CompositionGuide: String, CaseIterable, Identifiable {
    case thirds, golden, square, crosshair
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thirds: return "Rule of thirds"
        case .golden: return "Golden ratio"
        case .square: return "Square guide"
        case .crosshair: return "Center crosshair"
        }
    }
}

/// A canceled countdown's completion cannot consume a new countdown. Integer
/// ticks are display state; the controller schedules against a monotonic clock.
struct CaptureTimerState {
    private(set) var operationID: UUID?
    private(set) var remaining = 0
    var isActive: Bool { operationID != nil }

    mutating func begin(seconds: Int) -> UUID? {
        guard !isActive, [3, 5, 10].contains(seconds) else { return nil }
        let id = UUID()
        operationID = id
        remaining = seconds
        return id
    }
    mutating func tick(_ id: UUID) -> Bool {
        guard id == operationID, remaining > 0 else { return false }
        remaining -= 1
        return remaining == 0
    }
    mutating func consume(_ id: UUID) -> Bool {
        guard id == operationID, remaining == 0 else { return false }
        cancel()
        return true
    }
    mutating func cancel() { operationID = nil; remaining = 0 }
}

/// Cancellation invalidates a result, but synchronous GPU work must finish
/// before another preview operation can begin.
struct PreviewRenderState {
    struct Ticket: Equatable, Sendable {
        let id: UUID
        let generation: UInt64
    }

    private(set) var generation: UInt64 = 0
    private var active: Ticket?

    mutating func begin() -> Ticket? {
        guard active == nil else { return nil }
        let ticket = Ticket(id: UUID(), generation: generation)
        active = ticket
        return ticket
    }

    /// Always drains the matching operation; only current results may publish.
    mutating func finish(_ ticket: Ticket) -> Bool {
        guard active == ticket else { return false }
        active = nil
        return ticket.generation == generation
    }

    mutating func invalidate() { generation &+= 1 }
}

/// Display-referred, unfiltered preview analysis. Not a RAW histogram or a
/// sensor-clipping meter. All input/output is bounded to 192 x 192 pixels.
enum PreviewAnalysisMath {
    static let maximumDimension = 192
    struct Result: Equatable, Sendable {
        let histogram: [Int]
        let clippedPixels: Int
        let pixelCount: Int
        let overlayRGBA: [UInt8]
    }

    static func analyze(rgba: [UInt8], width: Int, height: Int, zebras: Bool, peaking: Bool) -> Result? {
        guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
              rgba.count == width * height * 4 else { return nil }
        let count = width * height
        var luma = [Int](repeating: 0, count: count)
        var histogram = [Int](repeating: 0, count: 64)
        var overlay = [UInt8](repeating: 0, count: count * 4)
        var clipped = 0
        for index in 0..<count {
            let offset = index * 4
            let r = Int(rgba[offset]), g = Int(rgba[offset + 1]), b = Int(rgba[offset + 2])
            let y = (54 * r + 183 * g + 19 * b) >> 8
            luma[index] = y
            histogram[min(y / 4, 63)] += 1
            // Warn on individual color-channel clipping, not just white pixels.
            if max(r, g, b) >= 250 {
                clipped += 1
                if zebras, ((index % width + index / width) / 3).isMultiple(of: 2) {
                    overlay[offset] = 180; overlay[offset + 1] = 156; overlay[offset + 3] = 180
                }
            }
        }
        if peaking, width > 2, height > 2 {
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    let edge = abs(luma[index + 1] - luma[index - 1]) + abs(luma[index + width] - luma[index - width])
                    guard edge > 72, luma[index] > 20, luma[index] < 245 else { continue }
                    let offset = index * 4
                    overlay[offset] = 220; overlay[offset + 1] = 55; overlay[offset + 2] = 55; overlay[offset + 3] = 220
                }
            }
        }
        return Result(histogram: histogram, clippedPixels: clipped, pixelCount: count, overlayRGBA: overlay)
    }

    static func horizonDegrees(x: Double, y: Double) -> Double? {
        guard x.isFinite, y.isFinite, x * x + y * y > 0.04 else { return nil }
        let degrees = atan2(x, -y) * 180 / .pi
        // The nearest portrait/landscape axis is level in any orientation.
        return degrees - (degrees / 90).rounded() * 90
    }
}
