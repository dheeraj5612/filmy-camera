import Foundation

/// Capture controls are separate from FilmRecipe's display-referred tone controls.
/// DR200/400 here change sensor exposure and require a real RAW original.
enum FujiDynamicRange: Int, Codable, CaseIterable, Identifiable, Sendable {
    case dr100 = 100, dr200 = 200, dr400 = 400
    var id: Int { rawValue }
    var title: String { "DR\(rawValue)" }
    var protectionStops: Double { self == .dr400 ? 2 : self == .dr200 ? 1 : 0 }
}

enum FujiDrive: String, Codable, CaseIterable, Identifiable, Sendable {
    case single, continuousLow, continuousHigh, aeBracket, isoBracket, whiteBalanceBracket
    case filmBracket, dynamicRangeBracket, focusBracket, focusStack, computationalND, multipleExposure, interval
    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "Single frame"
        case .continuousLow: return "Continuous Low"
        case .continuousHigh: return "Continuous High"
        case .aeBracket: return "AE bracketing"
        case .isoBracket: return "ISO bracketing"
        case .whiteBalanceBracket: return "White balance bracketing"
        case .filmBracket: return "Film simulation bracketing"
        case .dynamicRangeBracket: return "Dynamic range bracketing"
        case .focusBracket: return "Focus bracketing"
        case .focusStack: return "Focus stacking"
        case .computationalND: return "Computational ND"
        case .multipleExposure: return "Multiple exposure"
        case .interval: return "Interval shooting"
        }
    }
    var isComposite: Bool { self == .focusStack || self == .computationalND || self == .multipleExposure }
    var usesFocusSweep: Bool { self == .focusBracket || self == .focusStack }
}

enum FujiBracketOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case ascending, centerFirst, descending
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ascending: return "− / 0 / +"
        case .centerFirst: return "0 / − / +"
        case .descending: return "+ / 0 / −"
        }
    }
}

enum FujiViewfinder: String, Codable, CaseIterable, Identifiable, Sendable {
    case electronic, opticalStyle, hybrid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .electronic: return "EVF"
        case .opticalStyle: return "OVF-style"
        case .hybrid: return "Hybrid"
        }
    }
}

enum FujiFocusAssist: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, splitImage, microprism
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .splitImage: return "Digital split image"
        case .microprism: return "Digital microprism"
        }
    }
}

enum FujiBlendMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case average, additive, bright, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum FujiQuickControl: String, Codable, CaseIterable, Identifiable, Sendable {
    case banks, drive, autoISO, dynamicRange, teleconverter, viewfinder, focusAssist, naturalView
    case nd, multipleExposure, preShot, rawDevelopment, bracketing, focusStack, interval, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .banks: return "C1–C7"
        case .drive: return "Drive"
        case .autoISO: return "Auto ISO"
        case .dynamicRange: return "Capture DR"
        case .teleconverter: return "Digital prime"
        case .viewfinder: return "Viewfinder"
        case .focusAssist: return "Focus assist"
        case .naturalView: return "Natural view"
        case .nd: return "ND"
        case .multipleExposure: return "Multi exposure"
        case .preShot: return "Pre-shot"
        case .rawDevelopment: return "RAW develop"
        case .bracketing: return "BKT settings"
        case .focusStack: return "Focus stack"
        case .interval: return "Interval"
        case .manual: return "Sensor controls"
        }
    }
}

struct FujiAutoISOProfile: Codable, Equatable, Sendable {
    var minimumISO: Double = 100
    var maximumISO: Double = 1600
    /// The slowest preferred shutter, not an absolute floor at the ISO ceiling.
    var minimumShutterSeconds: Double = 1.0 / 125
    var useFocalLengthRule = false
    var motionMultiplier: Double = 1

    func normalized() -> Self {
        var result = self
        result.minimumISO = FujiMath.finite(minimumISO, in: 20...25_600, fallback: 100)
        result.maximumISO = FujiMath.finite(maximumISO, in: result.minimumISO...102_400, fallback: 1600)
        result.minimumShutterSeconds = FujiMath.finite(minimumShutterSeconds, in: (1.0 / 8000)...1, fallback: 1.0 / 125)
        result.motionMultiplier = FujiMath.finite(motionMultiplier, in: 0.5...4, fallback: 1)
        return result
    }

    static let defaults: [Self] = [
        .init(minimumISO: 100, maximumISO: 800, minimumShutterSeconds: 1.0 / 60),
        .init(minimumISO: 100, maximumISO: 3200, minimumShutterSeconds: 1.0 / 125),
        .init(minimumISO: 100, maximumISO: 6400, minimumShutterSeconds: 1.0 / 500)
    ]
}

struct FujiShootingSettings: Codable, Equatable, Sendable {
    var drive: FujiDrive = .single
    var dynamicRange: FujiDynamicRange = .dr100
    var captureRAW = false
    var autoISOIndex: Int? = nil
    var autoISOProfiles = FujiAutoISOProfile.defaults
    var digitalCrop: Double = 1
    var lockPrimeLens = false
    var viewfinder: FujiViewfinder = .electronic
    var naturalLiveView = false
    var focusAssist: FujiFocusAssist = .off
    var preShotSeconds: Double = 0
    var bracketCount = 3
    var bracketStep: Double = 1
    var bracketOrder: FujiBracketOrder = .centerFirst
    var filmRecipeIDs = ["provia-standard", "classic-chrome", "acros-monochrome"]
    var isoBracketStep: Double = 1
    var whiteBalanceStep = 2
    var burstCount = 5
    var focusCount = 7
    var focusNear: Double = 0.1
    var focusFar: Double = 0.9
    var focusInterval: Double = 0.15
    var ndStops = 3
    var multipleExposureCount = 2
    var blendMode: FujiBlendMode = .average
    var intervalSeconds: Double = 5
    var intervalCount = 10
    var keepCompositeSources = true

    var needsRAW: Bool { captureRAW || dynamicRange != .dr100 || drive == .dynamicRangeBracket }
    var autoISOProfile: FujiAutoISOProfile? {
        guard let index = autoISOIndex, autoISOProfiles.indices.contains(index) else { return nil }
        return autoISOProfiles[index]
    }
    var needsCaptureCoordinator: Bool {
        drive != .single || needsRAW || autoISOIndex != nil || digitalCrop != 1 || preShotSeconds > 0
    }
    var previewCrop: Double { viewfinder == .electronic ? digitalCrop : 1 }
    var showsNaturalPreview: Bool { naturalLiveView || viewfinder != .electronic }

    func normalized() -> Self {
        var result = self
        result.digitalCrop = FujiMath.finite(digitalCrop, in: 1...3, fallback: 1)
        result.preShotSeconds = FujiMath.finite(preShotSeconds, in: 0...1.5, fallback: 0)
        result.bracketCount = [3, 5, 7, 9].contains(bracketCount) ? bracketCount : 3
        result.bracketStep = FujiMath.finite(bracketStep, in: (1.0 / 3)...2, fallback: 1)
        result.isoBracketStep = FujiMath.finite(isoBracketStep, in: (1.0 / 3)...1, fallback: 1)
        result.whiteBalanceStep = min(max(whiteBalanceStep, 1), 3)
        result.burstCount = min(max(burstCount, 2), 20)
        result.focusCount = min(max(focusCount, 2), 20)
        result.focusNear = FujiMath.finite(focusNear, in: 0...1, fallback: 0.1)
        result.focusFar = FujiMath.finite(focusFar, in: 0...1, fallback: 0.9)
        result.focusInterval = FujiMath.finite(focusInterval, in: 0.05...3, fallback: 0.15)
        result.ndStops = min(max(ndStops, 1), 5)
        result.multipleExposureCount = min(max(multipleExposureCount, 2), 9)
        result.intervalSeconds = FujiMath.finite(intervalSeconds, in: 1...3600, fallback: 5)
        result.intervalCount = min(max(intervalCount, 2), 120)
        result.filmRecipeIDs = Array(filmRecipeIDs.filter { !$0.isEmpty }.prefix(3))
        while result.filmRecipeIDs.count < 3 { result.filmRecipeIDs.append("provia-standard") }
        result.autoISOProfiles = Array(autoISOProfiles.prefix(3)).map { $0.normalized() }
        while result.autoISOProfiles.count < 3 {
            result.autoISOProfiles.append(FujiAutoISOProfile.defaults[result.autoISOProfiles.count])
        }
        if let index = autoISOIndex, !(0..<3).contains(index) { result.autoISOIndex = nil }
        return result
    }
}

struct FujiExposure: Equatable, Sendable {
    var iso: Double
    var seconds: Double
    var product: Double { iso * seconds }
}

struct FujiSensorSnapshot: Sendable {
    let transactionID: UUID
    let deviceID: String
    let exposure: FujiExposure
    let isoRange: ClosedRange<Double>
    let durationRange: ClosedRange<Double>
    let lensPosition: Double
    let supportsFocus: Bool
    let supportsRAW: Bool
}

enum FujiShootingError: LocalizedError, Equatable, Sendable {
    case unavailable, busy, cancelled, timedOut, unsupportedRAW, unsupportedExposure, unsupportedFocus
    case exposureOutOfRange, invalidCombination(String), processingFailed, alignmentFailed, storageFailed
    var errorDescription: String? {
        switch self {
        case .unavailable: return "The camera is not available. Resume it and try again."
        case .busy: return "The camera is finishing another operation."
        case .cancelled: return "Shooting canceled. Frames already saved are kept."
        case .timedOut: return "The camera did not finish applying or capturing the requested settings."
        case .unsupportedRAW: return "This lens does not expose RAW. Select a supported physical rear lens in Sensor controls."
        case .unsupportedExposure: return "This lens does not support custom sensor exposure. Choose a physical lens in Sensor controls."
        case .unsupportedFocus: return "Focus bracketing requires a lens with manual focus control."
        case .exposureOutOfRange: return "The requested bracket or highlight protection exceeds this lens's exposure range."
        case .invalidCombination(let detail): return detail
        case .processingFailed: return "The frame could not be developed. Retained originals remain in RAW Develop or the capture source folder."
        case .alignmentFailed: return "Frames moved too far to stack safely. Use a tripod and a smaller focus range."
        case .storageFailed: return "The capture could not be written to local storage. Free some space and retry."
        }
    }
}

enum FujiMath {
    static func finite(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
    }

    /// Preserve metered exposure. Raise ISO before slowing past the preferred
    /// shutter; at maximum ISO permit a slower shutter, as Fuji Auto ISO does.
    static func autoExposure(
        metered: FujiExposure, profile: FujiAutoISOProfile,
        isoRange: ClosedRange<Double>, durationRange: ClosedRange<Double>, focalLength: Double = 50
    ) -> FujiExposure {
        let profile = profile.normalized()
        let low = min(max(profile.minimumISO, isoRange.lowerBound), isoRange.upperBound)
        let high = min(max(profile.maximumISO, low), isoRange.upperBound)
        let preferred = profile.useFocalLengthRule
            ? 1 / max(focalLength * profile.motionMultiplier, 1)
            : profile.minimumShutterSeconds
        let product = finite(metered.product, in: (isoRange.lowerBound * durationRange.lowerBound)...(isoRange.upperBound * durationRange.upperBound), fallback: low * preferred)
        let secondsAtLow = product / low
        let seconds = min(max(min(secondsAtLow, preferred), durationRange.lowerBound), durationRange.upperBound)
        let iso = min(max(product / seconds, low), high)
        return FujiExposure(iso: iso, seconds: min(max(product / iso, durationRange.lowerBound), durationRange.upperBound))
    }

    /// Adapt shutter first and ISO only when a hardware shutter boundary is
    /// reached. Reject an unattainable exposure rather than fake a DR label.
    static func shiftedExposure(
        _ base: FujiExposure, stops: Double, isoRange: ClosedRange<Double>, durationRange: ClosedRange<Double>
    ) throws -> FujiExposure {
        guard base.product.isFinite, base.product > 0, stops.isFinite else { throw FujiShootingError.exposureOutOfRange }
        let product = base.product * pow(2, stops)
        let seconds = min(max(base.seconds * pow(2, stops), durationRange.lowerBound), durationRange.upperBound)
        let iso = min(max(product / seconds, isoRange.lowerBound), isoRange.upperBound)
        let actual = FujiExposure(iso: iso, seconds: seconds)
        guard abs(log2(actual.product / product)) < 0.05 else { throw FujiShootingError.exposureOutOfRange }
        return actual
    }

    static func bracketOffsets(count: Int, step: Double, order: FujiBracketOrder) -> [Double] {
        let count = [3, 5, 7, 9].contains(count) ? count : 3
        let step = finite(step, in: (1.0 / 3)...2, fallback: 1)
        let half = count / 2
        switch order {
        case .ascending: return (-half...half).map { Double($0) * step }
        case .descending: return (-half...half).reversed().map { Double($0) * step }
        case .centerFirst: return [0] + (1...half).flatMap { [-Double($0) * step, Double($0) * step] }
        }
    }

    static func focusPositions(near: Double, far: Double, count: Int) -> [Double] {
        let count = min(max(count, 2), 20)
        let start = finite(near, in: 0...1, fallback: 0)
        let end = finite(far, in: 0...1, fallback: 1)
        return (0..<count).map { start + (end - start) * Double($0) / Double(count - 1) }
    }
}

struct FujiCaptureStep: Equatable, Sendable {
    var exposureOffset: Double = 0
    var dynamicRange: FujiDynamicRange = .dr100
    var focusPosition: Double? = nil
    var delayAfter: Double = 0
}

struct FujiCapturePlan: Equatable, Sendable {
    let steps: [FujiCaptureStep]
    let settings: FujiShootingSettings
    static func make(_ input: FujiShootingSettings) throws -> Self {
        let settings = input.normalized()
        if settings.preShotSeconds > 0 && (settings.needsRAW || settings.drive != .single) {
            throw FujiShootingError.invalidCombination("Pre-shot uses preview frames. Use Single frame with RAW and capture DR protection off.")
        }
        if settings.drive.usesFocusSweep && abs(settings.focusFar - settings.focusNear) < 0.001 {
            throw FujiShootingError.invalidCombination("Choose two different focus endpoints.")
        }
        let ordinary = FujiCaptureStep(dynamicRange: settings.dynamicRange)
        let steps: [FujiCaptureStep]
        switch settings.drive {
        case .aeBracket:
            steps = FujiMath.bracketOffsets(count: settings.bracketCount, step: settings.bracketStep, order: settings.bracketOrder)
                .map { FujiCaptureStep(exposureOffset: $0, dynamicRange: settings.dynamicRange) }
        case .dynamicRangeBracket:
            steps = FujiDynamicRange.allCases.map { FujiCaptureStep(dynamicRange: $0) }
        case .focusBracket, .focusStack:
            steps = FujiMath.focusPositions(near: settings.focusNear, far: settings.focusFar, count: settings.focusCount)
                .map { FujiCaptureStep(dynamicRange: settings.dynamicRange, focusPosition: $0, delayAfter: settings.focusInterval) }
        case .continuousLow, .continuousHigh:
            steps = Array(repeating: FujiCaptureStep(dynamicRange: settings.dynamicRange, delayAfter: settings.drive == .continuousLow ? 0.3 : 0), count: settings.burstCount)
        case .interval:
            steps = Array(repeating: FujiCaptureStep(dynamicRange: settings.dynamicRange, delayAfter: settings.intervalSeconds), count: settings.intervalCount)
        case .computationalND:
            steps = Array(repeating: ordinary, count: 1 << settings.ndStops)
        default: steps = [ordinary]
        }
        return Self(steps: steps, settings: settings)
    }
}
