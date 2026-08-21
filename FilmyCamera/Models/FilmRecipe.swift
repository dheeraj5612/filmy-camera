import Foundation
import SwiftUI

/// A film-inspired set of camera and finishing controls.
///
/// The values intentionally mirror the public vocabulary used by modern film
/// cameras. They are data, rather than a collection of opaque filter names, so
/// the renderer and the UI can both inspect the look.
public struct FilmRecipe: Identifiable, Codable, Hashable, Sendable {
    /// Version of the persisted recipe envelope. Version 1 was the implicit
    /// pre-provenance format; version 2 records provenance explicitly; version
    /// 3 records user edits and renderer compatibility metadata; version 4
    /// adds the canonical camera mode controls introduced by the fidelity pass;
    /// version 5 adds persisted Kelvin white-balance control.
    public static let currentSchemaVersion = 5
    public static let rendererVersion = "core-image-parametric-v1"

    /// The product-level disclosure that accompanies every current recipe.
    /// It intentionally rules out an exact-output or hardware-calibration
    /// claim.
    public static let independentApproximationDisclaimer =
        "Filmy Camera is an independent implementation inspired by public Fujifilm terminology and controls. Its renders are original approximations, not pixel-identical Fujifilm camera output. It is not affiliated with, endorsed by, or calibrated to Fujifilm, and it contains no proprietary LUTs, firmware, or calibration data."

    /// Product-specific disclosure for the compact-camera look. The recipe
    /// uses only public Canon specifications and control names as references;
    /// it does not contain Canon Picture Style data or camera calibration.
    public static let g7XApproximationDisclaimer =
        "G7 X Compact is an independent, original approximation inspired by public Canon PowerShot G7 X Mark III specifications. It cannot reproduce that camera's one-inch sensor, lens, DIGIC processing, or depth of field, is not pixel-identical Canon output, and is not affiliated with, endorsed by, or calibrated to Canon."

    /// Disclosure for recipes decoded from the pre-provenance persistence
    /// format. The old record is retained for compatibility, but its origin
    /// cannot be reconstructed from the stored bytes alone.
    public static let legacyProvenanceDisclaimer =
        "This recipe predates provenance metadata. Its source and calibration history cannot be verified from the stored record; do not present it as an exact hardware match."

    public enum FilmBase: String, CaseIterable, Codable, Hashable, Sendable {
        case standard
        case provia
        case classicChrome
        case velvia
        case astia
        case proNegative
        case proNegStandard
        case eterna
        case eternaBleachBypass
        case acros
        case acrosYellow
        case acrosRed
        case acrosGreen
        case classicNegative
        case nostalgicNegative
        case realaAce
        case compactDigital
        case monochrome
        case sepia

        public var displayName: String {
            switch self {
            case .standard, .provia: return "Natural Standard"
            case .classicChrome: return "Muted Color"
            case .velvia: return "Vivid Slide"
            case .astia: return "Soft Portrait"
            case .proNegative: return "Defined Negative"
            case .proNegStandard: return "Neutral Portrait"
            case .eterna: return "Cinema Soft"
            case .eternaBleachBypass: return "Silver Cinema"
            case .acros: return "Neutral Monochrome"
            case .acrosYellow: return "Yellow Monochrome"
            case .acrosRed: return "Red Monochrome"
            case .acrosGreen: return "Green Monochrome"
            case .classicNegative: return "Warm Negative"
            case .nostalgicNegative: return "Memory Negative"
            case .realaAce: return "Natural Negative"
            case .compactDigital: return "Premium Compact"
            case .monochrome: return "Fine Monochrome"
            case .sepia: return "Sepia Archive"
            }
        }

        /// Canonical public camera vocabulary retained separately from the
        /// product's more inviting recipe names.
        public var officialName: String {
            switch self {
            case .standard, .provia: return "PROVIA/STANDARD"
            case .classicChrome: return "CLASSIC CHROME"
            case .velvia: return "Velvia/VIVID"
            case .astia: return "ASTIA/SOFT"
            case .proNegative: return "PRO Neg. Hi"
            case .proNegStandard: return "PRO Neg. Std"
            case .eterna: return "ETERNA/CINEMA"
            case .eternaBleachBypass: return "ETERNA BLEACH BYPASS"
            case .acros, .acrosYellow, .acrosRed, .acrosGreen: return "ACROS"
            case .classicNegative: return "CLASSIC Neg."
            case .nostalgicNegative: return "NOSTALGIC Neg."
            case .realaAce: return "REALA ACE"
            case .compactDigital: return "STANDARD"
            case .monochrome: return "MONOCHROME"
            case .sepia: return "SEPIA"
            }
        }

        /// Public filter vocabulary mapped to an original channel-mix
        /// approximation. The values are intentionally inspectable rather
        /// than hidden in renderer-only conditionals.
        public var monochromeFilter: MonochromeFilter? {
            switch self {
            case .acros:
                return .neutral
            case .acrosYellow:
                return .yellow
            case .acrosRed:
                return .red
            case .acrosGreen:
                return .green
            case .monochrome:
                return .neutral
            default:
                return nil
            }
        }

        /// Whether this base exposes Fujifilm-style monochromatic color axes.
        /// Sepia intentionally has no channel-mix filter because its warm
        /// tone is produced by the base transform, but it still supports the
        /// same warm/cool and green/magenta controls.
        public var supportsMonochromaticColorAxes: Bool {
            switch self {
            case .acros, .acrosYellow, .acrosRed, .acrosGreen, .monochrome, .sepia:
                return true
            default:
                return false
            }
        }
    }

    public enum MonochromeFilter: String, CaseIterable, Codable, Hashable, Sendable {
        case neutral
        case yellow
        case red
        case green

        /// Display-referred sRGB RGB weights for the filter's luminance
        /// response. This is an original approximation of the public filter
        /// intent, not proprietary Fujifilm calibration data.
        public var channelWeights: (red: Double, green: Double, blue: Double) {
            switch self {
            case .neutral:
                return (0.2126, 0.7152, 0.0722)
            case .yellow:
                return (0.30, 0.66, 0.04)
            case .red:
                return (0.48, 0.47, 0.05)
            case .green:
                return (0.16, 0.76, 0.08)
            }
        }
    }

    /// Public Fujifilm-style dynamic-range modes. These are expressed as
    /// capture/render intent; JPEG input cannot recover highlights that were
    /// already clipped by the source camera.
    public enum DynamicRange: Int, CaseIterable, Codable, Hashable, Sendable {
        case auto = 0
        case dr100 = 100
        case dr200 = 200
        case dr400 = 400

        public var displayName: String {
            switch self {
            case .auto: return "AUTO"
            case .dr100, .dr200, .dr400: return "DR\(rawValue)"
            }
        }

        var highlightProtection: Double {
            switch self {
            case .auto: return 0.10
            case .dr100: return 0
            case .dr200: return 0.16
            case .dr400: return 0.30
            }
        }
    }

    /// Public D Range Priority modes. Hardware cameras use this setting to
    /// automatically balance highlight and shadow protection; the renderer
    /// applies a deterministic approximation because an iPhone JPEG cannot
    /// recover clipped sensor data or inspect the camera's ISO decision.
    public enum DRangePriority: String, CaseIterable, Codable, Hashable, Sendable {
        case auto
        case strong
        case weak
        case off

        public var displayName: String {
            switch self {
            case .auto: return "AUTO"
            case .strong: return "Strong"
            case .weak: return "Weak"
            case .off: return "Off"
            }
        }

        var highlightProtection: Double {
            switch self {
            case .auto: return 0.12
            case .strong: return 0.24
            case .weak: return 0.12
            case .off: return 0
            }
        }
    }

    /// White-balance choices exposed by current Fujifilm image-quality menus.
    /// The app keeps a normalized fine-tune shift alongside the mode and a
    /// persisted Kelvin value for the explicit Color Temperature mode.
    public enum WhiteBalanceMode: String, CaseIterable, Codable, Hashable, Sendable {
        case auto
        case whitePriority
        case ambiencePriority
        case daylight
        case shade
        case fluorescent1
        case fluorescent2
        case fluorescent3
        case incandescent
        case underwater
        case custom1
        case custom2
        case custom3
        case colorTemperature

        public var displayName: String {
            switch self {
            case .auto: return "AUTO"
            case .whitePriority: return "White priority"
            case .ambiencePriority: return "Ambience priority"
            case .daylight: return "Daylight"
            case .shade: return "Shade"
            case .fluorescent1: return "Fluorescent 1"
            case .fluorescent2: return "Fluorescent 2"
            case .fluorescent3: return "Fluorescent 3"
            case .incandescent: return "Incandescent"
            case .underwater: return "Underwater"
            case .custom1: return "Custom 1"
            case .custom2: return "Custom 2"
            case .custom3: return "Custom 3"
            case .colorTemperature: return "Color temperature"
            }
        }

        /// Original normalized offsets used when a mode has a stable visual
        /// bias. AUTO and custom slots defer entirely to the editable shifts.
        var temperatureBias: Double {
            switch self {
            case .ambiencePriority: return 0.04
            case .shade: return 0.12
            case .fluorescent1: return -0.03
            case .fluorescent2: return -0.08
            case .fluorescent3: return -0.12
            case .incandescent: return 0.18
            case .underwater: return -0.08
            default: return 0
            }
        }

        var tintBias: Double {
            switch self {
            case .fluorescent1: return 0.01
            case .fluorescent2: return 0.02
            case .fluorescent3: return 0.03
            default: return 0
            }
        }
    }

    /// The public FX Blue control has the three states exposed by Fujifilm's
    /// camera UI. The scalar bridge keeps older persisted recipes readable.
    public enum FXBlueLevel: Int, CaseIterable, Codable, Hashable, Sendable {
        case off
        case weak
        case strong

        public var displayName: String {
            switch self {
            case .off: return "Off"
            case .weak: return "Weak"
            case .strong: return "Strong"
            }
        }

        /// Renderer scalar used by the original parametric approximation.
        public var scalarValue: Double {
            switch self {
            case .off: return 0
            case .weak: return 0.5
            case .strong: return 1
            }
        }

        /// Maps the old signed scalar representation to the public control.
        /// Negative legacy values are intentionally treated as Off.
        public init(scalarValue: Double) {
            if scalarValue >= 0.75 {
                self = .strong
            } else if scalarValue > 0 {
                self = .weak
            } else {
                self = .off
            }
        }
    }

    /// Fujifilm-style Color Chrome strength. Built-in looks use only these
    /// public camera states; the scalar bridge remains intentionally tolerant
    /// so older user-authored recipes with intermediate values still decode.
    public enum ColorChromeLevel: Int, CaseIterable, Codable, Hashable, Sendable {
        case off
        case weak
        case strong

        public var displayName: String {
            switch self {
            case .off: return "Off"
            case .weak: return "Weak"
            case .strong: return "Strong"
            }
        }

        public var scalarValue: Double {
            switch self {
            case .off: return 0
            case .weak: return 0.5
            case .strong: return 1
            }
        }

        public init(scalarValue: Double) {
            if scalarValue >= 0.75 {
                self = .strong
            } else if scalarValue > 0 {
                self = .weak
            } else {
                self = .off
            }
        }
    }

    /// Fujifilm-style Grain Effect roughness. Built-in looks use only the
    /// public Off/Weak/Strong states; intermediate legacy values remain
    /// renderable for user-authored recipes.
    public enum GrainEffectLevel: Int, CaseIterable, Codable, Hashable, Sendable {
        case off
        case weak
        case strong

        public var displayName: String {
            switch self {
            case .off: return "Off"
            case .weak: return "Weak"
            case .strong: return "Strong"
            }
        }

        public var scalarValue: Double {
            switch self {
            case .off: return 0
            case .weak: return 0.5
            case .strong: return 1
            }
        }

        public init(scalarValue: Double) {
            if scalarValue >= 0.75 {
                self = .strong
            } else if scalarValue > 0 {
                self = .weak
            } else {
                self = .off
            }
        }
    }

    /// Fujifilm's two public grain-size choices. The built-in library stores
    /// these canonical scalars instead of arbitrary intermediate strengths.
    public enum GrainSizeLevel: Int, CaseIterable, Codable, Hashable, Sendable {
        case small
        case large

        public var displayName: String {
            switch self {
            case .small: return "Small"
            case .large: return "Large"
            }
        }

        public var scalarValue: Double {
            switch self {
            case .small: return 0.75
            case .large: return 1.5
            }
        }

        public init(scalarValue: Double) {
            self = scalarValue >= 1.0 ? .large : .small
        }
    }

    /// First-party public references used for terminology and control scope.
    /// These references document vocabulary and behavior, not transferable
    /// LUT values, sensor calibration, or proprietary implementation data.
    public enum PublicReference: String, CaseIterable, Codable, Hashable, Sendable {
        case xt5ImageQualitySetting
        case filmSimulationOverview
        case g7XMarkIIITechnicalSpecifications
        case g7XMarkIIICameraMuseum

        public var title: String {
            switch self {
            case .xt5ImageQualitySetting:
                return "FUJIFILM X-T5 Image Quality Setting"
            case .filmSimulationOverview:
                return "FUJIFILM Film Simulation overview"
            case .g7XMarkIIITechnicalSpecifications:
                return "Canon PowerShot G7 X Mark III technical specifications"
            case .g7XMarkIIICameraMuseum:
                return "Canon Camera Museum: PowerShot G7 X Mark III"
            }
        }

        public var url: String {
            switch self {
            case .xt5ImageQualitySetting:
                return "https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/"
            case .filmSimulationOverview:
                return "https://www.fujifilm-x.com/en-us/products/film-simulation/"
            case .g7XMarkIIITechnicalSpecifications:
                return "https://www.usa.canon.com/support/p/powershot-g7-x-mark-iii"
            case .g7XMarkIIICameraMuseum:
                return "https://global.canon/en/c-museum/product/dcc884.html"
            }
        }

        public var scope: String {
            switch self {
            case .xt5ImageQualitySetting:
                return "Public names, option descriptions, and control groupings"
            case .filmSimulationOverview:
                return "Public film-simulation names and subject-oriented descriptions"
            case .g7XMarkIIITechnicalSpecifications:
                return "Public sensor, lens, white-balance, and Picture Style option specifications"
            case .g7XMarkIIICameraMuseum:
                return "Public compact-camera imaging, low-light, and lens characteristics"
            }
        }
    }

    public static let fujifilmPublicReferences: [PublicReference] = [
        .xt5ImageQualitySetting,
        .filmSimulationOverview
    ]

    public static let g7XPublicReferences: [PublicReference] = [
        .g7XMarkIIITechnicalSpecifications,
        .g7XMarkIIICameraMuseum
    ]

    /// Machine-readable provenance attached to a recipe and persisted with
    /// saved-frame metadata. The enum surface contains no exact-match or
    /// hardware-calibrated state by design.
    public struct Provenance: Codable, Hashable, Sendable {
        public enum Source: String, CaseIterable, Codable, Hashable, Sendable {
            case publicOfficialDocumentation
            case publicCanonDocumentation
            case userModified
            case legacyRecordWithoutProvenance
        }

        public enum Implementation: String, CaseIterable, Codable, Hashable, Sendable {
            case originalParametricApproximation
            case unknownLegacyRecord
        }

        public enum Calibration: String, CaseIterable, Codable, Hashable, Sendable {
            case notCalibratedToFujifilmHardware
            case notCalibratedToCanonHardware
            case unknownLegacyRecord
        }

        public let source: Source
        public let implementation: Implementation
        public let calibration: Calibration
        public let references: [PublicReference]
        public let parentRecipeID: String?
        public let rendererVersion: String

        public init(
            source: Source,
            implementation: Implementation,
            calibration: Calibration,
            references: [PublicReference],
            parentRecipeID: String? = nil,
            rendererVersion: String = FilmRecipe.rendererVersion
        ) {
            self.source = source
            self.implementation = implementation
            self.calibration = calibration
            self.references = references
            self.parentRecipeID = parentRecipeID
            self.rendererVersion = rendererVersion
        }

        private enum CodingKeys: String, CodingKey {
            case source
            case implementation
            case calibration
            case references
            case parentRecipeID
            case rendererVersion
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = try container.decode(Source.self, forKey: .source)
            implementation = try container.decode(Implementation.self, forKey: .implementation)
            calibration = try container.decode(Calibration.self, forKey: .calibration)
            references = try container.decode([PublicReference].self, forKey: .references)
            parentRecipeID = try container.decodeIfPresent(String.self, forKey: .parentRecipeID)
            // A missing renderer version is legacy metadata, not evidence that
            // the record is compatible with the current renderer.
            rendererVersion = try container.decodeIfPresent(String.self, forKey: .rendererVersion)
                ?? "legacy-unknown"
        }

        public var disclaimer: String {
            switch implementation {
            case .originalParametricApproximation:
                return calibration == .notCalibratedToCanonHardware
                    ? FilmRecipe.g7XApproximationDisclaimer
                    : FilmRecipe.independentApproximationDisclaimer
            case .unknownLegacyRecord:
                return FilmRecipe.legacyProvenanceDisclaimer
            }
        }

        /// A complete record has the expected source, implementation status,
        /// calibration disclosure, and the complete official reference set.
        public var isComplete: Bool {
            let hasMatchingSourceAndReferences: Bool
            switch (source, calibration) {
            case (.publicOfficialDocumentation, .notCalibratedToFujifilmHardware),
                 (.userModified, .notCalibratedToFujifilmHardware):
                hasMatchingSourceAndReferences = references == FilmRecipe.fujifilmPublicReferences
            case (.publicCanonDocumentation, .notCalibratedToCanonHardware),
                 (.userModified, .notCalibratedToCanonHardware):
                hasMatchingSourceAndReferences = references == FilmRecipe.g7XPublicReferences
            default:
                hasMatchingSourceAndReferences = false
            }

            return hasMatchingSourceAndReferences
                && implementation == .originalParametricApproximation
                && rendererVersion == FilmRecipe.rendererVersion
        }
    }

    public static let currentProvenance = Provenance(
        source: .publicOfficialDocumentation,
        implementation: .originalParametricApproximation,
        calibration: .notCalibratedToFujifilmHardware,
        references: fujifilmPublicReferences
    )

    public static let g7XProvenance = Provenance(
        source: .publicCanonDocumentation,
        implementation: .originalParametricApproximation,
        calibration: .notCalibratedToCanonHardware,
        references: g7XPublicReferences
    )

    /// Used only when decoding the old JSON shape that had no provenance
    /// fields. It keeps old user data readable without laundering uncertainty
    /// into the current provenance claim.
    public static let legacyProvenance = Provenance(
        source: .legacyRecordWithoutProvenance,
        implementation: .unknownLegacyRecord,
        calibration: .unknownLegacyRecord,
        references: []
    )

    /// Units used by the stable numeric control contract.
    public enum ControlUnit: String, CaseIterable, Codable, Hashable, Sendable {
        case exposureEV
        case toneOffset
        case multiplier
        case normalizedStrength
        case normalizedOffset
        case normalizedSize
        case kelvin
    }

    /// Public semantics for every numeric field that participates in a
    /// recipe. `editorRange` is the app's normalized editing contract; the
    /// renderer may still receive an out-of-range draft and clamp at its
    /// rendering boundary for resilience.
    public enum Control: String, CaseIterable, Codable, Hashable, Sendable {
        case exposure
        case highlights
        case shadows
        case color
        case contrast
        case colorChrome
        case blueResponse
        case fxBlue
        case temperature
        case tint
        case colorTemperature
        case monochromaticWarmCool
        case monochromaticGreenMagenta
        case sharpness
        case noiseReduction
        case clarity
        case grain
        case grainSize
        case vignette
        case halation
        case paletteRedBias
        case paletteGreenBias
        case paletteBlueBias
        case paletteRedGreenMix
        case paletteGreenBlueMix
        case paletteBlueRedMix
        case paletteSaturation

        public var displayName: String {
            switch self {
            case .exposure: return "Exposure"
            case .highlights: return "Highlights"
            case .shadows: return "Shadows"
            case .color: return "Color"
            case .contrast: return "Contrast"
            case .colorChrome: return "Color Chrome"
            case .blueResponse: return "Blue response"
            case .fxBlue: return "Color Chrome FX Blue"
            case .temperature: return "White balance temperature shift"
            case .tint: return "White balance tint shift"
            case .colorTemperature: return "White balance color temperature"
            case .monochromaticWarmCool: return "Monochromatic warm-cool"
            case .monochromaticGreenMagenta: return "Monochromatic green-magenta"
            case .sharpness: return "Sharpness"
            case .noiseReduction: return "High ISO noise reduction"
            case .clarity: return "Clarity"
            case .grain: return "Grain roughness"
            case .grainSize: return "Grain size"
            case .vignette: return "Vignette"
            case .halation: return "Halation"
            case .paletteRedBias: return "Palette red bias"
            case .paletteGreenBias: return "Palette green bias"
            case .paletteBlueBias: return "Palette blue bias"
            case .paletteRedGreenMix: return "Palette red-green mix"
            case .paletteGreenBlueMix: return "Palette green-blue mix"
            case .paletteBlueRedMix: return "Palette blue-red mix"
            case .paletteSaturation: return "Palette saturation"
            }
        }

        public var unit: ControlUnit {
            switch self {
            case .exposure:
                return .exposureEV
            case .highlights, .shadows:
                return .toneOffset
            case .color, .contrast, .paletteSaturation:
                return .multiplier
            case .colorChrome, .blueResponse, .fxBlue, .noiseReduction, .grain, .vignette, .halation:
                return .normalizedStrength
            case .temperature, .tint, .sharpness, .clarity, .paletteRedBias, .paletteGreenBias,
                 .paletteBlueBias, .paletteRedGreenMix, .paletteGreenBlueMix, .paletteBlueRedMix,
                 .monochromaticWarmCool, .monochromaticGreenMagenta:
                return .normalizedOffset
            case .colorTemperature:
                return .kelvin
            case .grainSize:
                return .normalizedSize
            }
        }

        /// These ranges are intentionally app-level normalized semantics, not
        /// claims that Fujifilm hardware uses the same numeric scale.
        public var editorRange: ClosedRange<Double> {
            switch self {
            case .exposure: return -2.0...2.0
            case .highlights, .shadows: return -1.0...1.0
            case .color: return 0.0...2.0
            case .contrast: return 0.5...1.7
            case .colorChrome: return 0.0...1.0
            case .blueResponse, .fxBlue: return -1.0...1.0
            case .temperature, .tint: return -1.0...1.0
            case .colorTemperature: return 2500.0...10000.0
            case .monochromaticWarmCool, .monochromaticGreenMagenta: return -1.0...1.0
            case .sharpness, .clarity: return -1.0...1.0
            case .noiseReduction: return 0.0...1.0
            case .grain: return 0.0...1.0
            case .grainSize: return 0.35...2.5
            case .vignette, .halation: return 0.0...1.0
            case .paletteRedBias, .paletteGreenBias, .paletteBlueBias,
                 .paletteRedGreenMix, .paletteGreenBlueMix, .paletteBlueRedMix:
                return -1.0...1.0
            case .paletteSaturation: return 0.0...2.0
            }
        }

        public var semanticDescription: String {
            switch self {
            case .exposure:
                return "Exposure compensation in EV; zero is neutral."
            case .highlights, .shadows:
                return "Signed tone-curve offset; zero is neutral and the sign is preserved."
            case .color:
                return "Color-density multiplier; 1.0 is neutral."
            case .contrast:
                return "Contrast multiplier; 1.0 is neutral."
            case .colorChrome:
                return "Three-state Color Chrome control: Off, Weak, or Strong."
            case .blueResponse:
                return "Signed normalized blue-channel response used by the original approximation."
            case .fxBlue:
                return "Three-state FX Blue control: Off, Weak, or Strong; negative legacy values render as Off."
            case .temperature:
                return "Normalized white-balance temperature shift; positive values warm the image."
            case .tint:
                return "Normalized white-balance tint shift; positive values move toward magenta."
            case .colorTemperature:
                return "Color temperature in Kelvin; the public camera range is 2500 K through 10000 K."
            case .monochromaticWarmCool:
                return "Normalized ACROS, MONOCHROME, or SEPIA warm-to-cool color axis."
            case .monochromaticGreenMagenta:
                return "Normalized ACROS, MONOCHROME, or SEPIA green-to-magenta color axis."
            case .sharpness:
                return "Signed normalized edge-definition adjustment."
            case .noiseReduction:
                return "Normalized smoothing amount; zero leaves this stage off."
            case .clarity:
                return "Signed normalized local-definition adjustment."
            case .grain:
                return "Three-state Grain Effect control: Off, Weak, or Strong."
            case .grainSize:
                return "Two-state Grain Size control: Small or Large."
            case .vignette:
                return "Normalized edge-darkening amount."
            case .halation:
                return "Normalized highlight-spread amount."
            case .paletteRedBias, .paletteGreenBias, .paletteBlueBias:
                return "Signed normalized channel bias in the original palette transform."
            case .paletteRedGreenMix, .paletteGreenBlueMix, .paletteBlueRedMix:
                return "Signed normalized cross-channel mix in the original palette transform."
            case .paletteSaturation:
                return "Palette-stage saturation multiplier; 1.0 is neutral."
            }
        }

        public func value(in recipe: FilmRecipe) -> Double {
            switch self {
            case .exposure: return recipe.exposure
            case .highlights: return recipe.tone.highlight
            case .shadows: return recipe.tone.shadow
            case .color: return recipe.saturation
            case .contrast: return recipe.contrast
            case .colorChrome: return recipe.colorChrome
            case .blueResponse: return recipe.blueResponse
            case .fxBlue: return recipe.fxBlue
            case .temperature: return recipe.whiteBalance.temperature
            case .tint: return recipe.whiteBalance.tint
            case .colorTemperature: return recipe.whiteBalance.kelvin
            case .monochromaticWarmCool: return recipe.monochromaticColor.warmCool
            case .monochromaticGreenMagenta: return recipe.monochromaticColor.greenMagenta
            case .sharpness: return recipe.sharpness
            case .noiseReduction: return recipe.noiseReduction
            case .clarity: return recipe.clarity
            case .grain: return recipe.grain
            case .grainSize: return recipe.grainSize
            case .vignette: return recipe.vignette
            case .halation: return recipe.halation
            case .paletteRedBias: return recipe.palette.redBias
            case .paletteGreenBias: return recipe.palette.greenBias
            case .paletteBlueBias: return recipe.palette.blueBias
            case .paletteRedGreenMix: return recipe.palette.redGreenMix
            case .paletteGreenBlueMix: return recipe.palette.greenBlueMix
            case .paletteBlueRedMix: return recipe.palette.blueRedMix
            case .paletteSaturation: return recipe.palette.saturation
            }
        }
    }

    /// Stable, machine-readable findings returned by `validationIssues`.
    /// Validation reports problems without mutating a user's draft.
    public struct ValidationIssue: Codable, Hashable, Sendable, Identifiable {
        public enum Code: String, CaseIterable, Codable, Hashable, Sendable {
            case emptyID
            case emptyName
            case emptySubtitle
            case unsupportedSchemaVersion
            case nonFiniteControl
            case controlOutsideEditorRange
            case monochromeColorMustBeZero
            case monochromePaletteSaturationMustBeZero
            case provenanceUnavailable
        }

        public let code: Code
        public let control: Control?

        public init(code: Code, control: Control? = nil) {
            self.code = code
            self.control = control
        }

        public var id: String {
            [code.rawValue, control?.rawValue].compactMap { $0 }.joined(separator: ".")
        }

        public var message: String {
            switch code {
            case .emptyID: return "Recipe id must not be empty."
            case .emptyName: return "Recipe name must not be empty."
            case .emptySubtitle: return "Recipe subtitle must not be empty."
            case .unsupportedSchemaVersion: return "Recipe schema version is not supported."
            case .nonFiniteControl:
                let controlName = control?.displayName ?? "Recipe"
                return controlName + " contains a non-finite value."
            case .controlOutsideEditorRange:
                let controlName = control?.displayName ?? "Recipe control"
                return controlName + " is outside the declared editor range."
            case .monochromeColorMustBeZero:
                return "Monochrome film bases must have zero Color."
            case .monochromePaletteSaturationMustBeZero:
                return "Monochrome film bases must have zero palette saturation."
            case .provenanceUnavailable:
                return "Recipe provenance is incomplete and cannot support a current audit claim."
            }
        }
    }

    public struct Palette: Codable, Hashable, Sendable {
        public var redBias: Double
        public var greenBias: Double
        public var blueBias: Double
        public var redGreenMix: Double
        public var greenBlueMix: Double
        public var blueRedMix: Double
        public var saturation: Double

        public init(
            redBias: Double = 0,
            greenBias: Double = 0,
            blueBias: Double = 0,
            redGreenMix: Double = 0,
            greenBlueMix: Double = 0,
            blueRedMix: Double = 0,
            saturation: Double = 1
        ) {
            self.redBias = redBias
            self.greenBias = greenBias
            self.blueBias = blueBias
            self.redGreenMix = redGreenMix
            self.greenBlueMix = greenBlueMix
            self.blueRedMix = blueRedMix
            self.saturation = saturation
        }
    }

    public struct Tone: Codable, Hashable, Sendable {
        public var highlight: Double
        public var shadow: Double

        public init(highlight: Double = 0, shadow: Double = 0) {
            self.highlight = highlight
            self.shadow = shadow
        }
    }

    /// Fujifilm's monochromatic color axes are represented as normalized
    /// warm/cool and green/magenta shifts. They affect ACROS, MONOCHROME, and
    /// SEPIA-style bases; keeping them in the recipe makes the control contract
    /// explicit rather than silently dropping the setting from an edited look.
    public struct MonochromaticColor: Codable, Hashable, Sendable {
        public var warmCool: Double
        public var greenMagenta: Double

        public init(warmCool: Double = 0, greenMagenta: Double = 0) {
            self.warmCool = warmCool
            self.greenMagenta = greenMagenta
        }
    }

    public struct WhiteBalanceShift: Codable, Hashable, Sendable {
        public var mode: WhiteBalanceMode
        /// Color temperature in Kelvin. The renderer clamps this to the public
        /// camera range of 2500...10000 at its boundary.
        public var kelvin: Double
        /// A normalized temperature shift. Positive values warm the image.
        public var temperature: Double
        /// A normalized tint shift. Positive values move toward magenta.
        public var tint: Double

        public init(
            temperature: Double = 0,
            tint: Double = 0,
            mode: WhiteBalanceMode = .auto,
            kelvin: Double = 6500
        ) {
            self.mode = mode
            self.kelvin = kelvin
            self.temperature = temperature
            self.tint = tint
        }

        private enum CodingKeys: String, CodingKey {
            case mode
            case kelvin
            case temperature
            case tint
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decodeIfPresent(WhiteBalanceMode.self, forKey: .mode) ?? .auto
            // Pre-v5 records did not persist a Kelvin value. 6500 K is the
            // neutral bridge used by the previous normalized-only model.
            kelvin = try container.decodeIfPresent(Double.self, forKey: .kelvin) ?? 6500
            temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
            tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        }
    }

    public let schemaVersion: Int
    public private(set) var provenance: Provenance
    public let id: String
    public let name: String
    public let subtitle: String
    public let filmBase: FilmBase
    public var exposure: Double
    public var tone: Tone
    public var saturation: Double
    public var contrast: Double
    public var dynamicRange: DynamicRange
    public var dRangePriority: DRangePriority
    public var whiteBalance: WhiteBalanceShift
    public var monochromaticColor: MonochromaticColor
    public var colorChrome: Double
    public var colorChromeLevel: ColorChromeLevel {
        get { ColorChromeLevel(scalarValue: colorChrome) }
        set { colorChrome = newValue.scalarValue }
    }
    public var blueResponse: Double
    public var fxBlue: Double
    public var fxBlueLevel: FXBlueLevel {
        get { FXBlueLevel(scalarValue: fxBlue) }
        set { fxBlue = newValue.scalarValue }
    }
    public var sharpness: Double
    public var noiseReduction: Double
    public var clarity: Double
    public var grain: Double
    public var grainEffectLevel: GrainEffectLevel {
        get { GrainEffectLevel(scalarValue: grain) }
        set { grain = newValue.scalarValue }
    }
    public var grainSize: Double
    public var grainSizeLevel: GrainSizeLevel {
        get { GrainSizeLevel(scalarValue: grainSize) }
        set { grainSize = newValue.scalarValue }
    }
    public var vignette: Double
    public var halation: Double
    public var palette: Palette

    public init(
        id: String,
        name: String,
        subtitle: String,
        filmBase: FilmBase = .standard,
        exposure: Double = 0,
        tone: Tone = Tone(),
        saturation: Double = 1,
        contrast: Double = 1,
        dynamicRange: DynamicRange = .dr100,
        dRangePriority: DRangePriority = .off,
        whiteBalance: WhiteBalanceShift = WhiteBalanceShift(),
        monochromaticColor: MonochromaticColor = MonochromaticColor(),
        colorChrome: Double = 0,
        blueResponse: Double = 0,
        fxBlue: Double = 0,
        sharpness: Double = 0,
        noiseReduction: Double = 0,
        clarity: Double = 0,
        grain: Double = 0,
        grainSize: Double = 1,
        vignette: Double = 0,
        halation: Double = 0,
        palette: Palette = Palette(),
        provenance: Provenance = Self.currentProvenance
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.provenance = provenance
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.filmBase = filmBase
        self.exposure = exposure
        self.tone = tone
        self.saturation = saturation
        self.contrast = contrast
        self.dynamicRange = dynamicRange
        self.dRangePriority = dRangePriority
        self.whiteBalance = whiteBalance
        self.monochromaticColor = monochromaticColor
        self.colorChrome = colorChrome
        self.blueResponse = blueResponse
        self.fxBlue = fxBlue
        self.sharpness = sharpness
        self.noiseReduction = noiseReduction
        self.clarity = clarity
        self.grain = grain
        self.grainSize = grainSize
        self.vignette = vignette
        self.halation = halation
        self.palette = palette
    }

    /// Records that a user changed one of the public recipe controls. The
    /// source references remain useful for the parent look, but the edited
    /// record is no longer presented as an untouched built-in recipe.
    public mutating func markUserModified(parentRecipeID: String) {
        let parentProvenance = provenance
        provenance = Provenance(
            source: .userModified,
            implementation: .originalParametricApproximation,
            calibration: parentProvenance.calibration,
            references: parentProvenance.references,
            parentRecipeID: parentRecipeID,
            rendererVersion: Self.rendererVersion
        )
    }

    /// Copies only editable renderer controls from a persisted recipe onto a
    /// current built-in parent. Identity, descriptive text, schema, and
    /// provenance stay owned by the current parent and migration layer. Every
    /// numeric value is sanitized at this persistence boundary so a damaged or
    /// legacy UserDefaults record cannot publish NaN or out-of-range controls
    /// into SwiftUI sliders.
    mutating func applyControlValues(from source: FilmRecipe) {
        exposure = Self.sanitized(source.exposure, for: .exposure, fallback: exposure)
        tone = Tone(
            highlight: Self.sanitized(source.tone.highlight, for: .highlights, fallback: tone.highlight),
            shadow: Self.sanitized(source.tone.shadow, for: .shadows, fallback: tone.shadow)
        )
        saturation = Self.sanitized(source.saturation, for: .color, fallback: saturation)
        contrast = Self.sanitized(source.contrast, for: .contrast, fallback: contrast)
        dynamicRange = source.dynamicRange
        dRangePriority = source.dRangePriority
        whiteBalance = WhiteBalanceShift(
            temperature: Self.sanitized(source.whiteBalance.temperature, for: .temperature, fallback: whiteBalance.temperature),
            tint: Self.sanitized(source.whiteBalance.tint, for: .tint, fallback: whiteBalance.tint),
            mode: source.whiteBalance.mode,
            kelvin: Self.sanitized(source.whiteBalance.kelvin, for: .colorTemperature, fallback: whiteBalance.kelvin)
        )
        monochromaticColor = MonochromaticColor(
            warmCool: Self.sanitized(source.monochromaticColor.warmCool, for: .monochromaticWarmCool, fallback: monochromaticColor.warmCool),
            greenMagenta: Self.sanitized(source.monochromaticColor.greenMagenta, for: .monochromaticGreenMagenta, fallback: monochromaticColor.greenMagenta)
        )
        colorChrome = Self.sanitized(source.colorChrome, for: .colorChrome, fallback: colorChrome)
        blueResponse = Self.sanitized(source.blueResponse, for: .blueResponse, fallback: blueResponse)
        fxBlue = Self.sanitized(source.fxBlue, for: .fxBlue, fallback: fxBlue)
        sharpness = Self.sanitized(source.sharpness, for: .sharpness, fallback: sharpness)
        noiseReduction = Self.sanitized(source.noiseReduction, for: .noiseReduction, fallback: noiseReduction)
        clarity = Self.sanitized(source.clarity, for: .clarity, fallback: clarity)
        grain = Self.sanitized(source.grain, for: .grain, fallback: grain)
        grainSize = Self.sanitized(source.grainSize, for: .grainSize, fallback: grainSize)
        vignette = Self.sanitized(source.vignette, for: .vignette, fallback: vignette)
        halation = Self.sanitized(source.halation, for: .halation, fallback: halation)
        palette = Palette(
            redBias: Self.sanitized(source.palette.redBias, for: .paletteRedBias, fallback: palette.redBias),
            greenBias: Self.sanitized(source.palette.greenBias, for: .paletteGreenBias, fallback: palette.greenBias),
            blueBias: Self.sanitized(source.palette.blueBias, for: .paletteBlueBias, fallback: palette.blueBias),
            redGreenMix: Self.sanitized(source.palette.redGreenMix, for: .paletteRedGreenMix, fallback: palette.redGreenMix),
            greenBlueMix: Self.sanitized(source.palette.greenBlueMix, for: .paletteGreenBlueMix, fallback: palette.greenBlueMix),
            blueRedMix: Self.sanitized(source.palette.blueRedMix, for: .paletteBlueRedMix, fallback: palette.blueRedMix),
            saturation: Self.sanitized(source.palette.saturation, for: .paletteSaturation, fallback: palette.saturation)
        )

        if filmBase.monochromeFilter != nil {
            saturation = 0
            palette.saturation = 0
        }
    }

    private static func sanitized(
        _ value: Double,
        for control: Control,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, control.editorRange.lowerBound), control.editorRange.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case provenance
        case id
        case name
        case subtitle
        case filmBase
        case exposure
        case tone
        case saturation
        case contrast
        case dynamicRange
        case dRangePriority
        case whiteBalance
        case monochromaticColor
        case colorChrome
        case blueResponse
        case fxBlue
        case sharpness
        case noiseReduction
        case clarity
        case grain
        case grainSize
        case vignette
        case halation
        case palette
    }

    /// Decode both the current envelope and the original pre-provenance
    /// envelope. Missing metadata is deliberately marked as legacy rather
    /// than silently receiving the current provenance claim.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        provenance = try container.decodeIfPresent(Provenance.self, forKey: .provenance)
            ?? Self.legacyProvenance
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        filmBase = try container.decode(FilmBase.self, forKey: .filmBase)
        exposure = try container.decode(Double.self, forKey: .exposure)
        tone = try container.decode(Tone.self, forKey: .tone)
        saturation = try container.decode(Double.self, forKey: .saturation)
        contrast = try container.decode(Double.self, forKey: .contrast)
        dynamicRange = try container.decode(DynamicRange.self, forKey: .dynamicRange)
        dRangePriority = try container.decodeIfPresent(DRangePriority.self, forKey: .dRangePriority) ?? .off
        whiteBalance = try container.decode(WhiteBalanceShift.self, forKey: .whiteBalance)
        monochromaticColor = try container.decodeIfPresent(MonochromaticColor.self, forKey: .monochromaticColor) ?? MonochromaticColor()
        colorChrome = try container.decode(Double.self, forKey: .colorChrome)
        blueResponse = try container.decode(Double.self, forKey: .blueResponse)
        fxBlue = try container.decode(Double.self, forKey: .fxBlue)
        sharpness = try container.decode(Double.self, forKey: .sharpness)
        noiseReduction = try container.decode(Double.self, forKey: .noiseReduction)
        clarity = try container.decode(Double.self, forKey: .clarity)
        grain = try container.decode(Double.self, forKey: .grain)
        grainSize = try container.decode(Double.self, forKey: .grainSize)
        vignette = try container.decode(Double.self, forKey: .vignette)
        halation = try container.decode(Double.self, forKey: .halation)
        palette = try container.decode(Palette.self, forKey: .palette)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(filmBase, forKey: .filmBase)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(tone, forKey: .tone)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(dynamicRange, forKey: .dynamicRange)
        try container.encode(dRangePriority, forKey: .dRangePriority)
        try container.encode(whiteBalance, forKey: .whiteBalance)
        try container.encode(monochromaticColor, forKey: .monochromaticColor)
        try container.encode(colorChrome, forKey: .colorChrome)
        try container.encode(blueResponse, forKey: .blueResponse)
        try container.encode(fxBlue, forKey: .fxBlue)
        try container.encode(sharpness, forKey: .sharpness)
        try container.encode(noiseReduction, forKey: .noiseReduction)
        try container.encode(clarity, forKey: .clarity)
        try container.encode(grain, forKey: .grain)
        try container.encode(grainSize, forKey: .grainSize)
        try container.encode(vignette, forKey: .vignette)
        try container.encode(halation, forKey: .halation)
        try container.encode(palette, forKey: .palette)
    }

    /// Returns deterministic, non-mutating findings for the persisted recipe
    /// contract. The renderer remains defensive for exploratory drafts that
    /// intentionally exceed these editor bounds.
    public var validationIssues: [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(code: .emptyID))
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(code: .emptyName))
        }
        if subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(code: .emptySubtitle))
        }
        if !(1...Self.currentSchemaVersion).contains(schemaVersion) {
            issues.append(ValidationIssue(code: .unsupportedSchemaVersion))
        }

        for control in Control.allCases {
            let value = control.value(in: self)
            if !value.isFinite {
                issues.append(ValidationIssue(code: .nonFiniteControl, control: control))
            } else if !control.editorRange.contains(value) {
                issues.append(ValidationIssue(code: .controlOutsideEditorRange, control: control))
            }
        }

        if filmBase.monochromeFilter != nil && abs(saturation) > 0.000001 {
            issues.append(ValidationIssue(code: .monochromeColorMustBeZero))
        }
        if filmBase.monochromeFilter != nil && abs(palette.saturation) > 0.000001 {
            issues.append(ValidationIssue(code: .monochromePaletteSaturationMustBeZero))
        }
        if schemaVersion != Self.currentSchemaVersion || !provenance.isComplete {
            issues.append(ValidationIssue(code: .provenanceUnavailable))
        }

        return issues
    }

    /// A recipe is valid only when its controls satisfy the app contract and
    /// its provenance is complete. This does not claim hardware equivalence.
    public var isValid: Bool { validationIssues.isEmpty }

    // These aliases keep the model convenient for controls that use the same
    // terms as the camera UI.
    public var highlightTone: Double { tone.highlight }
    public var shadowTone: Double { tone.shadow }
    public var temperatureShift: Double { whiteBalance.temperature }
    public var tintShift: Double { whiteBalance.tint }
    public var grainAmount: Double { grain }
    public var vignetteAmount: Double { vignette }

    /// Colors used by the recipe rail and other lightweight UI previews.
    /// The renderer never uses these swatches as image data; they are UI hints.
    public static let previewColors: [Color] = [
        Color(red: 0.44, green: 0.34, blue: 0.25),
        Color(red: 0.58, green: 0.28, blue: 0.18),
        Color(red: 0.32, green: 0.43, blue: 0.39),
        Color(red: 0.25, green: 0.35, blue: 0.43),
        Color(red: 0.56, green: 0.44, blue: 0.28),
        Color(red: 0.68, green: 0.68, blue: 0.62)
    ]

    /// The initial recipe library. Names refer to public film-camera
    /// conventions; the app is not affiliated with or calibrated by Fujifilm.
    public static let builtIns: [FilmRecipe] = [
        FilmRecipe(
            id: "provia-standard",
            name: "Natural Standard",
            subtitle: "Natural color / clean daylight",
            filmBase: .provia,
            tone: Tone(highlight: 0.02, shadow: 0.00),
            saturation: 1.00,
            contrast: 1.00,
            dynamicRange: .dr100,
            whiteBalance: WhiteBalanceShift(),
            colorChrome: 0.5,
            blueResponse: 0.02,
            fxBlue: 0.00,
            sharpness: 0.02,
            noiseReduction: 0.01,
            clarity: 0.02,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.04,
            halation: 0.01,
            palette: Palette(
                redBias: 0.006,
                greenBias: 0.004,
                blueBias: 0.004,
                redGreenMix: 0.004,
                greenBlueMix: 0.002,
                blueRedMix: 0.004,
                saturation: 1.00
            )
        ),
        FilmRecipe(
            id: "classic-chrome",
            name: "Muted Color",
            subtitle: "Muted color / hard light",
            filmBase: .classicChrome,
            tone: Tone(highlight: -0.18, shadow: 0.10),
            saturation: 0.88,
            contrast: 1.06,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.02, tint: -0.01),
            colorChrome: 0.5,
            blueResponse: 0.18,
            fxBlue: 0.5,
            sharpness: 0.04,
            noiseReduction: 0.01,
            clarity: 0.10,
            grain: 0.5,
            grainSize: 1.5,
            vignette: 0.12,
            halation: 0.04,
            palette: Palette(
                redBias: 0.012,
                greenBias: 0.004,
                blueBias: -0.012,
                redGreenMix: 0.018,
                greenBlueMix: -0.010,
                blueRedMix: -0.014,
                saturation: 0.96
            )
        ),
        FilmRecipe(
            id: "velvia-vivid",
            name: "Vivid Slide",
            subtitle: "Deep color / rich contrast",
            filmBase: .velvia,
            tone: Tone(highlight: -0.08, shadow: -0.14),
            saturation: 1.22,
            contrast: 1.12,
            dynamicRange: .dr100,
            whiteBalance: WhiteBalanceShift(temperature: 0.04, tint: -0.02),
            colorChrome: 1.0,
            blueResponse: 0.34,
            fxBlue: 0.5,
            sharpness: 0.16,
            noiseReduction: 0.01,
            clarity: 0.18,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.10,
            halation: 0.02,
            palette: Palette(
                redBias: 0.016,
                greenBias: 0.010,
                blueBias: 0.022,
                redGreenMix: 0.028,
                greenBlueMix: -0.020,
                blueRedMix: 0.014,
                saturation: 1.06
            )
        ),
        FilmRecipe(
            id: "astia-soft",
            name: "Soft Portrait",
            subtitle: "Portrait color / gentle rolloff",
            filmBase: .astia,
            tone: Tone(highlight: 0.10, shadow: 0.08),
            saturation: 1.02,
            contrast: 0.96,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.03, tint: 0.02),
            colorChrome: 0.5,
            blueResponse: 0.04,
            fxBlue: 0.5,
            sharpness: -0.02,
            noiseReduction: 0.03,
            clarity: 0.02,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.08,
            halation: 0.03,
            palette: Palette(
                redBias: 0.018,
                greenBias: 0.006,
                blueBias: -0.004,
                redGreenMix: 0.010,
                greenBlueMix: 0.002,
                blueRedMix: -0.004,
                saturation: 0.99
            )
        ),
        FilmRecipe(
            id: "pro-neg-high",
            name: "Defined Negative",
            subtitle: "Neutral color / defined edges",
            filmBase: .proNegative,
            tone: Tone(highlight: -0.06, shadow: -0.02),
            saturation: 0.96,
            contrast: 1.08,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.01, tint: 0.01),
            colorChrome: 0.5,
            blueResponse: 0.02,
            fxBlue: 0.5,
            sharpness: 0.12,
            noiseReduction: 0.03,
            clarity: 0.16,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.06,
            halation: 0.01,
            palette: Palette(
                redBias: 0.010,
                greenBias: 0.004,
                blueBias: 0.000,
                redGreenMix: 0.006,
                greenBlueMix: -0.004,
                blueRedMix: -0.004,
                saturation: 0.98
            )
        ),
        FilmRecipe(
            id: "eterna-cinema",
            name: "Cinema Soft",
            subtitle: "Low saturation / soft shadows",
            filmBase: .eterna,
            tone: Tone(highlight: 0.16, shadow: 0.18),
            saturation: 0.78,
            contrast: 0.91,
            dynamicRange: .dr400,
            whiteBalance: WhiteBalanceShift(temperature: -0.02, tint: -0.01),
            colorChrome: 0.5,
            blueResponse: -0.06,
            fxBlue: 0.0,
            sharpness: -0.04,
            noiseReduction: 0.05,
            clarity: -0.04,
            grain: 0.5,
            grainSize: 1.5,
            vignette: 0.16,
            halation: 0.10,
            palette: Palette(
                redBias: 0.004,
                greenBias: 0.010,
                blueBias: 0.016,
                redGreenMix: -0.006,
                greenBlueMix: 0.010,
                blueRedMix: 0.002,
                saturation: 0.96
            )
        ),
        FilmRecipe(
            id: "acros-monochrome",
            name: "Fine Monochrome",
            subtitle: "Fine grain / tonal depth",
            filmBase: .monochrome,
            tone: Tone(highlight: -0.04, shadow: -0.12),
            saturation: 0,
            contrast: 1.08,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(),
            colorChrome: 0,
            blueResponse: 0,
            fxBlue: 0,
            sharpness: 0.10,
            noiseReduction: 0.02,
            clarity: 0.12,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.14,
            halation: 0.02,
            palette: Palette(
                redBias: 0,
                greenBias: 0,
                blueBias: 0,
                redGreenMix: 0,
                greenBlueMix: 0,
                blueRedMix: 0,
                saturation: 0
            )
        ),
        FilmRecipe(
            id: "sepia-archive",
            name: "Sepia Archive",
            subtitle: "Warm monochrome / paper tone",
            filmBase: .sepia,
            tone: Tone(highlight: 0.02, shadow: -0.06),
            saturation: 0,
            contrast: 1.04,
            dynamicRange: .dr200,
            sharpness: 0.06,
            noiseReduction: 0.02,
            clarity: 0.04,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.12,
            halation: 0.02,
            palette: Palette(
                redBias: 0.02,
                greenBias: 0.004,
                blueBias: -0.02,
                redGreenMix: 0.004,
                greenBlueMix: 0,
                blueRedMix: 0,
                saturation: 0
            )
        ),
        FilmRecipe(
            id: "acros-neutral-filter",
            name: "Neutral Monochrome",
            subtitle: "Neutral filter / tonal depth",
            filmBase: .acros,
            tone: Tone(highlight: -0.03, shadow: -0.10),
            saturation: 0,
            contrast: 1.06,
            dynamicRange: .dr200,
            sharpness: 0.10,
            noiseReduction: 0.02,
            clarity: 0.11,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.14,
            halation: 0.01,
            palette: Palette(saturation: 0)
        ),
        FilmRecipe(
            id: "acros-yellow-filter",
            name: "Yellow Monochrome",
            subtitle: "Yellow filter / open skies",
            filmBase: .acrosYellow,
            tone: Tone(highlight: -0.02, shadow: -0.08),
            saturation: 0,
            contrast: 1.05,
            dynamicRange: .dr200,
            sharpness: 0.10,
            noiseReduction: 0.02,
            clarity: 0.10,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.14,
            halation: 0.01,
            palette: Palette(saturation: 0)
        ),
        FilmRecipe(
            id: "acros-red-filter",
            name: "Red Monochrome",
            subtitle: "Red filter / graphic contrast",
            filmBase: .acrosRed,
            tone: Tone(highlight: -0.08, shadow: -0.16),
            saturation: 0,
            contrast: 1.10,
            dynamicRange: .dr200,
            sharpness: 0.12,
            noiseReduction: 0.02,
            clarity: 0.14,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.16,
            halation: 0.01,
            palette: Palette(saturation: 0)
        ),
        FilmRecipe(
            id: "acros-green-filter",
            name: "Green Monochrome",
            subtitle: "Green filter / gentle skin tones",
            filmBase: .acrosGreen,
            tone: Tone(highlight: 0.02, shadow: -0.04),
            saturation: 0,
            contrast: 1.03,
            dynamicRange: .dr200,
            sharpness: 0.08,
            noiseReduction: 0.02,
            clarity: 0.08,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.13,
            halation: 0.01,
            palette: Palette(saturation: 0)
        ),
        FilmRecipe(
            id: "classic-negative",
            name: "Warm Negative",
            subtitle: "Cyan shadows / warm highlights",
            filmBase: .classicNegative,
            tone: Tone(highlight: -0.06, shadow: 0.18),
            saturation: 0.96,
            contrast: 1.04,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.03, tint: 0.01),
            colorChrome: 0.5,
            blueResponse: 0.24,
            fxBlue: 0.5,
            sharpness: 0.02,
            noiseReduction: 0.02,
            clarity: 0.06,
            grain: 0.5,
            grainSize: 1.5,
            vignette: 0.14,
            halation: 0.06,
            palette: Palette(
                redBias: 0.018,
                greenBias: 0.002,
                blueBias: 0.012,
                redGreenMix: -0.012,
                greenBlueMix: 0.006,
                blueRedMix: 0.022,
                saturation: 0.98
            )
        ),
        FilmRecipe(
            id: "nostalgic-negative",
            name: "Memory Negative",
            subtitle: "Amber light / cool shadows",
            filmBase: .nostalgicNegative,
            tone: Tone(highlight: -0.08, shadow: 0.16),
            saturation: 1.02,
            contrast: 1.02,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.08, tint: 0.01),
            colorChrome: 0.5,
            blueResponse: 0.30,
            fxBlue: 0.5,
            sharpness: 0.01,
            noiseReduction: 0.02,
            clarity: 0.03,
            grain: 0.5,
            grainSize: 1.5,
            vignette: 0.18,
            halation: 0.12,
            palette: Palette(
                redBias: 0.024,
                greenBias: -0.004,
                blueBias: 0.020,
                redGreenMix: 0.012,
                greenBlueMix: 0.010,
                blueRedMix: -0.018,
                saturation: 1.00
            )
        ),
        FilmRecipe(
            id: "eterna-bleach-bypass",
            name: "Silver Cinema",
            subtitle: "Desaturated / high contrast cinema",
            filmBase: .eternaBleachBypass,
            tone: Tone(highlight: -0.12, shadow: -0.16),
            saturation: 0.54,
            contrast: 1.18,
            dynamicRange: .dr400,
            whiteBalance: WhiteBalanceShift(temperature: -0.02, tint: -0.02),
            colorChrome: 0.5,
            blueResponse: 0.08,
            fxBlue: 0.5,
            sharpness: 0.16,
            noiseReduction: 0.02,
            clarity: 0.14,
            grain: 0.5,
            grainSize: 1.5,
            vignette: 0.18,
            halation: 0.04,
            palette: Palette(
                redBias: 0.004,
                greenBias: 0.008,
                blueBias: 0.014,
                redGreenMix: 0.002,
                greenBlueMix: 0.008,
                blueRedMix: 0.004,
                saturation: 0.94
            )
        ),
        FilmRecipe(
            id: "pro-neg-standard",
            name: "Neutral Portrait",
            subtitle: "Soft portrait / natural gradation",
            filmBase: .proNegStandard,
            tone: Tone(highlight: 0.08, shadow: 0.10),
            saturation: 0.92,
            contrast: 0.94,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.02, tint: 0.02),
            colorChrome: 0.5,
            blueResponse: 0.02,
            fxBlue: 0.5,
            sharpness: -0.02,
            noiseReduction: 0.04,
            clarity: -0.04,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.08,
            halation: 0.03,
            palette: Palette(
                redBias: 0.016,
                greenBias: 0.004,
                blueBias: -0.002,
                redGreenMix: 0.006,
                greenBlueMix: 0.002,
                blueRedMix: -0.002,
                saturation: 0.98
            )
        ),
        FilmRecipe(
            id: "reala-ace",
            name: "Natural Negative",
            subtitle: "Natural color / gentle cyan",
            filmBase: .realaAce,
            tone: Tone(highlight: 0.02, shadow: 0.03),
            saturation: 0.96,
            contrast: 1.00,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.01, tint: 0.01),
            colorChrome: 0.5,
            blueResponse: 0.14,
            fxBlue: 0.5,
            sharpness: 0.02,
            noiseReduction: 0.02,
            clarity: 0.02,
            grain: 0.5,
            grainSize: 0.75,
            vignette: 0.06,
            halation: 0.02,
            palette: Palette(
                redBias: 0.012,
                greenBias: 0.004,
                blueBias: 0.008,
                redGreenMix: 0.006,
                greenBlueMix: 0.004,
                blueRedMix: 0.006,
                saturation: 0.99
            )
        ),
        FilmRecipe(
            id: "g7x-compact",
            name: "G7 X Compact",
            subtitle: "Warm skin / crisp compact color",
            filmBase: .compactDigital,
            exposure: 0.05,
            tone: Tone(highlight: 0.08, shadow: 0.10),
            saturation: 1.06,
            contrast: 1.08,
            dynamicRange: .dr200,
            dRangePriority: .off,
            whiteBalance: WhiteBalanceShift(
                temperature: 0.04,
                tint: 0.01,
                mode: .ambiencePriority
            ),
            colorChrome: 0,
            blueResponse: 0.08,
            fxBlue: 0,
            sharpness: 0.18,
            noiseReduction: 0.08,
            clarity: 0.10,
            grain: 0,
            grainSize: 0.75,
            vignette: 0.05,
            halation: 0,
            palette: Palette(
                redBias: 0.015,
                greenBias: 0.002,
                blueBias: -0.006,
                redGreenMix: 0.012,
                greenBlueMix: 0.004,
                blueRedMix: -0.008,
                saturation: 1.01
            ),
            provenance: g7XProvenance
        )
    ]
}
