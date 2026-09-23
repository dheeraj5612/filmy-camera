import Foundation

/// Requests are independent of any iPhone marketing name. The active format,
/// capture mode and codec determine which combinations can actually be used.
public struct ProCaptureOptions: Codable, Equatable, Sendable {
    public enum Resolution: Int, Codable, CaseIterable, Sendable {
        case mp12 = 12, mp24 = 24, mp48 = 48
        public var title: String { "\(rawValue) MP" }
        public var pixelBudget: Double { Double(rawValue) * 1_000_000 }
    }
    public enum Codec: String, Codable, CaseIterable, Sendable {
        case jpeg, heif
        public var title: String { self == .jpeg ? "JPEG · sRGB" : "HEIF · Display P3" }
    }
    public enum RawFormat: String, Codable, CaseIterable, Sendable {
        case off, bayer, appleProRAW
        public var title: String {
            switch self {
            case .off: return "Off"
            case .bayer: return "Bayer DNG"
            case .appleProRAW: return "Apple ProRAW"
            }
        }
    }
    public var resolution: Resolution = .mp12
    public var codec: Codec = .jpeg
    public var raw: RawFormat = .off
    public var hdr = false
    public var livePhoto = false
    public init() {}
}

public struct ProPhotoDimensions: Codable, Equatable, Sendable {
    public let width: Int32
    public let height: Int32
    public var pixels: Int64 { Int64(width) * Int64(height) }
    public init(width: Int32, height: Int32) { self.width = width; self.height = height }
}

public struct ProCaptureOptionCapabilities: Equatable, Sendable {
    public var dimensions: [ProPhotoDimensions] = []
    public var supportsHEIF = false
    public var supportsBayerRAW = false
    public var supportsProRAW = false
    public var supportsLivePhoto = false
    public var supportsHDRExport = false
    public var aperture: Float = 0
    public var minimumAperture: Float = 0
    public var maximumAperture: Float = 0
    public var supportsVariableAperture = false
    public var resolutions: [ProCaptureOptions.Resolution] {
        ProCaptureOptions.Resolution.allCases.filter { resolution in
            // 24 MP is an explicitly labeled downsample of a 48 MP capture.
            // Native 24 MP fusion requires Photos deferred processing, which
            // is not interchangeable with immediately available source bytes.
            let minimum = resolution == .mp24 ? 46_000_000 : Int64(Double(resolution.rawValue) * 950_000)
            return dimensions.contains { $0.pixels >= minimum }
        }
    }
    public init() {}
}

public enum ExposurePriorityMode: String, CaseIterable, Sendable {
    case shutter, iso
    public var title: String { self == .shutter ? "Shutter priority" : "ISO priority" }
}

/// Pure, tested policy shared by settings, capture and the on-disk manifest.
enum ProCapturePolicy {
    struct Resolution: Equatable, Sendable {
        let options: ProCaptureOptions
        let notices: [String]
        let dimensions: ProPhotoDimensions?
    }

    static func resolve(_ request: ProCaptureOptions, capabilities: ProCaptureOptionCapabilities, manualExposure: Bool) -> Resolution {
        var options = request
        var notices: [String] = []
        if options.codec == .heif && !capabilities.supportsHEIF {
            options.codec = .jpeg
            notices.append("HEIF is unavailable on this camera. JPEG is selected.")
        }
        if options.raw == .bayer && !capabilities.supportsBayerRAW || options.raw == .appleProRAW && !capabilities.supportsProRAW {
            options.raw = .off
            notices.append("The selected RAW format is unavailable on this lens. RAW is off.")
        }
        if options.livePhoto && (!capabilities.supportsLivePhoto || options.raw != .off || manualExposure) {
            options.livePhoto = false
            notices.append("Live Photos require a supported camera, automatic exposure and RAW off.")
        }
        if options.hdr && (options.codec != .heif || !capabilities.supportsHDRExport) {
            options.hdr = false
            notices.append("HDR export requires HEIF and iOS 18 or later.")
        }
        if (manualExposure || options.raw == .bayer || options.livePhoto) && options.resolution != .mp12 {
            options.resolution = .mp12
            notices.append("This capture mode is limited to a 12 MP request. No upscaling is used.")
        }
        if !capabilities.resolutions.contains(options.resolution) {
            options.resolution = capabilities.resolutions.last(where: { $0.rawValue <= options.resolution.rawValue }) ?? .mp12
            notices.append("The requested resolution is unavailable on this lens.")
        }
        if options.resolution == .mp24 {
            notices.append("24 MP output is downsampled from a 48 MP request, not Apple's deferred 24 MP fusion.")
        }
        if options.livePhoto {
            notices.append("Silent Live Photo originals are retained. Filmy edits affect the still, not the motion clip.")
        }
        if options.hdr {
            notices.append("HDR preserves source highlight headroom when available. SDR sources stay SDR; print finishes use SDR.")
        }
        let minimumPixels = options.resolution == .mp24 ? 46_000_000 : Int64(Double(options.resolution.rawValue) * 950_000)
        // AVFoundation requires one of the active format's exact dimensions,
        // not an invented 24 MP width/height. Never request above output max.
        let sorted = capabilities.dimensions.filter { $0.width > 0 && $0.height > 0 }.sorted { $0.pixels < $1.pixels }
        let dimension = sorted.first { $0.pixels >= minimumPixels } ?? sorted.last
        return Resolution(options: options, notices: notices, dimensions: dimension)
    }

    static func outputScale(width: Double, height: Double, resolution: ProCaptureOptions.Resolution) -> Double {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return 1 }
        // Native sensor dimensions use rounded marketing MP labels. Do not
        // resample a 12.2/48.8 MP sensor solely to hit a decimal round number.
        let pixels = width * height
        if resolution != .mp24, pixels <= resolution.pixelBudget * 1.04 { return 1 }
        return min(1, sqrt(resolution.pixelBudget / pixels))
    }
}

/// A damped exposure meter. The fixed parameter is never used as the feedback
/// actuator. Negative target offset means the sensor needs MORE exposure.
enum ExposurePriorityPolicy {
    struct Request: Equatable, Sendable {
        let iso: Float
        let duration: Double
        let reachedLimit: Bool
    }
    static func next(mode: ExposurePriorityMode, fixedValue: Double, iso: Float, duration: Double,
                     offset: Float, isoRange: ClosedRange<Float>, durationRange: ClosedRange<Double>) -> Request? {
        guard fixedValue.isFinite, fixedValue > 0, iso.isFinite, iso > 0,
              duration.isFinite, duration > 0, offset.isFinite else { return nil }
        let correctionEV = abs(offset) <= 0.1 ? 0 : min(max(-Double(offset) * 0.45, -0.33), 0.33)
        let multiplier = pow(2, correctionEV)
        let requestedISO = mode == .iso ? fixedValue : Double(iso) * multiplier
        let requestedDuration = mode == .shutter ? fixedValue : duration * multiplier
        let nextISO = min(max(requestedISO, Double(isoRange.lowerBound)), Double(isoRange.upperBound))
        let nextDuration = min(max(requestedDuration, durationRange.lowerBound), durationRange.upperBound)
        let limited = abs(nextISO - requestedISO) > 0.01 || abs(nextDuration - requestedDuration) > 0.000001
        return Request(iso: Float(nextISO), duration: nextDuration, reachedLimit: limited && abs(offset) > 0.1)
    }
}

/// Owns the temporary paired movie until it has been copied into a durable
/// project or Photos. Late callbacks and canceled captures cannot leak files.
public final class CaptureMovieResource: @unchecked Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Buffers callbacks until didFinishCaptureFor. RAW and processed callbacks may
/// arrive in either order, and a Live Photo's movie can finish after its still.
struct ProCaptureAccumulator {
    let id: Int64
    let options: ProCaptureOptions
    var processed: Data?
    var raw: Data?
    var movie: CaptureMovieResource?
    var processingFailed = false
    var dimensions = ProPhotoDimensions(width: 0, height: 0)
    var flashFired = false
    mutating func accept(data: Data?, isRaw: Bool, id: Int64) {
        guard id == self.id else { return }
        guard let data, !data.isEmpty else { processingFailed = true; return }
        if isRaw { raw = data } else { processed = data }
    }
    var isComplete: Bool {
        !processingFailed && processed != nil && (options.raw == .off || raw != nil)
            && (!options.livePhoto || movie != nil)
    }
}

/// Reject malformed capability ranges rather than fabricating optical settings.
enum OpticalAperturePolicy {
    static func clamped(_ value: Float, minimum: Float, maximum: Float) -> Float? {
        guard value.isFinite, minimum.isFinite, maximum.isFinite,
              minimum > 0, maximum > minimum else { return nil }
        return min(max(value, minimum), maximum)
    }
}
