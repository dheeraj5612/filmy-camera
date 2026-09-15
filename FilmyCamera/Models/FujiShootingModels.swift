import Foundation

/// Capture controls, not film-renderer presets. Stored values are validated at
/// the persistence boundary and again against the current physical device.
enum FujiDriveMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case single, continuousLow, continuousHigh, exposureBracket, isoBracket
    case filmBracket, whiteBalanceBracket, dynamicRangeBracket, focusBracket
    case focusStack, multipleExposure, preShot, computationalND, interval

    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "Single frame"
        case .continuousLow: return "CL · paced burst"
        case .continuousHigh: return "CH · fastest available burst"
        case .exposureBracket: return "AE BKT"
        case .isoBracket: return "ISO BKT"
        case .filmBracket: return "Film simulation BKT"
        case .whiteBalanceBracket: return "White balance BKT"
        case .dynamicRangeBracket: return "DR BKT · 100 / 200 / 400"
        case .focusBracket: return "Focus BKT · source frames"
        case .focusStack: return "Focus stack · merged + sources"
        case .multipleExposure: return "Multiple exposure"
        case .preShot: return "Pre-shot + full-resolution still"
        case .computationalND: return "Computational ND"
        case .interval: return "Interval shooting"
        }
    }
    var needsManualExposure: Bool {
        [.exposureBracket, .isoBracket, .dynamicRangeBracket, .focusBracket, .focusStack].contains(self)
    }
    var needsManualFocus: Bool { self == .focusBracket || self == .focusStack }
}

enum FujiDynamicRange: Int, CaseIterable, Codable, Identifiable, Sendable {
    case dr100 = 100, dr200 = 200, dr400 = 400
    var id: Int { rawValue }
    var title: String { "DR\(rawValue)" }
    var stops: Double {
        switch self {
        case .dr100: return 0
        case .dr200: return 1
        case .dr400: return 2
        }
    }
    var gain: Double { pow(2, stops) }
}

enum FujiViewfinderMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case electronic, opticalStyle, hybrid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .electronic: return "EVF · developed preview"
        case .opticalStyle: return "OVF-style · natural + frame lines"
        case .hybrid: return "Hybrid · natural + developed inset"
        }
    }
}

enum FujiFocusAssist: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, splitImage, microprism
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .splitImage: return "Digital split comparison"
        case .microprism: return "Digital microprism contrast aid"
        }
    }
}

enum FujiMultipleExposureBlend: String, CaseIterable, Codable, Identifiable, Sendable {
    case average, additive, bright, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum FujiPrimeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case native, crop14, crop20, crop30
    var id: String { rawValue }
    var factor: Double {
        switch self {
        case .native: return 1
        case .crop14: return 1.4
        case .crop20: return 2
        case .crop30: return 3
        }
    }
    var title: String {
        self == .native ? "Native lens" : String(format: "%.1f× digital prime crop", factor)
    }
    /// No resampling: a 2x crop retains one quarter of the source pixels.
    var retainedPixelFraction: Double { 1 / (factor * factor) }
}

enum FujiQItem: String, CaseIterable, Codable, Identifiable, Sendable {
    case banks, drive, autoISO, dynamicRange, filmBracket, whiteBalanceBracket
    case prime, viewfinder, naturalView, focusAssist, multipleExposure
    case preShot, computationalND, focusStack, raw, interval
    var id: String { rawValue }
    var title: String {
        switch self {
        case .banks: return "C1–C7"
        case .drive: return "Drive / BKT"
        case .autoISO: return "Auto ISO"
        case .dynamicRange: return "Dynamic range"
        case .filmBracket: return "Film BKT"
        case .whiteBalanceBracket: return "WB BKT"
        case .prime: return "Digital prime"
        case .viewfinder: return "Viewfinder"
        case .naturalView: return "Natural live view"
        case .focusAssist: return "Focus assist"
        case .multipleExposure: return "Multiple exposure"
        case .preShot: return "Pre-shot"
        case .computationalND: return "Computational ND"
        case .focusStack: return "Focus stack"
        case .raw: return "RAW development"
        case .interval: return "Interval"
        }
    }
}

struct FujiAutoISOProfile: Codable, Equatable, Sendable {
    var minimumISO: Double = 100
    var maximumISO: Double = 3200
    /// Maximum preferred duration. At the ISO ceiling the shutter is allowed
    /// to become slower, just as Fuji minimum-shutter Auto ISO behaves.
    var minimumShutterSeconds: Double = 1 / 125

    static let defaults: [Self] = [
        .init(minimumISO: 100, maximumISO: 800, minimumShutterSeconds: 1 / 60),
        .init(minimumISO: 100, maximumISO: 3200, minimumShutterSeconds: 1 / 125),
        .init(minimumISO: 100, maximumISO: 6400, minimumShutterSeconds: 1 / 500)
    ]

    func validated() -> Self {
        let minimum = FujiLimits.finite(minimumISO, fallback: 100, in: 16...102400)
        return Self(
            minimumISO: minimum,
            maximumISO: FujiLimits.finite(maximumISO, fallback: 3200, in: minimum...102400),
            minimumShutterSeconds: FujiLimits.finite(minimumShutterSeconds, fallback: 1 / 125, in: (1 / 32000)...1)
        )
    }
}

struct FujiExposure: Equatable, Sendable {
    let iso: Double
    let seconds: Double
    let isLimited: Bool
}

enum FujiAutoISOPlanner {
    /// `meteredProduct` is ISO * seconds at the target brightness. The solver
    /// first protects shutter speed, then raises ISO, then accepts a slower
    /// shutter. It never advertises an unavailable sensor value.
    static func resolve(
        meteredProduct: Double,
        profile: FujiAutoISOProfile,
        isoBounds: ClosedRange<Double>,
        durationBounds: ClosedRange<Double>
    ) -> FujiExposure {
        let profile = profile.validated()
        let minimum = min(max(profile.minimumISO, isoBounds.lowerBound), isoBounds.upperBound)
        let maximum = min(max(profile.maximumISO, minimum), isoBounds.upperBound)
        let preferredDuration = min(max(profile.minimumShutterSeconds, durationBounds.lowerBound), durationBounds.upperBound)
        let product = FujiLimits.finite(meteredProduct, fallback: minimum * preferredDuration, in: 0.0000001...1e9)
        let iso = min(max(product / preferredDuration, minimum), maximum)
        let duration = min(max(product / iso, durationBounds.lowerBound), durationBounds.upperBound)
        let actualProduct = iso * duration
        return FujiExposure(iso: iso, seconds: duration, isLimited: abs(log2(actualProduct / product)) > 0.1)
    }
}

enum FujiLimits {
    static let maximumSourceBytes = 120_000_000
    static let maximumPreviewFrames = 12
    static let previewLongEdge = 1280
    static let compositeLongEdge = 4096
    static let maximumSequenceFrames = 24
    static let maximumFocusFrames = 12

    static func finite(_ value: Double, fallback: Double, in range: ClosedRange<Double>) -> Double {
        min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
    }
}

struct FujiShootingSettings: Codable, Equatable, Sendable {
    var enabled = false
    var drive: FujiDriveMode = .single
    var dynamicRange: FujiDynamicRange = .dr100
    var retainRAW = false
    var autoISOIndex: Int? = nil
    var autoISOProfiles = FujiAutoISOProfile.defaults
    var viewfinder: FujiViewfinderMode = .electronic
    var naturalLiveView = false
    var prime: FujiPrimeMode = .native
    var focusAssist: FujiFocusAssist = .off
    var bracketCount = 3
    var bracketStepEV: Double = 1
    var filmRecipeIDs = ["provia-standard", "classic-chrome", "acros-monochrome"]
    var whiteBalanceStep: Double = 500
    var burstCount = 5
    var intervalSeconds: Double = 2
    var focusCount = 7
    var focusNear: Double = 0.1
    var focusFar: Double = 0.9
    var multipleExposureCount = 2
    var multipleExposureBlend: FujiMultipleExposureBlend = .average
    var preShotSeconds: Double = 1
    var preShotCount = 6
    var ndSeconds: Double = 2
    var qItems = FujiQItem.allCases

    var activeAutoISO: FujiAutoISOProfile? {
        guard enabled, let index = autoISOIndex, autoISOProfiles.indices.contains(index) else { return nil }
        return autoISOProfiles[index]
    }
    var previewIsNatural: Bool { enabled && (naturalLiveView || viewfinder != .electronic) }
    var cropFactor: Double { enabled ? prime.factor : 1 }
    var needsRAW: Bool { retainRAW || dynamicRange != .dr100 || drive == .dynamicRangeBracket }

    func validated() -> Self {
        var copy = self
        copy.autoISOProfiles = (0..<3).map { index in
            autoISOProfiles.indices.contains(index) ? autoISOProfiles[index].validated() : FujiAutoISOProfile.defaults[index]
        }
        if let index = copy.autoISOIndex, !(0..<3).contains(index) { copy.autoISOIndex = nil }
        copy.bracketCount = [3, 5, 7].contains(bracketCount) ? bracketCount : 3
        copy.bracketStepEV = FujiLimits.finite(bracketStepEV, fallback: 1, in: (1 / 3)...2)
        copy.whiteBalanceStep = FujiLimits.finite(whiteBalanceStep, fallback: 500, in: 100...2000)
        copy.burstCount = min(max(burstCount, 2), FujiLimits.maximumSequenceFrames)
        copy.intervalSeconds = FujiLimits.finite(intervalSeconds, fallback: 2, in: 0.5...3600)
        copy.focusCount = min(max(focusCount, 2), FujiLimits.maximumFocusFrames)
        copy.focusNear = FujiLimits.finite(focusNear, fallback: 0.1, in: 0...1)
        copy.focusFar = FujiLimits.finite(focusFar, fallback: 0.9, in: 0...1)
        if copy.focusNear > copy.focusFar { swap(&copy.focusNear, &copy.focusFar) }
        copy.multipleExposureCount = min(max(multipleExposureCount, 2), 9)
        copy.preShotSeconds = FujiLimits.finite(preShotSeconds, fallback: 1, in: 0.25...2)
        copy.preShotCount = min(max(preShotCount, 1), FujiLimits.maximumPreviewFrames)
        copy.ndSeconds = FujiLimits.finite(ndSeconds, fallback: 2, in: 0.5...8)
        var seenRecipes = Set<String>()
        copy.filmRecipeIDs = filmRecipeIDs.filter { !$0.isEmpty && seenRecipes.insert($0).inserted }.prefix(3).map { $0 }
        if copy.filmRecipeIDs.isEmpty { copy.filmRecipeIDs = ["provia-standard", "classic-chrome", "acros-monochrome"] }
        var seenItems = Set<FujiQItem>()
        copy.qItems = qItems.filter { seenItems.insert($0).inserted }.prefix(16).map { $0 }
        return copy
    }
}

struct FujiCaptureStep: Equatable, Sendable {
    var exposureEV: Double = 0
    var isoEV: Double = 0
    var lensPosition: Double? = nil
    var dynamicRange: FujiDynamicRange = .dr100
    var delayBefore: Double = 0
}

enum FujiCapturePlanner {
    static func bracketOffsets(count: Int, step: Double) -> [Double] {
        let count = [3, 5, 7].contains(count) ? count : 3
        let step = FujiLimits.finite(step, fallback: 1, in: (1 / 3)...2)
        return [0] + (1...(count / 2)).flatMap { [-Double($0) * step, Double($0) * step] }
    }

    static func steps(for input: FujiShootingSettings) -> [FujiCaptureStep] {
        let settings = input.validated()
        let normal = FujiCaptureStep(dynamicRange: settings.dynamicRange)
        switch settings.drive {
        case .exposureBracket:
            return bracketOffsets(count: settings.bracketCount, step: settings.bracketStepEV).map {
                FujiCaptureStep(exposureEV: $0, dynamicRange: settings.dynamicRange)
            }
        case .isoBracket:
            return bracketOffsets(count: settings.bracketCount, step: settings.bracketStepEV).map {
                FujiCaptureStep(isoEV: $0, dynamicRange: settings.dynamicRange)
            }
        case .dynamicRangeBracket:
            return FujiDynamicRange.allCases.map { FujiCaptureStep(dynamicRange: $0) }
        case .focusBracket, .focusStack:
            return (0..<settings.focusCount).map { index in
                let position = settings.focusNear + (settings.focusFar - settings.focusNear) * Double(index) / Double(settings.focusCount - 1)
                return FujiCaptureStep(lensPosition: position, dynamicRange: settings.dynamicRange)
            }
        case .continuousLow, .continuousHigh, .interval:
            return (0..<settings.burstCount).map { index in
                var step = normal
                if index > 0 {
                    step.delayBefore = settings.drive == .interval ? settings.intervalSeconds : (settings.drive == .continuousLow ? 0.25 : 0)
                }
                return step
            }
        default:
            // Film and WB bracketing develop a single original, not three
            // subtly different moments. Pre-shot adds one full-resolution still.
            return [normal]
        }
    }
}

/// Small value-type ring shared by pre-shot and tests. Timestamps are monotonic,
/// so clock/timezone changes cannot retain stale camera frames indefinitely.
struct FujiTimedBuffer<Value> {
    struct Entry {
        let time: Double
        let value: Value
    }
    private(set) var entries: [Entry] = []
    var capacity: Int
    var maximumAge: Double

    mutating func append(_ value: Value, at time: Double) {
        guard time.isFinite, capacity > 0, maximumAge.isFinite, maximumAge > 0 else {
            entries.removeAll()
            return
        }
        if let last = entries.last, time < last.time { entries.removeAll() }
        entries.removeAll { time - $0.time > maximumAge }
        entries.append(Entry(time: time, value: value))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    mutating func takeEntries(at time: Double) -> [Entry] {
        defer { entries.removeAll() }
        guard time.isFinite else { return [] }
        return entries.filter { $0.time <= time && time - $0.time <= maximumAge }
    }
    mutating func take(at time: Double) -> [Value] { takeEntries(at: time).map(\.value) }
    mutating func removeAll() { entries.removeAll() }
}

struct FujiDevelopmentAdjustments: Codable, Equatable, Sendable {
    var exposureEV: Double = 0
    /// nil retains the RAW file's as-shot neutral balance.
    var temperature: Double? = nil
    var tint: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var sharpness: Double = 0
    var noiseReduction: Double = 0.2

    func validated() -> Self {
        var copy = self
        copy.exposureEV = FujiLimits.finite(exposureEV, fallback: 0, in: -3...3)
        if let temperature { copy.temperature = FujiLimits.finite(temperature, fallback: 5600, in: 2500...10000) }
        copy.tint = FujiLimits.finite(tint, fallback: 0, in: -150...150)
        copy.highlights = FujiLimits.finite(highlights, fallback: 0, in: -1...1)
        copy.shadows = FujiLimits.finite(shadows, fallback: 0, in: -1...1)
        copy.sharpness = FujiLimits.finite(sharpness, fallback: 0, in: 0...1)
        copy.noiseReduction = FujiLimits.finite(noiseReduction, fallback: 0.2, in: 0...1)
        return copy
    }
}
