import Foundation

/// Preferences are distinct from negotiated hardware settings. A lens switch
/// never silently turns an unavailable RAW or resolution request into another
/// format: the capability surface explains what must be changed.
public struct ProCaptureSettings: Codable, Equatable, Sendable {
    public enum Resolution: Int, Codable, CaseIterable, Identifiable, Sendable {
        case mp12 = 12, mp24 = 24, mp48 = 48
        public var id: Int { rawValue }
        public var title: String { "\(rawValue) MP" }
        public var pixelBudget: Int64 {
            switch self {
            case .mp12: 4_032 * 3_024
            case .mp24: 5_712 * 4_284
            case .mp48: 8_064 * 6_048
            }
        }
    }

    public enum Format: String, Codable, CaseIterable, Identifiable, Sendable {
        case jpeg, heif, bayerRAW, proRAW
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .jpeg: "JPEG"
            case .heif: "HEIF"
            case .bayerRAW: "DNG + HEIF"
            case .proRAW: "ProRAW + HEIF"
            }
        }
        public var retainsRAW: Bool { self == .bayerRAW || self == .proRAW }
        public var renderedExtension: String { self == .jpeg ? "jpg" : "heic" }
    }

    public enum DynamicRange: String, Codable, CaseIterable, Identifiable, Sendable {
        case sdr, hdr
        public var id: String { rawValue }
        public var title: String { self == .hdr ? "HDR (10-bit HEIF)" : "Standard" }
    }

    public enum ColorGamut: String, Codable, CaseIterable, Identifiable, Sendable {
        case sRGB, displayP3
        public var id: String { rawValue }
        public var title: String { self == .displayP3 ? "Display P3" : "sRGB" }
    }

    public var resolution: Resolution = .mp12
    public var format: Format = .heif
    public var dynamicRange: DynamicRange = .sdr
    public var colorGamut: ColorGamut = .displayP3
    public var livePhoto = false
    public var livePhotoAudio = false

    public init() {}

    /// Legacy render callers and golden-image tests retain their sRGB JPEG
    /// contract. New captures use the explicitly selected output preferences.
    public static var legacy: Self {
        var settings = Self()
        settings.format = .jpeg
        settings.colorGamut = .sRGB
        settings.resolution = .mp48
        return settings
    }

    public var incompatibility: String? {
        if format == .jpeg && dynamicRange == .hdr {
            return "HDR needs HEIF. Select HEIF or use Standard dynamic range."
        }
        if livePhoto && dynamicRange == .hdr {
            return "Live Photo editing currently uses standard dynamic range. Turn Live off for HDR HEIF."
        }
        if livePhoto && format.retainsRAW {
            return "Live Photos and RAW cannot be captured together. Choose HEIF or turn Live off."
        }
        if livePhoto && resolution != .mp12 {
            return "Live Photos use 12 MP. Select 12 MP or turn Live off."
        }
        return nil
    }

    public static func restored(from data: Data?) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}

public enum CameraExposureProgram: String, CaseIterable, Identifiable, Sendable {
    case automatic, manual, shutterPriority, isoPriority, aperturePriority
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: "Auto"
        case .manual: "Manual"
        case .shutterPriority: "Shutter priority"
        case .isoPriority: "ISO priority"
        case .aperturePriority: "Aperture priority"
        }
    }
}

public struct ProCaptureCapabilities: Equatable, Sendable {
    public var resolutions: [ProCaptureSettings.Resolution] = []
    public var formats: [ProCaptureSettings.Format] = []
    public var livePhotoSupported = false
    public var wideColorSupported = false
    public var exposurePrograms: [CameraExposureProgram] = [.automatic]
    public var aperture: Float = 0
    public var minimumAperture: Float = 0
    public var maximumAperture: Float = 0
    public var nativeExposureAPIAvailable = false
    public var variableApertureSupported: Bool {
        minimumAperture > 0 && maximumAperture > minimumAperture
            && exposurePrograms.contains(.aperturePriority)
    }
    public init() {}

    public func unavailableReason(for settings: ProCaptureSettings) -> String? {
        if let reason = settings.incompatibility { return reason }
        guard resolutions.contains(settings.resolution) else {
            return "\(settings.resolution.title) is unavailable on this lens. Choose a supported resolution."
        }
        guard formats.contains(settings.format) else {
            return "\(settings.format.title) is unavailable on this lens. Choose a supported format."
        }
        if settings.livePhoto && !livePhotoSupported { return "Live Photos are unavailable on this lens." }
        return nil
    }
}

/// 24 MP is an explicit high-resolution downsample, NOT an AVCaptureDeferred-
/// PhotoProxy. Proxy dimensions are excluded because a proxy is not a finished
/// 24 MP photo. This also avoids silently writing a second asset into Photos.
public enum PhotoResolutionPolicy {
    public struct Dimensions: Equatable, Sendable {
        public let width: Int32
        public let height: Int32
        public init(width: Int32, height: Int32) { self.width = width; self.height = height }
        public var pixels: Int64 { Int64(width) * Int64(height) }
        public var isDeferred24MP: Bool { pixels >= 20_000_000 && pixels <= 30_000_000 }
    }

    public static func captureDimensions(
        for resolution: ProCaptureSettings.Resolution,
        supported: [Dimensions]
    ) -> Dimensions? {
        let candidates = supported.filter { $0.width > 0 && $0.height > 0 && !$0.isDeferred24MP }
            .sorted { $0.pixels < $1.pixels }
        // Older front cameras may deliver fewer than 12 MP. Never upscale.
        if resolution == .mp12 { return candidates.first }
        // Camera dimensions are nominal (12 MP often means 12.2 MP).
        let minimum = resolution == .mp12 ? Int64(10_000_000)
            : resolution == .mp24 ? Int64(40_000_000) : Int64(40_000_000)
        return candidates.first { $0.pixels >= minimum }
    }

    public static func availableResolutions(supported: [Dimensions]) -> [ProCaptureSettings.Resolution] {
        ProCaptureSettings.Resolution.allCases.filter { captureDimensions(for: $0, supported: supported) != nil }
    }

    public static func outputScale(sourcePixels: Double, resolution: ProCaptureSettings.Resolution) -> Double {
        guard sourcePixels.isFinite, sourcePixels > 0 else { return 1 }
        return min(1, sqrt(Double(resolution.pixelBudget) / sourcePixels))
    }
}

/// All callbacks belong to a single unique capture ID and are assembled only
/// at the terminal callback. A processed callback is not the end of RAW+HEIF
/// or Live Photo capture.
struct PhotoCaptureAssembly: Sendable {
    let uniqueID: Int64
    let settings: ProCaptureSettings
    var processed: Data?
    var raw: Data?
    var liveMovieURL: URL?
    var failed = false

    var isComplete: Bool {
        !failed && processed?.isEmpty == false
            && (!settings.format.retainsRAW || raw?.isEmpty == false)
            && (!settings.livePhoto || liveMovieURL != nil)
    }
}
