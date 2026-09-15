import Foundation

struct SmartSceneMetrics: Equatable, Sendable {
    var luminance = 0.5
    var low = 0.25
    var high = 0.75
    var saturation = 0.25
    var warmth = 0.0
    var greenFraction = 0.0
    var blueFraction = 0.0
    var clippedFraction = 0.0

    var isUsable: Bool {
        [luminance, low, high, saturation, warmth, greenFraction, blueFraction, clippedFraction].allSatisfy(\.isFinite)
            && high > 0.055 && low < 0.97
    }
    var isHighContrast: Bool { high - low > 0.65 }
    var isDark: Bool { luminance < 0.23 && low < 0.09 }

    /// Packed display-referred sRGB RGBA8. Transparent pixels are not black scene evidence.
    static func measure(rgba: [UInt8]) -> Self? {
        guard rgba.count >= 64, rgba.count.isMultiple(of: 4) else { return nil }
        var luminances: [Double] = []
        luminances.reserveCapacity(rgba.count / 4)
        var color = 0.0
        var warmth = 0.0
        var green = 0.0
        var blue = 0.0
        var clipped = 0.0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            guard rgba[offset + 3] >= 128 else { continue }
            let red = Double(rgba[offset]) / 255
            let greenValue = Double(rgba[offset + 1]) / 255
            let blueValue = Double(rgba[offset + 2]) / 255
            let maximum = max(red, greenValue, blueValue)
            let minimum = min(red, greenValue, blueValue)
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
            luminances.append(0.2126 * red + 0.7152 * greenValue + 0.0722 * blueValue)
            color += saturation
            warmth += red - blueValue
            if greenValue > red * 1.12 && greenValue > blueValue * 1.12 && saturation > 0.18 { green += 1 }
            if blueValue > red * 1.12 && blueValue > greenValue * 1.08 && saturation > 0.18 { blue += 1 }
            if minimum > 0.97 { clipped += 1 }
        }
        guard luminances.count >= 16 else { return nil }
        let count = Double(luminances.count)
        let mean = luminances.reduce(0, +) / count
        luminances.sort()
        return Self(luminance: mean,
                    low: luminances[Int(Double(luminances.count - 1) * 0.05)],
                    high: luminances[Int(Double(luminances.count - 1) * 0.95)],
                    saturation: color / count, warmth: warmth / count,
                    greenFraction: green / count, blueFraction: blue / count, clippedFraction: clipped / count)
    }
}

enum SmartSceneKind: String, CaseIterable, Sendable {
    case people, landscape, food, architecture, night, warmLight, flowers, water, snow, everyday
    var title: String {
        switch self {
        case .people: return "People"
        case .landscape: return "Nature"
        case .food: return "Food"
        case .architecture: return "Street & architecture"
        case .night: return "Low light"
        case .warmLight: return "Warm light"
        case .flowers: return "Flowers & detail"
        case .water: return "Water & sky"
        case .snow: return "Bright scenery"
        case .everyday: return "For this light"
        }
    }
}

struct SmartSceneClassification: Equatable, Sendable {
    let identifier: String
    let confidence: Double
}

struct SmartScene: Equatable, Sendable {
    let kind: SmartSceneKind
    /// Evidence strength, not a calibrated probability or UI percentage.
    let evidence: Double
    let metrics: SmartSceneMetrics
    let hasFaces: Bool

    static func interpret(metrics: SmartSceneMetrics, classifications: [SmartSceneClassification],
                          faceCount: Int = 0, faceCoverage: Double = 0) -> Self? {
        guard metrics.isUsable else { return nil }
        let vocabulary: [(SmartSceneKind, Set<String>)] = [
            (.people, ["person", "people", "portrait", "selfie", "human", "group_portrait"]),
            (.landscape, ["landscape", "nature", "forest", "mountain", "mountains", "tree", "trees", "garden", "park"]),
            (.food, ["food", "meal", "dish", "dessert", "fruit", "bread", "cake", "coffee", "drink", "beverage"]),
            (.architecture, ["architecture", "building", "buildings", "city", "cityscape", "street", "skyscraper", "bridge"]),
            (.night, ["night", "nighttime", "nightlife", "fireworks", "neon", "night_sky"]),
            (.warmLight, ["sunset", "sunrise", "dusk", "dawn", "golden_hour"]),
            (.flowers, ["flower", "flowers", "blossom", "blossoms", "floral", "plant", "plants"]),
            (.water, ["beach", "ocean", "sea", "lake", "river", "waterfall", "coast", "seascape"]),
            (.snow, ["snow", "snowy", "ice", "glacier", "skiing"])
        ]
        var evidence: [SmartSceneKind: Double] = [:]
        for observation in classifications {
            guard observation.confidence.isFinite, observation.confidence >= 0.25 else { continue }
            let normalized = observation.identifier.lowercased()
                .replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
            let tokens = Set(normalized.split(separator: "_").map(String.init)).union([normalized])
            for (kind, labels) in vocabulary where !tokens.isDisjoint(with: labels) {
                // Correlated synonyms must not add up to artificial certainty.
                evidence[kind] = max(evidence[kind, default: 0], min(observation.confidence, 1))
            }
        }
        if faceCount > 0 {
            let coverage = faceCoverage.isFinite ? max(0, min(faceCoverage, 1)) : 0
            evidence[.people] = max(evidence[.people, default: 0], coverage >= 0.015 ? 0.98 : 0.70)
        }
        if metrics.isDark { evidence[.night] = max(evidence[.night, default: 0], 0.48) }
        // Describe the visible palette, not an asserted location or time of day.
        if metrics.warmth > 0.12 && metrics.saturation > 0.18 && faceCount == 0 && evidence[.food, default: 0] < 0.35 {
            evidence[.warmLight] = max(evidence[.warmLight, default: 0], 0.40)
        }
        let strongest = SmartSceneKind.allCases.filter { $0 != .everyday }.max {
            evidence[$0, default: 0] < evidence[$1, default: 0]
        }
        let strength = strongest.map { evidence[$0, default: 0] } ?? 0
        return Self(kind: strength >= 0.35 ? strongest ?? .everyday : .everyday,
                    evidence: strength, metrics: metrics, hasFaces: faceCount > 0)
    }
}

enum SmartRecipeIntent: String, CaseIterable, Sendable {
    case balanced, natural, vivid, cinematic, monochrome
    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .natural: return "Natural"
        case .vivid: return "Vivid"
        case .cinematic: return "Cinema"
        case .monochrome: return "B&W"
        }
    }
}

/// Projection of the effective recipe controls, never a match based on recipe names.
struct SmartRecipeProfile: Equatable, Sendable {
    let id: String
    let family: String
    var contrast = 1.0
    var saturation = 1.0
    var highlights = 0.0
    var grain = 0.0
    var warmth = 0.0
    var tint = 0.0
    var exposure = 0.0
    var highlightProtection = 0.0
    var isMonochrome: Bool { family.hasPrefix("acros") || family == "monochrome" || family == "sepia" }
    var isValid: Bool {
        !id.isEmpty && [contrast, saturation, highlights, grain, warmth, tint, exposure, highlightProtection].allSatisfy(\.isFinite)
    }
}

struct SmartRecipeMatch: Identifiable, Equatable, Sendable {
    let id: String
    let score: Double
    let reason: String
}

enum SmartRecipeEngine {
    static func rank(scene: SmartScene, profiles: [SmartRecipeProfile], intent: SmartRecipeIntent = .balanced,
                     favoriteIDs: Set<String> = [], limit: Int = 3) -> [SmartRecipeMatch] {
        guard scene.metrics.isUsable, limit > 0 else { return [] }
        var seen: Set<String> = []
        var candidates: [(profile: SmartRecipeProfile, score: Double)] = []
        for profile in profiles where profile.isValid {
            guard seen.insert(profile.id).inserted else { continue }
            if intent == .monochrome {
                guard profile.isMonochrome, profile.family != "sepia" else { continue }
            } else if intent != .balanced && profile.isMonochrome { continue }
            var score = affinity(for: profile.family, scene: scene.kind)
            let targetContrast: Double = scene.hasFaces || scene.metrics.isHighContrast || scene.metrics.isDark ? 0.98 : 1.06
            let targetSaturation: Double = intent == .vivid ? 1.16 : scene.metrics.saturation > 0.55 ? 0.98 : 1.06
            score -= min(abs(profile.contrast - targetContrast), 2) * 25
            score -= min(abs(profile.saturation - targetSaturation), 2) * 14
            score -= min(abs(profile.exposure), 4) * 6
            score -= min(abs(profile.tint), 1) * 5
            if scene.hasFaces || scene.kind == .food {
                score -= max(0, profile.saturation - 1.15) * 28
                score -= min(abs(profile.warmth), 1) * 12
                score -= max(0, profile.contrast - 1.08) * 30
                if profile.isMonochrome && intent != .monochrome { score -= 20 }
            }
            if scene.metrics.isHighContrast || scene.metrics.clippedFraction > 0.02 {
                score += min(max(profile.highlightProtection, 0), 0.5) * 20
                score -= min(max(profile.highlights, -0.5), 0.5) * 10
            }
            if scene.metrics.isDark {
                score -= min(max(profile.grain, 0), 1) * 18
                score -= max(0, profile.contrast - 1.05) * 20
            }
            switch intent {
            case .balanced:
                if profile.isMonochrome { score -= 10 }
            case .natural:
                score -= abs(profile.saturation - 1) * 30 + abs(profile.warmth) * 22 + max(0, profile.grain) * 10
                if ["provia", "standard", "realaAce", "proNegStandard", "compactDigital"].contains(profile.family) { score += 12 }
            case .vivid:
                if profile.family == "velvia" { score += 20 }
            case .cinematic:
                if profile.family == "eterna" { score += 24 }
                if ["classicChrome", "classicNegative", "eternaBleachBypass"].contains(profile.family) { score += 12 }
                score -= abs(profile.saturation - 0.90) * 12
            case .monochrome: break
            }
            if favoriteIDs.contains(profile.id) { score += 2 }
            guard score.isFinite else { continue }
            candidates.append((profile, score))
        }
        var selected: [(profile: SmartRecipeProfile, score: Double)] = []
        while selected.count < min(limit, 3) && !candidates.isEmpty {
            candidates.sort { left, right in
                let leftScore = left.score - diversityPenalty(left.profile, selected: selected.map(\.profile))
                let rightScore = right.score - diversityPenalty(right.profile, selected: selected.map(\.profile))
                return leftScore == rightScore ? left.profile.id < right.profile.id : leftScore > rightScore
            }
            let candidate = candidates.removeFirst()
            if intent != .monochrome && candidate.profile.isMonochrome && selected.contains(where: { $0.profile.isMonochrome }) { continue }
            selected.append(candidate)
        }
        return selected.map { SmartRecipeMatch(id: $0.profile.id, score: $0.score, reason: reason(for: $0.profile, scene: scene)) }
    }

    private static func diversityPenalty(_ profile: SmartRecipeProfile, selected: [SmartRecipeProfile]) -> Double {
        selected.contains(where: { $0.family == profile.family }) ? 11 : 0
    }
    private static func affinity(for family: String, scene: SmartSceneKind) -> Double {
        let preferred: [String]
        switch scene {
        case .people: preferred = ["astia", "proNegStandard", "realaAce", "proNegative", "nostalgicNegative"]
        case .landscape: preferred = ["velvia", "provia", "realaAce", "standard", "classicChrome"]
        case .food: preferred = ["realaAce", "provia", "astia", "compactDigital", "standard"]
        case .architecture: preferred = ["classicChrome", "classicNegative", "proNegative", "acros", "eterna"]
        case .night: preferred = ["eterna", "proNegStandard", "realaAce", "classicChrome", "compactDigital"]
        case .warmLight: preferred = ["nostalgicNegative", "classicNegative", "astia", "eterna", "provia"]
        case .flowers: preferred = ["astia", "velvia", "provia", "realaAce", "proNegStandard"]
        case .water: preferred = ["provia", "velvia", "realaAce", "classicChrome", "standard"]
        case .snow: preferred = ["realaAce", "provia", "proNegStandard", "astia", "standard"]
        case .everyday: preferred = ["realaAce", "provia", "compactDigital", "proNegStandard", "standard"]
        }
        guard let index = preferred.firstIndex(of: family) else { return 18 }
        return 40 - Double(index) * 3
    }
    private static func reason(for profile: SmartRecipeProfile, scene: SmartScene) -> String {
        if profile.isMonochrome { return "A monochrome alternative emphasizing light, shape, and texture." }
        if scene.metrics.isHighContrast && (profile.highlightProtection > 0.10 || profile.highlights < 0) {
            return "A gentler highlight curve for this contrasty scene."
        }
        switch scene.kind {
        case .people: return profile.contrast <= 1.08 ? "Gentle contrast and color for people." : "More defined contrast for an expressive portrait."
        case .landscape: return "Color separation for foliage and outdoor scenery."
        case .food: return "A color-first look for food and tabletop details."
        case .architecture: return "Restrained tones for streets, lines, and texture."
        case .night: return profile.grain <= 0.20 ? "Restrained grain for this low-light scene." : "A textured, atmospheric low-light alternative."
        case .warmLight: return "A film palette that complements this scene's warm tones."
        case .flowers: return "Color and contrast for flowers and small details."
        case .water: return "Color separation for water and coastal scenery."
        case .snow: return "Balanced color for bright scenery."
        case .everyday: return "A versatile starting point for the light and color in this frame."
        }
    }
}

/// Two observations and a minimum dwell prevent flicker while framing.
struct SmartRecipeStabilizer: Sendable {
    private(set) var displayed: String?
    private var pending: String?
    private var repetitions = 0
    private var lastChange = -Double.infinity
    mutating func shouldPublish(signature: String, now: TimeInterval, force: Bool = false) -> Bool {
        guard now.isFinite else { return false }
        guard signature != displayed else { pending = nil; repetitions = 0; return false }
        if signature == pending { repetitions += 1 } else { pending = signature; repetitions = 1 }
        guard force || (repetitions >= 2 && now - lastChange >= 3.5) else { return false }
        displayed = signature
        lastChange = now
        pending = nil
        repetitions = 0
        return true
    }
    mutating func reset() { self = Self() }
}

struct SmartRecipeUndo: Equatable, Sendable {
    let previousID: String
    let appliedID: String
    func target(currentID: String, availableIDs: Set<String>) -> String? {
        guard currentID == appliedID, availableIDs.contains(previousID) else { return nil }
        return previousID
    }
}

/// Invalidation does not release an in-flight lease. Restart cannot queue retained camera buffers.
struct SmartRecipeAnalysisGate: Sendable {
    struct Ticket: Equatable, Sendable {
        let generation: UInt64
        let serial: UInt64
    }
    private var generation: UInt64 = 0
    private var serial: UInt64 = 0
    private(set) var inFlight: Ticket?
    private var nextAllowedTime = 0.0
    mutating func begin(now: TimeInterval, interval: TimeInterval) -> Ticket? {
        guard now.isFinite, interval.isFinite, interval > 0, inFlight == nil, now >= nextAllowedTime else { return nil }
        serial &+= 1
        let ticket = Ticket(generation: generation, serial: serial)
        inFlight = ticket
        nextAllowedTime = now + interval
        return ticket
    }
    mutating func finish(_ ticket: Ticket) -> Bool {
        guard inFlight == ticket else { return false }
        inFlight = nil
        return ticket.generation == generation
    }
    mutating func invalidate() { generation &+= 1; nextAllowedTime = 0 }
}
