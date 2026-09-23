import Foundation

/// Scene Auto is deliberately session-only. Constructing a camera never enables it.
public struct SceneAutoState: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case off, metering, adapting, settled, held, paused, limited
    }
    public var phase: Phase = .off
    public var scene: SceneAutoScene = .balanced
    public var development = SceneAutoDevelopment()
    public var generation: UInt64 = 0
    public var isEnabled: Bool { phase != .off }
    public var acceptsFrames: Bool { isEnabled && phase != .held && phase != .paused }
    public var title: String {
        switch phase {
        case .off: return "Scene Auto Off"
        case .metering: return "Metering"
        case .adapting: return "Adapting"
        case .settled: return scene.title
        case .held: return "Auto Held"
        case .paused: return "Auto Paused"
        case .limited: return "Auto Limited"
        }
    }
}

public enum SceneAutoScene: String, CaseIterable, Sendable {
    case balanced, portrait, action, lowLight, backlit, highContrast
    public var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .portrait: return "Portrait"
        case .action: return "Motion"
        case .lowLight: return "Low Light"
        case .backlit: return "Backlit"
        case .highContrast: return "Highlights"
        }
    }
}

/// Additive, bounded adjustments to a temporary recipe copy, never saved edits.
/// These are display-referred tone adjustments, not RAW highlight recovery/HDR.
public struct SceneAutoDevelopment: Equatable, Sendable {
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var noiseReduction: Double = 0
    public var sharpness: Double = 0

    mutating func approach(_ target: Self, seconds: Double) {
        // A 0.025/second ceiling prevents a visible recipe jump on a new label.
        let step = max(0, min(seconds, 1)) * 0.025
        highlights = SceneAutoPolicy.approach(highlights, target.highlights, by: step)
        shadows = SceneAutoPolicy.approach(shadows, target.shadows, by: step)
        noiseReduction = SceneAutoPolicy.approach(noiseReduction, target.noiseReduction, by: step)
        sharpness = SceneAutoPolicy.approach(sharpness, target.sharpness, by: step)
    }
}

struct SceneAutoPoint: Equatable, Sendable {
    let x: Double
    let y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
    func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
    static let center = Self(x: 0.5, y: 0.5)
}

struct SceneAutoObservation: Sendable {
    var timestamp: Double
    var median: Double
    var center: Double
    var highlights: Double
    var shadows: Double
    var motion: Double
    var neutralFraction: Double
    var redOverGreen: Double
    var blueOverGreen: Double
    /// Normalized coordinates in the upright, *uncropped* preview, top-left origin.
    var face: SceneAutoPoint?
    var faceConfidence: Double

    var isValid: Bool {
        let fractions = [median, center, highlights, shadows, motion, neutralFraction, faceConfidence]
        return timestamp.isFinite && timestamp >= 0 && fractions.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && redOverGreen.isFinite && blueOverGreen.isFinite && redOverGreen > 0 && blueOverGreen > 0
            && (face?.isValid ?? true)
    }
}

struct SceneAutoSensor: Sendable {
    var iso: Double
    var duration: Double
    var minimumISO: Double
    var maximumISO: Double
    var minimumDuration: Double
    var maximumDuration: Double
    var aperture: Double
    /// AVFoundation's metered minus target exposure. Positive means too bright.
    var targetOffset: Double
    var zoom: Double
    var isAdjustingExposure: Bool
    var isAdjustingWhiteBalance: Bool
    var isAdjustingFocus: Bool
    var supportsCustomExposure: Bool

    var isValid: Bool {
        let positive = [iso, duration, minimumISO, maximumISO, minimumDuration, maximumDuration, aperture, zoom]
        return positive.allSatisfy { $0.isFinite && $0 > 0 }
            && minimumISO <= maximumISO && minimumDuration <= maximumDuration && targetOffset.isFinite
    }
    /// Estimate incident scene brightness, compensating for non-neutral exposure.
    var meteredEV100: Double { log2(aperture * aperture * 100 / (duration * iso)) + targetOffset }
}

struct SceneAutoExposure: Equatable, Sendable {
    let iso: Double
    let duration: Double
}

struct SceneAutoDecision: Sendable {
    let scene: SceneAutoScene
    let exposure: SceneAutoExposure?
    let fallbackBias: Double
    let whiteBalance: WhiteBalance
    let focus: SceneAutoPoint?
    let development: SceneAutoDevelopment
    let isMetering: Bool
    let isAdapting: Bool
    enum WhiteBalance: Sendable { case unchanged, lock, meter }
}

/// Hardware-free control policy. All time is monotonic; the session queue is its
/// sole owner. No ML scene-label flicker is allowed to drive hardware directly.
struct SceneAutoPolicy {
    static let sampleInterval = 0.4
    static let maximumSampleAge = 1.5
    static let exposureDeadband = 0.16
    static let sceneDwell = 1.2
    static let sceneCooldown = 3.0
    static let whiteBalanceCooldown = 8.0
    static let userFocusGrace = 6.0

    private(set) var scene: SceneAutoScene = .balanced
    private(set) var development = SceneAutoDevelopment()
    private var beganAt: Double?
    private var previousTime: Double?
    private var candidate: SceneAutoScene = .balanced
    private var candidateSince: Double = 0
    private var sceneChangedAt: Double = -.infinity
    private var filteredOffset: Double = 0
    private var filteredMotion: Double = 0
    private var exposureErrorSince: Double?
    private var lastExposureAt: Double = -.infinity
    private var wbReference: (red: Double, blue: Double)?
    private var wbMeteringSince: Double?
    private var wbMismatchSince: Double?
    private var lastWBMeterAt: Double = -.infinity
    private var lastFocus: SceneAutoPoint?
    private var focusCandidate: SceneAutoPoint?
    private var focusCandidateSince: Double = 0
    private var lastFocusAt: Double = -.infinity
    private var spatialChangeSince: Double?

    static func approach(_ value: Double, _ target: Double, by step: Double) -> Double {
        guard value.isFinite, target.isFinite, step.isFinite, step >= 0 else { return value.isFinite ? value : 0 }
        return value + min(max(target - value, -step), step)
    }

    /// Pauses do not catch up an accumulated exposure or finishing adjustment.
    mutating func resume() {
        beganAt = nil
        previousTime = nil
        exposureErrorSince = nil
        candidateSince = 0
        focusCandidate = nil
        lastFocus = nil
        spatialChangeSince = nil
        wbMismatchSince = nil
        wbMeteringSince = nil
        // A pause can interrupt native WB reacquisition. Warm up and lock
        // again instead of accidentally leaving continuous WB running.
        wbReference = nil
    }

    mutating func update(
        observation o: SceneAutoObservation,
        sensor s: SceneAutoSensor,
        now: Double,
        lastUserFocus: Double = -.infinity
    ) -> SceneAutoDecision? {
        guard o.isValid, s.isValid, now.isFinite, now >= o.timestamp,
              now - o.timestamp <= Self.maximumSampleAge,
              previousTime.map({ o.timestamp > $0 }) ?? true else { return nil }
        let gap = previousTime.map { o.timestamp - $0 } ?? 0
        if gap > 2.5 { resume() }
        let dt = previousTime.map { min(o.timestamp - $0, 1) } ?? Self.sampleInterval
        previousTime = o.timestamp
        if beganAt == nil {
            beganAt = o.timestamp
            filteredOffset = s.targetOffset
            filteredMotion = o.motion
            candidateSince = o.timestamp
        }
        let alpha = 1 - exp(-dt / 0.8)
        filteredOffset += alpha * (s.targetOffset - filteredOffset)
        filteredMotion += alpha * (o.motion - filteredMotion)
        let warmup = o.timestamp - (beganAt ?? o.timestamp) < 1.2
        updateScene(o, s, at: o.timestamp)

        // Scene exposure targets are intentionally restrained. A bright sky
        // should not cause the foreground or a face to be crushed to black.
        let bias: Double
        switch scene {
        case .backlit: bias = -0.15
        case .highContrast: bias = -0.35
        case .lowLight: bias = -0.20
        default: bias = 0
        }
        let error = bias - filteredOffset
        if abs(error) > Self.exposureDeadband {
            if exposureErrorSince == nil { exposureErrorSince = o.timestamp }
        } else {
            exposureErrorSince = nil
        }
        let confirmedError = exposureErrorSince.map { o.timestamp - $0 >= 0.65 } ?? false
        var exposure: SceneAutoExposure?
        if !warmup, !s.isAdjustingExposure, s.supportsCustomExposure,
           o.timestamp - lastExposureAt >= Self.sampleInterval {
            let maximumStep = (abs(error) > 1.5 ? 1.0 : 0.45) * min(dt, 0.6)
            let correction = confirmedError ? min(max(error, -maximumStep), maximumStep) : 0
            let target = Self.allocateExposure(sensor: s, scene: scene, motion: filteredMotion, correctionEV: correction)
            let isoChange = abs(log2(target.iso / s.iso))
            let shutterChange = abs(log2(target.duration / s.duration))
            // Don't resubmit hardware-quantized values or chase single-frame ISO noise.
            if isoChange > 0.08 || shutterChange > 0.08 {
                exposure = target
                lastExposureAt = o.timestamp
                // Metering is feedback from the *applied* previous request. Do
                // not integrate a stale residual after making a correction.
                filteredOffset += correction
            }
        }

        var targetDevelopment = SceneAutoDevelopment()
        if scene == .backlit || scene == .highContrast {
            targetDevelopment.highlights = -0.16
            targetDevelopment.shadows = -0.12
        }
        let noise = min(max(log2(max(s.iso / max(s.minimumISO, 50), 1)) / 6, 0), 1)
        targetDevelopment.noiseReduction = noise * 0.16
        targetDevelopment.sharpness = -noise * 0.10
        if !warmup { development.approach(targetDevelopment, seconds: dt) }

        let wb = updateWhiteBalance(o, s, warmup: warmup)
        let focus = updateFocus(o, s, warmup: warmup, lastUserFocus: lastUserFocus)
        return SceneAutoDecision(
            scene: scene, exposure: exposure, fallbackBias: bias, whiteBalance: wb, focus: focus,
            development: development, isMetering: warmup,
            isAdapting: !warmup && (confirmedError || exposure != nil || wb == .meter)
        )
    }

    /// Preserve total exposure while trading shutter time for ISO. Zoom raises
    /// the handheld shutter floor. Never force a slower motion-blurring shutter
    /// just to achieve a prettier ISO readout; at a hardware limit, stay bounded.
    static func allocateExposure(
        sensor s: SceneAutoSensor, scene: SceneAutoScene, motion: Double, correctionEV: Double
    ) -> SceneAutoExposure {
        guard s.isValid, correctionEV.isFinite, motion.isFinite else {
            return SceneAutoExposure(iso: 100, duration: 1.0 / 60)
        }
        let baseDenominator: Double
        switch scene {
        case .action: baseDenominator = 250
        case .portrait: baseDenominator = 125
        case .lowLight: baseDenominator = motion < 0.018 ? 30 : 60
        default: baseDenominator = 60
        }
        let denominator = max(baseDenominator, 30 * min(max(s.zoom, 1), 6))
        let longest = min(s.maximumDuration, max(s.minimumDuration, 1 / denominator))
        let product = s.iso * s.duration * pow(2, min(max(correctionEV, -1), 1))
        let duration = min(max(product / s.minimumISO, s.minimumDuration), longest)
        let iso = min(max(product / duration, s.minimumISO), s.maximumISO)
        return SceneAutoExposure(iso: iso, duration: duration)
    }

    private mutating func updateScene(_ o: SceneAutoObservation, _ s: SceneAutoSensor, at now: Double) {
        let next: SceneAutoScene
        // Separate entry/exit thresholds avoid flapping at every boundary.
        if filteredMotion > (scene == .action ? 0.045 : 0.085) {
            next = .action
        } else if o.face != nil && o.faceConfidence >= 0.75 {
            next = .portrait
        } else if s.meteredEV100 < (scene == .lowLight ? 6.5 : 5.5) {
            next = .lowLight
        } else if o.highlights > (scene == .backlit ? 0.025 : 0.05) && o.center < 0.28 && o.shadows > 0.18 {
            next = .backlit
        } else if o.highlights > (scene == .highContrast ? 0.035 : 0.07) && o.shadows > 0.10 {
            next = .highContrast
        } else {
            next = .balanced
        }
        if next != candidate {
            candidate = next
            candidateSince = now
        }
        if candidate != scene, now - candidateSince >= Self.sceneDwell, now - sceneChangedAt >= Self.sceneCooldown {
            scene = candidate
            sceneChangedAt = now
        }
    }

    private mutating func updateWhiteBalance(
        _ o: SceneAutoObservation, _ s: SceneAutoSensor, warmup: Bool
    ) -> SceneAutoDecision.WhiteBalance {
        guard !warmup else { return .unchanged }
        if let began = wbMeteringSince {
            guard o.timestamp - began >= 1.2, !s.isAdjustingWhiteBalance || o.timestamp - began >= 4 else { return .unchanged }
            wbMeteringSince = nil
            wbReference = (o.redOverGreen, o.blueOverGreen)
            return .lock
        }
        guard let reference = wbReference else {
            guard !s.isAdjustingWhiteBalance || o.timestamp - (beganAt ?? o.timestamp) > 4 else { return .unchanged }
            wbReference = (o.redOverGreen, o.blueOverGreen)
            lastWBMeterAt = o.timestamp
            return .lock
        }
        // Only reasonably neutral pixels are color-meter evidence. A red wall,
        // sunset, skin, or a saturated film look must not cause gray-world drift.
        let difference = max(abs(log2(o.redOverGreen / reference.red)), abs(log2(o.blueOverGreen / reference.blue)))
        guard o.neutralFraction >= 0.18, difference > 0.22, filteredMotion < 0.04 else {
            wbMismatchSince = nil
            return .unchanged
        }
        if wbMismatchSince == nil { wbMismatchSince = o.timestamp }
        guard o.timestamp - (wbMismatchSince ?? o.timestamp) >= 2,
              o.timestamp - lastWBMeterAt >= Self.whiteBalanceCooldown else { return .unchanged }
        wbMismatchSince = nil
        wbMeteringSince = o.timestamp
        lastWBMeterAt = o.timestamp
        return .meter
    }

    private mutating func updateFocus(
        _ o: SceneAutoObservation, _ s: SceneAutoSensor, warmup: Bool, lastUserFocus: Double
    ) -> SceneAutoPoint? {
        guard !warmup, !s.isAdjustingFocus, o.timestamp - lastUserFocus >= Self.userFocusGrace else { return nil }
        let target = o.faceConfidence >= 0.75 ? (o.face ?? .center) : .center
        if o.motion > 0.12 {
            if spatialChangeSince == nil { spatialChangeSince = o.timestamp }
        }
        let reframed = spatialChangeSince.map { o.timestamp - $0 > 0.8 && o.motion < 0.035 } ?? false
        let moved = lastFocus.map { $0.distance(to: target) > 0.12 } ?? true
        guard moved || reframed else { focusCandidate = nil; return nil }
        if focusCandidate.map({ $0.distance(to: target) > 0.06 }) ?? true {
            focusCandidate = target
            focusCandidateSince = o.timestamp
        }
        guard o.timestamp - focusCandidateSince >= 0.8, o.timestamp - lastFocusAt >= 2.5,
              o.motion < 0.085 || o.face != nil else { return nil }
        lastFocus = target
        lastFocusAt = o.timestamp
        focusCandidate = nil
        spatialChangeSince = nil
        return target
    }
}

/// Small sRGB thumbnail statistics. Motion subtracts the global brightness
/// change so an exposure correction is not mistaken for subject movement.
enum SceneAutoStatistics {
    static let maximumDimension = 160
    struct Result {
        let median: Double
        let center: Double
        let highlights: Double
        let shadows: Double
        let motion: Double
        let neutralFraction: Double
        let redOverGreen: Double
        let blueOverGreen: Double
        let luma: [Double]
    }
    static func measure(rgba: [UInt8], width: Int, height: Int, previousLuma: [Double]?) -> Result? {
        guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
              rgba.count == width * height * 4 else { return nil }
        let count = width * height
        var histogram = [Int](repeating: 0, count: 256)
        var luma = [Double](repeating: 0, count: count)
        var centerSum = 0.0, centerCount = 0, highlights = 0, shadows = 0
        var reds: [Double] = [], blues: [Double] = []
        for i in 0..<count {
            let r = Double(rgba[i * 4]) / 255, g = Double(rgba[i * 4 + 1]) / 255, b = Double(rgba[i * 4 + 2]) / 255
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            luma[i] = y
            histogram[min(Int(y * 255), 255)] += 1
            if max(r, g, b) >= 0.98 { highlights += 1 }
            if y < 0.12 { shadows += 1 }
            let x = Double(i % width) / Double(width), v = Double(i / width) / Double(height)
            if (0.25...0.75).contains(x), (0.25...0.75).contains(v) { centerSum += y; centerCount += 1 }
            if y > 0.18, y < 0.85, max(r, g, b) - min(r, g, b) < 0.20, g > 0.08 {
                reds.append(r / g); blues.append(b / g)
            }
        }
        var cumulative = 0, median = 0.0
        for i in histogram.indices {
            cumulative += histogram[i]
            if cumulative >= (count + 1) / 2 { median = Double(i) / 255; break }
        }
        var motion = 0.0
        if let previousLuma, previousLuma.count == count, previousLuma.allSatisfy(\.isFinite) {
            let globalChange = zip(luma, previousLuma).reduce(0) { $0 + $1.0 - $1.1 } / Double(count)
            motion = zip(luma, previousLuma).reduce(0) { $0 + abs(($1.0 - $1.1) - globalChange) } / Double(count)
        }
        reds.sort(); blues.sort()
        return Result(
            median: median, center: centerCount > 0 ? centerSum / Double(centerCount) : median,
            highlights: Double(highlights) / Double(count), shadows: Double(shadows) / Double(count),
            motion: min(motion, 1), neutralFraction: Double(reds.count) / Double(count),
            redOverGreen: reds.isEmpty ? 1 : reds[reds.count / 2], blueOverGreen: blues.isEmpty ? 1 : blues[blues.count / 2], luma: luma
        )
    }
}
