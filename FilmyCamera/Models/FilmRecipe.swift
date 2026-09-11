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
    public static let rendererVersion = "core-image-parametric-v16"

    /// The Kelvin value that renders as "as shot". Phone frames are already
    /// balanced for their scene, so a Color Temperature setting equal to this
    /// daylight reference leaves color unchanged; higher renders warmer.
    public static let asShotKelvin: Double = 5600

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
            // Compensate the illuminant's cast: tungsten needs cooling,
            // while underwater light needs warmth to reduce its blue cast.
            case .incandescent: return -0.18
            case .underwater: return 0.08
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
        case fujifilmRecipeGuide
        case fujifilmCreatorRecipes
        case fujiXWeeklyRecipeLibrary
        case g7XMarkIIITechnicalSpecifications
        case g7XMarkIIICameraMuseum

        public var title: String {
            switch self {
            case .xt5ImageQualitySetting:
                return "FUJIFILM X-T5 Image Quality Setting"
            case .filmSimulationOverview:
                return "FUJIFILM Film Simulation overview"
            case .fujifilmRecipeGuide:
                return "FUJIFILM Film Simulation recipe guide"
            case .fujifilmCreatorRecipes:
                return "FUJIFILM creator FS RECIPE stories"
            case .fujiXWeeklyRecipeLibrary:
                return "Fuji X Weekly public recipe library"
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
            case .fujifilmRecipeGuide:
                return "https://shopusa.fujifilm-x.com/discover/how-to-make-a-film-simulation-recipe/"
            case .fujifilmCreatorRecipes:
                return "https://www.fujifilm-x.com/en-us/stories/"
            case .fujiXWeeklyRecipeLibrary:
                return "https://fujixweekly.com/recipes/"
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
            case .fujifilmRecipeGuide:
                return "Public recipe control semantics and an official example recipe"
            case .fujifilmCreatorRecipes:
                return "Public creator recipe settings published by Fujifilm"
            case .fujiXWeeklyRecipeLibrary:
                return "Public community recipe settings used as adaptation references"
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

    public static let fujifilmCreatorRecipeReferences: [PublicReference] =
        fujifilmPublicReferences + [.fujifilmRecipeGuide, .fujifilmCreatorRecipes]

    public static let communityRecipeReferences: [PublicReference] =
        fujifilmPublicReferences + [.fujiXWeeklyRecipeLibrary]

    /// Machine-readable provenance attached to a recipe and persisted with
    /// saved-frame metadata. The enum surface contains no exact-match or
    /// hardware-calibrated state by design.
    public struct Provenance: Codable, Hashable, Sendable {
        public enum Source: String, CaseIterable, Codable, Hashable, Sendable {
            case publicOfficialDocumentation
            case publicOfficialRecipe
            case publicCommunityRecipe
            case publicCanonDocumentation
            case originalCreativeDesign
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
            case notCalibratedToCameraHardware
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
                if calibration == .notCalibratedToCameraHardware { return FilmRecipe.creativeApproximationDisclaimer }
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
            case (.originalCreativeDesign, .notCalibratedToCameraHardware),
                 (.userModified, .notCalibratedToCameraHardware):
                hasMatchingSourceAndReferences = references.isEmpty
            case (.publicOfficialDocumentation, .notCalibratedToFujifilmHardware),
                 (.userModified, .notCalibratedToFujifilmHardware)
                where references == FilmRecipe.fujifilmPublicReferences:
                hasMatchingSourceAndReferences = references == FilmRecipe.fujifilmPublicReferences
            case (.publicOfficialRecipe, .notCalibratedToFujifilmHardware):
                hasMatchingSourceAndReferences = references == FilmRecipe.fujifilmCreatorRecipeReferences
            case (.publicCommunityRecipe, .notCalibratedToFujifilmHardware):
                hasMatchingSourceAndReferences = references == FilmRecipe.communityRecipeReferences
            case (.userModified, .notCalibratedToFujifilmHardware):
                hasMatchingSourceAndReferences = [
                    FilmRecipe.fujifilmCreatorRecipeReferences,
                    FilmRecipe.communityRecipeReferences
                ].contains(references)
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

    public static let fujifilmCreatorRecipeProvenance = Provenance(
        source: .publicOfficialRecipe,
        implementation: .originalParametricApproximation,
        calibration: .notCalibratedToFujifilmHardware,
        references: fujifilmCreatorRecipeReferences
    )

    public static let communityRecipeProvenance = Provenance(
        source: .publicCommunityRecipe,
        implementation: .originalParametricApproximation,
        calibration: .notCalibratedToFujifilmHardware,
        references: communityRecipeReferences
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
            kelvin: Double = FilmRecipe.asShotKelvin
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
            kelvin = try container.decodeIfPresent(Double.self, forKey: .kelvin) ?? FilmRecipe.asShotKelvin
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

    /// Expanded looks adapted from public Fujifilm creator recipes and
    /// established community recipes. IDs are stable so saved selections and
    /// user overrides survive display-name changes.
    public static let expandedInternetRecipeIDs: [String] = [
        "nostalgic-summer",
        "aurea-golden",
        "eternal-pastel",
        "crepuscolo-blue",
        "black-ice",
        "matter-monochrome",
        "honey-portrait",
        "pacifica-100",
        "desert-daydream",
        "quiet-provia",
        "velvet-haze",
        "pastel-400",
        "archive-64",
        "tungsten-800",
        "pushed-tungsten",
        "pacific-blues",
        "green-800",
        "hp5-texture"
    ]

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    /// Converts public camera-menu values into the renderer's normalized
    /// controls. This mapping is deliberately simple and inspectable; it does
    /// not claim that the Core Image pipeline matches Fujifilm hardware.
    private static func researchedRecipe(
        id: String,
        name: String,
        subtitle: String,
        filmBase: FilmBase,
        exposure: Double = 0,
        highlight: Double,
        shadow: Double,
        color: Double,
        dynamicRange: DynamicRange,
        dRangePriority: DRangePriority = .off,
        whiteBalanceMode: WhiteBalanceMode,
        kelvin: Double = FilmRecipe.asShotKelvin,
        redShift: Double = 0,
        blueShift: Double = 0,
        colorChrome: ColorChromeLevel,
        fxBlue: FXBlueLevel,
        sharpness: Double,
        noiseReduction: Double,
        clarity: Double,
        grain: GrainEffectLevel,
        grainSize: GrainSizeLevel,
        monochromaticColor: MonochromaticColor = MonochromaticColor(),
        vignette: Double = 0.08,
        halation: Double = 0.02,
        provenance: Provenance
    ) -> FilmRecipe {
        let monochrome = filmBase.monochromeFilter != nil || filmBase == .monochrome
        let temperature = clamp((redShift - blueShift) * 0.018, lower: -1, upper: 1)
        let tint = clamp((redShift + blueShift) * 0.008, lower: -1, upper: 1)

        let baseBlueResponse: Double
        switch filmBase {
        case .classicChrome: baseBlueResponse = 0.14
        case .classicNegative: baseBlueResponse = 0.24
        case .nostalgicNegative: baseBlueResponse = 0.20
        case .eterna, .eternaBleachBypass: baseBlueResponse = 0.08
        default: baseBlueResponse = 0.04
        }

        return FilmRecipe(
            id: id,
            name: name,
            subtitle: subtitle,
            filmBase: filmBase,
            exposure: clamp(exposure, lower: -2, upper: 2),
            tone: Tone(
                highlight: clamp(highlight / 4, lower: -1, upper: 1),
                shadow: clamp(shadow / 4, lower: -1, upper: 1)
            ),
            saturation: monochrome ? 0 : clamp(1 + color * 0.07, lower: 0, upper: 2),
            contrast: 1,
            dynamicRange: dynamicRange,
            dRangePriority: dRangePriority,
            whiteBalance: WhiteBalanceShift(
                temperature: temperature,
                tint: tint,
                mode: whiteBalanceMode,
                kelvin: kelvin
            ),
            monochromaticColor: monochromaticColor,
            colorChrome: colorChrome.scalarValue,
            blueResponse: monochrome ? 0 : baseBlueResponse,
            fxBlue: fxBlue.scalarValue,
            sharpness: clamp(sharpness * 0.04, lower: -1, upper: 1),
            noiseReduction: clamp((noiseReduction + 4) * 0.01, lower: 0, upper: 1),
            clarity: clamp(clarity * 0.04, lower: -1, upper: 1),
            grain: grain.scalarValue,
            grainSize: grainSize.scalarValue,
            vignette: vignette,
            halation: halation,
            palette: Palette(saturation: monochrome ? 0 : 1),
            provenance: provenance
        )
    }

    /// The initial recipe library. Names refer to public film-camera
    /// conventions; the app is not affiliated with or calibrated by Fujifilm.
    public static let builtIns: [FilmRecipe] = legacyBuiltIns + originalCreativeLooks

    /// The original 36 entries retain their identity, order, and exact controls.
    static let legacyBuiltIns: [FilmRecipe] = [
        FilmRecipe(
            id: "provia-standard",
            name: "Natural Standard",
            subtitle: "Natural color / clean daylight",
            filmBase: .provia,
            tone: Tone(highlight: 0.02, shadow: 0.02),
            saturation: 1.02,
            contrast: 1.02,
            dynamicRange: .dr100,
            whiteBalance: WhiteBalanceShift(),
            colorChrome: 0.5,
            blueResponse: 0.02,
            fxBlue: 0.00,
            sharpness: 0.02,
            noiseReduction: 0.01,
            clarity: 0.02,
            grain: 0,
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
            tone: Tone(highlight: -0.12, shadow: 0.16),
            saturation: 0.86,
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
            grainSize: 0.75,
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
            tone: Tone(highlight: 0.04, shadow: 0.14),
            saturation: 1.28,
            contrast: 1.16,
            dynamicRange: .dr100,
            whiteBalance: WhiteBalanceShift(temperature: 0.04, tint: -0.02),
            colorChrome: 1.0,
            blueResponse: 0.34,
            fxBlue: 0.5,
            sharpness: 0.16,
            noiseReduction: 0.01,
            clarity: 0.18,
            grain: 0,
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
            tone: Tone(highlight: -0.16, shadow: -0.04),
            saturation: 1.06,
            contrast: 0.94,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.03, tint: 0.02),
            colorChrome: 0.5,
            blueResponse: 0.04,
            fxBlue: 0.5,
            sharpness: -0.02,
            noiseReduction: 0.03,
            clarity: 0.02,
            grain: 0,
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
            tone: Tone(highlight: -0.04, shadow: 0.06),
            saturation: 0.94,
            contrast: 1.1,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.01, tint: 0.01),
            colorChrome: 0.5,
            blueResponse: 0.02,
            fxBlue: 0.5,
            sharpness: 0.12,
            noiseReduction: 0.03,
            clarity: 0.16,
            grain: 0,
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
            tone: Tone(highlight: -0.26, shadow: -0.26),
            saturation: 0.72,
            contrast: 0.86,
            dynamicRange: .dr400,
            whiteBalance: WhiteBalanceShift(temperature: -0.02, tint: -0.01),
            colorChrome: 0.5,
            blueResponse: -0.06,
            fxBlue: 0.0,
            sharpness: -0.04,
            noiseReduction: 0.05,
            clarity: -0.04,
            grain: 0,
            grainSize: 0.75,
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
            tone: Tone(highlight: -0.06, shadow: 0.16),
            saturation: 0,
            contrast: 1.1,
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
            tone: Tone(highlight: -0.04, shadow: 0.26),
            saturation: 0.94,
            contrast: 1.12,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.03, tint: 0.01),
            colorChrome: 0.5,
            blueResponse: 0.24,
            fxBlue: 0.5,
            sharpness: 0.02,
            noiseReduction: 0.02,
            clarity: 0.06,
            grain: 0.5,
            grainSize: 0.75,
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
            tone: Tone(highlight: -0.20, shadow: 0.06),
            saturation: 1.02,
            contrast: 1.0,
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
            tone: Tone(highlight: 0.06, shadow: 0.18),
            saturation: 0.5,
            contrast: 1.22,
            dynamicRange: .dr400,
            whiteBalance: WhiteBalanceShift(temperature: -0.02, tint: -0.02),
            colorChrome: 0.5,
            blueResponse: 0.08,
            fxBlue: 0.5,
            sharpness: 0.16,
            noiseReduction: 0.02,
            clarity: 0.14,
            grain: 0.5,
            grainSize: 0.75,
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
            tone: Tone(highlight: -0.1, shadow: -0.06),
            saturation: 0.9,
            contrast: 0.94,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.02, tint: 0.02),
            colorChrome: 0.5,
            blueResponse: 0.02,
            fxBlue: 0.5,
            sharpness: -0.02,
            noiseReduction: 0.04,
            clarity: -0.04,
            grain: 0,
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
            tone: Tone(highlight: 0.06, shadow: 0.06),
            saturation: 0.98,
            contrast: 1.06,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.01, tint: 0.01),
            colorChrome: 0.5,
            blueResponse: 0.14,
            fxBlue: 0.5,
            sharpness: 0.02,
            noiseReduction: 0.02,
            clarity: 0.02,
            grain: 0,
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
            subtitle: "Rich contrast / warm highlights",
            filmBase: .compactDigital,
            exposure: 0.05,
            // The Signature look combines deeper ambient tones, richer color,
            // and warm highlights. It is an original stylized approximation,
            // not a measured Canon camera response.
            tone: Tone(highlight: 0.12, shadow: 0.16),
            saturation: 1.06,
            contrast: 1.10,
            dynamicRange: .auto,
            dRangePriority: .weak,
            whiteBalance: WhiteBalanceShift(
                // Ambience Priority already contributes a small warm bias.
                // Keep the explicit shift restrained so neutral walls and
                // fabric stay neutral in daylight.
                temperature: 0.006,
                tint: 0.006,
                mode: .ambiencePriority
            ),
            colorChrome: 0,
            blueResponse: 0,
            fxBlue: 0,
            sharpness: 0.05,
            noiseReduction: 0.04,
            clarity: 0,
            grain: 0,
            grainSize: 0.75,
            vignette: 0,
            halation: 0,
            palette: Palette(),
            provenance: g7XProvenance
        ),

        // Public Fujifilm creator-recipe adaptations. Source settings:
        // https://www.fujifilm-x.com/en-gb/learning-centre/make-your-own-film-simulation-recipe/
        // https://www.fujifilm-x.com/en-us/stories/x-e5-x-fs-recipe-davide-gazzotti/
        // https://www.fujifilm-x.com/en-us/stories/acros-fs-recipe-x-allan-steele-dadzie/
        // https://www.fujifilm-x.com/en-us/stories/acros-fs-recipe-x-agathe-poupeney/
        researchedRecipe(
            id: "nostalgic-summer",
            name: "Nostalgic Summer",
            subtitle: "Soft warmth / seaside color",
            filmBase: .nostalgicNegative,
            exposure: 0.45,
            highlight: -1.5,
            shadow: -1,
            color: 3,
            dynamicRange: .dr400,
            whiteBalanceMode: .colorTemperature,
            kelvin: 5600,
            redShift: 0,
            blueShift: -3,
            colorChrome: .weak,
            fxBlue: .weak,
            sharpness: -1,
            noiseReduction: 0,
            clarity: 0,
            grain: .weak,
            grainSize: .large,
            vignette: 0.10,
            halation: 0.06,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "aurea-golden",
            name: "Aurea Golden",
            subtitle: "Golden light / warm portraits",
            filmBase: .nostalgicNegative,
            exposure: 0.33,
            highlight: -1.5,
            shadow: 0,
            color: 2,
            dynamicRange: .dr400,
            whiteBalanceMode: .ambiencePriority,
            redShift: 4,
            blueShift: -5,
            colorChrome: .weak,
            fxBlue: .weak,
            sharpness: -4,
            noiseReduction: -4,
            clarity: 0,
            grain: .weak,
            grainSize: .small,
            vignette: 0.12,
            halation: 0.08,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "eternal-pastel",
            name: "Eternal Pastel",
            subtitle: "Pastel color / suspended summer",
            filmBase: .classicChrome,
            exposure: 0.33,
            highlight: -1,
            shadow: -1.5,
            color: 4,
            dynamicRange: .dr400,
            whiteBalanceMode: .colorTemperature,
            kelvin: 5550,
            redShift: 1,
            blueShift: -4,
            colorChrome: .strong,
            fxBlue: .weak,
            sharpness: -4,
            noiseReduction: -4,
            clarity: 0,
            grain: .strong,
            grainSize: .small,
            vignette: 0.12,
            halation: 0.06,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "crepuscolo-blue",
            name: "Crepuscolo Blue",
            subtitle: "Cool dusk / cinematic quiet",
            filmBase: .nostalgicNegative,
            highlight: -1,
            shadow: -1.5,
            color: 2,
            dynamicRange: .dr400,
            whiteBalanceMode: .ambiencePriority,
            redShift: -4,
            blueShift: 0,
            colorChrome: .strong,
            fxBlue: .weak,
            sharpness: -2,
            noiseReduction: -4,
            clarity: 0,
            grain: .strong,
            grainSize: .small,
            vignette: 0.16,
            halation: 0.05,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "black-ice",
            name: "Black Ice",
            subtitle: "Hard city light / crisp texture",
            filmBase: .acrosYellow,
            highlight: 1.5,
            shadow: 2.5,
            color: 0,
            dynamicRange: .dr200,
            whiteBalanceMode: .auto,
            colorChrome: .off,
            fxBlue: .off,
            sharpness: 2,
            noiseReduction: -2,
            clarity: 0,
            grain: .strong,
            grainSize: .small,
            vignette: 0.16,
            halation: 0.01,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "matter-monochrome",
            name: "Matter Monochrome",
            subtitle: "Worked surfaces / tactile grain",
            filmBase: .acrosYellow,
            highlight: 1,
            shadow: 3,
            color: 0,
            dynamicRange: .dr400,
            whiteBalanceMode: .auto,
            redShift: 5,
            blueShift: 0,
            colorChrome: .strong,
            fxBlue: .strong,
            sharpness: 0,
            noiseReduction: -3,
            clarity: 3,
            grain: .weak,
            grainSize: .large,
            monochromaticColor: MonochromaticColor(warmCool: -0.25, greenMagenta: -0.25),
            vignette: 0.14,
            halation: 0.01,
            provenance: fujifilmCreatorRecipeProvenance
        ),

        // Additional official Fujifilm creator recipes:
        // https://www.fujifilm-x.com/no-no/stories/astia-fs-recipe-x-mikaela-mertens/
        // https://www.fujifilm-x.com/da-dk/stories/velvia-fs-recipe-x-dominic-stone/
        // https://www.fujifilm-x.com/en-us/stories/velvia-fs-recipe-x-rodrigo-roher/
        // https://www.fujifilm-x.com/en-us/stories/provia-fs-recipe-x-serkan-tekin/
        // https://www.fujifilm-x.com/it-it/stories/pro-neg-std-fs-recipe-x-paolo-emanuele-barretta/
        researchedRecipe(
            id: "honey-portrait",
            name: "Honey Portrait",
            subtitle: "Warm skin / gentle wedding light",
            filmBase: .astia,
            exposure: 0.33,
            highlight: -1,
            shadow: 1,
            color: 0,
            dynamicRange: .dr100,
            whiteBalanceMode: .daylight,
            redShift: 5,
            blueShift: -3,
            colorChrome: .off,
            fxBlue: .off,
            sharpness: 0,
            noiseReduction: 0,
            clarity: -2,
            grain: .weak,
            grainSize: .small,
            vignette: 0.08,
            halation: 0.04,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "pacifica-100",
            name: "Pacifica 100",
            subtitle: "Deep ocean color / restrained vividness",
            filmBase: .velvia,
            highlight: 0,
            shadow: 2.5,
            color: -1,
            dynamicRange: .dr100,
            whiteBalanceMode: .auto,
            redShift: 2,
            blueShift: -2,
            colorChrome: .weak,
            fxBlue: .strong,
            sharpness: 0,
            noiseReduction: 1,
            clarity: -2,
            grain: .strong,
            grainSize: .small,
            vignette: 0.12,
            halation: 0.02,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "desert-daydream",
            name: "Desert Daydream",
            subtitle: "Dusty warmth / saturated distance",
            filmBase: .velvia,
            highlight: -2,
            shadow: 3,
            color: 3,
            dynamicRange: .dr100,
            whiteBalanceMode: .daylight,
            redShift: 2,
            blueShift: -5,
            colorChrome: .weak,
            fxBlue: .weak,
            sharpness: 0,
            noiseReduction: -3,
            clarity: -4,
            grain: .weak,
            grainSize: .small,
            vignette: 0.10,
            halation: 0.03,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "quiet-provia",
            name: "Quiet Provia",
            subtitle: "Muted street color / soft transitions",
            filmBase: .provia,
            highlight: -1,
            shadow: 1,
            color: -1,
            dynamicRange: .dr100,
            whiteBalanceMode: .auto,
            colorChrome: .off,
            fxBlue: .off,
            sharpness: 1,
            noiseReduction: -1,
            clarity: 0,
            grain: .off,
            grainSize: .small,
            vignette: 0.06,
            halation: 0.01,
            provenance: fujifilmCreatorRecipeProvenance
        ),
        researchedRecipe(
            id: "velvet-haze",
            name: "Velvet Haze",
            subtitle: "Soft fashion / cinematic restraint",
            filmBase: .proNegStandard,
            highlight: -2,
            shadow: -1,
            color: 3,
            dynamicRange: .dr400,
            whiteBalanceMode: .colorTemperature,
            kelvin: 4350,
            redShift: 1,
            blueShift: -1,
            colorChrome: .strong,
            fxBlue: .strong,
            sharpness: 2,
            noiseReduction: -4,
            clarity: -5,
            grain: .off,
            grainSize: .small,
            vignette: 0.10,
            halation: 0.06,
            provenance: fujifilmCreatorRecipeProvenance
        ),

        // Community adaptations based on publicly posted Fuji X Weekly menu
        // settings. Product-facing names avoid claiming a film-stock match.
        // https://fujixweekly.com/2020/05/10/my-fujifilm-x-t30-kodak-portra-400-film-simulation-recipe/
        // https://fujixweekly.com/2019/08/02/my-fujifilm-x-t30-kodachrome-64-film-simulation-recipe/
        // https://fujixweekly.com/2024/04/16/cinestill-800t-fujifilm-x-trans-v-film-simulation-recipe/
        // https://fujixweekly.com/2022/05/18/fujifilm-x-e4-x-trans-iv-film-simulation-recipe-pushed-cinestill-800t/
        researchedRecipe(
            id: "pastel-400",
            name: "Pastel 400",
            subtitle: "Warm pastel / forgiving contrast",
            filmBase: .classicChrome,
            exposure: 0.83,
            highlight: -1,
            shadow: -1,
            color: 2,
            dynamicRange: .auto,
            whiteBalanceMode: .daylight,
            redShift: 4,
            blueShift: -5,
            colorChrome: .strong,
            fxBlue: .off,
            sharpness: -2,
            noiseReduction: -4,
            clarity: 0,
            grain: .strong,
            grainSize: .small,
            vignette: 0.10,
            halation: 0.05,
            provenance: communityRecipeProvenance
        ),
        researchedRecipe(
            id: "archive-64",
            name: "Archive 64",
            subtitle: "Warm archive color / crisp contrast",
            filmBase: .classicChrome,
            exposure: 0.67,
            highlight: 1,
            shadow: 2,
            color: 0,
            dynamicRange: .dr400,
            whiteBalanceMode: .daylight,
            redShift: 2,
            blueShift: -5,
            colorChrome: .weak,
            fxBlue: .off,
            sharpness: 2,
            noiseReduction: -4,
            clarity: 0,
            grain: .weak,
            grainSize: .small,
            vignette: 0.09,
            halation: 0.03,
            provenance: communityRecipeProvenance
        ),
        researchedRecipe(
            id: "tungsten-800",
            name: "Tungsten 800",
            subtitle: "Electric night / blooming highlights",
            filmBase: .eterna,
            exposure: 0.17,
            highlight: 0,
            shadow: 2,
            color: 4,
            dynamicRange: .dr400,
            whiteBalanceMode: .fluorescent3,
            redShift: -6,
            blueShift: -4,
            colorChrome: .strong,
            fxBlue: .weak,
            sharpness: -3,
            noiseReduction: -4,
            clarity: -5,
            grain: .strong,
            grainSize: .large,
            vignette: 0.18,
            halation: 0.20,
            provenance: communityRecipeProvenance
        ),
        researchedRecipe(
            id: "pushed-tungsten",
            name: "Pushed Tungsten",
            subtitle: "Cold overcast / dense cinema grain",
            filmBase: .eternaBleachBypass,
            exposure: 0.17,
            highlight: -0.5,
            shadow: -1.5,
            color: 3,
            dynamicRange: .dr400,
            whiteBalanceMode: .colorTemperature,
            kelvin: 7700,
            redShift: -9,
            blueShift: 5,
            colorChrome: .strong,
            fxBlue: .strong,
            sharpness: 0,
            noiseReduction: -4,
            clarity: -3,
            grain: .strong,
            grainSize: .large,
            vignette: 0.18,
            halation: 0.14,
            provenance: communityRecipeProvenance
        ),

        // https://fujixweekly.com/tag/pacific-blues/
        // https://fujixweekly.com/2018/02/03/my-fujifilm-x100f-fujicolor-superia-800-film-simulation-recipe-pro-neg-std/
        // https://fujixweekly.com/2022/03/23/fujifilm-x-trans-iv-film-simulation-recipe-ilford-hp5-plus-400/
        researchedRecipe(
            id: "pacific-blues",
            name: "Pacific Blues",
            subtitle: "Coastal cyan / bright summer color",
            filmBase: .classicNegative,
            exposure: 0.83,
            highlight: -2,
            shadow: 3,
            color: 4,
            dynamicRange: .dr400,
            whiteBalanceMode: .colorTemperature,
            kelvin: 5800,
            redShift: 1,
            blueShift: -3,
            colorChrome: .strong,
            fxBlue: .weak,
            sharpness: -2,
            noiseReduction: -4,
            clarity: -3,
            grain: .strong,
            grainSize: .large,
            vignette: 0.14,
            halation: 0.05,
            provenance: communityRecipeProvenance
        ),
        researchedRecipe(
            id: "green-800",
            name: "Green 800",
            subtitle: "Punchy green / gritty low light",
            filmBase: .proNegStandard,
            exposure: 0.67,
            highlight: 1,
            shadow: 2,
            color: 4,
            dynamicRange: .dr200,
            whiteBalanceMode: .auto,
            redShift: -2,
            blueShift: -3,
            colorChrome: .off,
            fxBlue: .off,
            sharpness: 1,
            noiseReduction: -3,
            clarity: 0,
            grain: .strong,
            grainSize: .large,
            vignette: 0.13,
            halation: 0.04,
            provenance: communityRecipeProvenance
        ),
        researchedRecipe(
            id: "hp5-texture",
            name: "HP5 Texture",
            subtitle: "Open monochrome / coarse latitude",
            filmBase: .monochrome,
            highlight: -1,
            shadow: 1,
            color: 0,
            dynamicRange: .dr400,
            whiteBalanceMode: .daylight,
            redShift: 1,
            blueShift: -8,
            colorChrome: .off,
            fxBlue: .off,
            sharpness: -2,
            noiseReduction: -4,
            clarity: 0,
            grain: .strong,
            grainSize: .large,
            vignette: 0.16,
            halation: 0.01,
            provenance: communityRecipeProvenance
        )
    ]
}


// MARK: - Original creative collections

extension FilmRecipe {
    /// Creative recipes are not vendor calibration profiles or RAW processes.
    static let creativeApproximationDisclaimer =
        "These are original Filmy creative treatments, not pixel-identical film scans or camera output. Filmy is not affiliated with any camera or film manufacturer. A visual style cannot change the sensor, lens, RAW processing, dynamic range, or capture capability. No proprietary LUTs or calibration data are included."

    static let creativeProvenance = Provenance(
        source: .originalCreativeDesign,
        implementation: .originalParametricApproximation,
        calibration: .notCalibratedToCameraHardware,
        references: []
    )

    enum Collection: String, CaseIterable, Sendable {
        case negative, slide, cinema, instant, digital, experimental, monochrome

        var title: String { rawValue.capitalized }
    }

    var creativeCollection: Collection? {
        guard provenance.calibration == .notCalibratedToCameraHardware else { return nil }
        return Collection(rawValue: String(id.split(separator: "-", maxSplits: 1).first ?? ""))
    }

    /// Only G7 X uses the compactDigital renderer's camera-specific flash path.
    /// Other digital aesthetics use a neutral base and their own color controls.
    var isDigitalCameraStyle: Bool { filmBase == .compactDigital || creativeCollection == .digital }

    static let originalCreativeRecipeIDs = originalCreativeLooks.map(\.id)

    private struct CreativeLook {
        let slug: String
        let name: String
        let description: String
        let base: FilmBase
        let exposure: Double
        let highlight: Double
        let shadow: Double
        let saturation: Double
        let contrast: Double
        let temperature: Double
        let tint: Double
        let grain: Double
        let vignette: Double
        let halation: Double
        let clarity: Double

        init(_ slug: String, _ name: String, _ description: String, _ base: FilmBase,
             _ exposure: Double, _ highlight: Double, _ shadow: Double, _ saturation: Double,
             _ contrast: Double, _ temperature: Double, _ tint: Double, _ grain: Double,
             _ vignette: Double, _ halation: Double, _ clarity: Double) {
            self.slug = slug; self.name = name; self.description = description; self.base = base
            self.exposure = exposure; self.highlight = highlight; self.shadow = shadow
            self.saturation = saturation; self.contrast = contrast; self.temperature = temperature
            self.tint = tint; self.grain = grain; self.vignette = vignette; self.halation = halation; self.clarity = clarity
        }

        func recipe(in collection: Collection) -> FilmRecipe {
            let isMono = collection == .monochrome
            let toning: MonochromaticColor
            switch slug {
            case "warm-fiber": toning = .init(warmCool: 0.12)
            case "cool-silver": toning = .init(warmCool: -0.10)
            case "selenium": toning = .init(warmCool: -0.05, greenMagenta: 0.09)
            case "copper-print": toning = .init(warmCool: 0.20, greenMagenta: 0.03)
            case "blue-print": toning = .init(warmCool: -0.42, greenMagenta: -0.04)
            default: toning = .init()
            }
            return FilmRecipe(
                id: "\(collection.rawValue)-\(slug)", name: name, subtitle: description,
                filmBase: base, exposure: exposure, tone: .init(highlight: highlight, shadow: shadow),
                saturation: isMono ? 0 : saturation, contrast: contrast,
                dynamicRange: collection == .cinema || collection == .negative ? .dr200 : .dr100,
                whiteBalance: .init(temperature: temperature, tint: tint), monochromaticColor: toning,
                colorChrome: isMono || collection == .digital ? 0 : ColorChromeLevel.weak.scalarValue,
                blueResponse: isMono ? 0 : (collection == .cinema ? 0.16 : 0.03),
                sharpness: max(-0.12, min(0.22, clarity * 0.6)), noiseReduction: 0.02,
                clarity: clarity, grain: GrainEffectLevel(scalarValue: grain).scalarValue,
                grainSize: grain >= 0.40 ? GrainSizeLevel.large.scalarValue : GrainSizeLevel.small.scalarValue,
                // Colored highlight scatter is reserved for color looks.
                vignette: vignette, halation: isMono ? 0 : halation,
                palette: .init(saturation: isMono ? 0 : 1), provenance: creativeProvenance
            )
        }
    }

    /// Explicit authored settings, not a generated cross-product of names and tints.
    static let originalCreativeLooks: [FilmRecipe] = {
        var result: [FilmRecipe] = []
        let negative: [CreativeLook] = [
            .init("portrait-160", "Portrait 160", "Gentle skin tones / warm daylight", .proNegStandard,
                  0.12, -0.20, 0.10, 0.94, 0.96, 0.06, 0.01, 0.16, 0.04, 0.02, -0.06),
            .init("portrait-400", "Portrait 400", "Soft warm mids / everyday negative", .proNegative,
                  0.08, -0.28, 0.18, 0.96, 1.02, 0.08, 0.02, 0.30, 0.06, 0.04, -0.04),
            .init("portrait-800", "Portrait 800", "Warm shadows / textured indoor color", .nostalgicNegative,
                  0.10, -0.22, 0.23, 0.90, 0.99, 0.11, 0.02, 0.43, 0.10, 0.08, -0.08),
            .init("gold-200", "Gold 200", "Golden daylight / red accents", .classicNegative,
                  0.05, -0.12, 0.08, 1.07, 1.05, 0.14, 0.01, 0.25, 0.10, 0.04, 0.01),
            .init("consumer-400", "Consumer 400", "Lively greens / family snapshots", .realaAce,
                  0.00, -0.10, 0.12, 1.12, 1.06, 0.03, -0.04, 0.34, 0.09, 0.02, 0.03),
            .init("coastal-100", "Coastal 100", "Clear blues / open shadows", .provia,
                  0.10, -0.18, 0.22, 1.08, 0.99, -0.06, -0.02, 0.13, 0.03, 0.01, 0.04),
            .init("city-200", "City 200", "Brick reds / quiet street color", .classicChrome,
                  -0.04, -0.05, 0.06, 0.95, 1.09, 0.03, 0.00, 0.22, 0.11, 0.01, 0.08),
            .init("soft-cream", "Soft Cream", "Cream highlights / muted foliage", .astia,
                  0.17, -0.30, 0.24, 0.88, 0.92, 0.09, 0.03, 0.17, 0.05, 0.05, -0.10),
            .init("olive-400", "Olive 400", "Olive greens / warm concrete", .classicNegative,
                  -0.02, -0.16, 0.13, 0.93, 1.07, 0.04, -0.06, 0.32, 0.12, 0.03, 0.04),
            .init("rose-200", "Rose 200", "Rose mids / restrained blues", .proNegStandard,
                  0.08, -0.18, 0.15, 0.98, 0.98, 0.04, 0.07, 0.19, 0.06, 0.04, -0.04),
            .init("pastel-day", "Pastel Day", "Airy color / soft high key", .astia,
                  0.22, -0.32, 0.26, 0.84, 0.90, 0.01, 0.02, 0.14, 0.02, 0.03, -0.12),
            .init("woodland", "Woodland Negative", "Earthy greens / deep mids", .realaAce,
                  -0.07, -0.20, 0.00, 0.96, 1.10, 0.00, -0.05, 0.24, 0.12, 0.02, 0.07),
            .init("copper-800", "Copper 800", "Copper warmth / evening grain", .nostalgicNegative,
                  -0.03, -0.24, 0.17, 0.93, 1.05, 0.16, 0.04, 0.46, 0.13, 0.10, -0.02),
            .init("winter-200", "Winter 200", "Cool whites / quiet daylight", .provia,
                  0.08, -0.24, 0.21, 0.83, 0.98, -0.13, 0.01, 0.20, 0.04, 0.02, 0.04),
            .init("travel-400", "Travel 400", "Balanced color / forgiving contrast", .realaAce,
                  0.05, -0.18, 0.17, 1.03, 1.02, 0.05, 0.00, 0.27, 0.07, 0.03, 0.02),
            .init("faded-album", "Faded Album", "Faded dye / warm paper memory", .nostalgicNegative,
                  0.10, -0.38, 0.32, 0.72, 0.87, 0.14, 0.03, 0.38, 0.18, 0.08, -0.13),
        ]
        result += negative.map { $0.recipe(in: .negative) }
        let slide: [CreativeLook] = [
            .init("chrome-50", "Chrome 50", "Crisp daylight / saturated primaries", .velvia,
                  -0.08, 0.06, -0.10, 1.09, 1.15, -0.01, 0.00, 0.10, 0.08, 0.01, 0.12),
            .init("chrome-100", "Chrome 100", "Clean whites / rich travel color", .provia,
                  -0.04, 0.02, -0.06, 1.14, 1.12, 0.00, 0.01, 0.12, 0.06, 0.02, 0.10),
            .init("mountain-50", "Mountain 50", "Deep skies / alpine greens", .velvia,
                  -0.15, 0.08, -0.16, 1.08, 1.18, -0.08, -0.02, 0.09, 0.12, 0.01, 0.15),
            .init("warm-projector", "Warm Projector", "Amber transparency / rich mids", .provia,
                  -0.03, 0.03, -0.06, 1.06, 1.14, 0.13, 0.02, 0.18, 0.14, 0.04, 0.08),
            .init("cool-chrome", "Cool Chrome", "Cool shadows / precise blues", .realaAce,
                  -0.06, 0.04, -0.08, 1.08, 1.13, -0.12, 0.02, 0.11, 0.05, 0.01, 0.13),
            .init("sunset-chrome", "Sunset Chrome", "Glowing reds / dense sunset color", .velvia,
                  -0.10, -0.05, -0.12, 1.12, 1.16, 0.16, 0.04, 0.14, 0.10, 0.06, 0.08),
            .init("botanical", "Botanical Slide", "Lush greens / bright floral color", .velvia,
                  -0.07, -0.06, -0.04, 1.10, 1.11, 0.00, -0.05, 0.10, 0.07, 0.02, 0.10),
            .init("soft-transparency", "Soft Transparency", "Delicate slide color / broad highlights", .astia,
                  0.05, -0.24, 0.05, 1.01, 1.04, 0.02, 0.01, 0.09, 0.03, 0.02, -0.03),
            .init("blue-hour", "Blue Hour Slide", "Cobalt dusk / crisp contrast", .provia,
                  -0.14, -0.10, -0.06, 1.06, 1.13, -0.17, 0.04, 0.19, 0.13, 0.04, 0.09),
            .init("archive-projector", "Archive Projector", "Warm reds / aged transparency", .classicChrome,
                  -0.04, -0.12, 0.10, 0.87, 1.11, 0.12, 0.03, 0.28, 0.19, 0.05, 0.02),
        ]
        result += slide.map { $0.recipe(in: .slide) }
        let cinema: [CreativeLook] = [
            .init("daylight-250", "Daylight 250", "Restrained daylight / filmic mids", .eterna,
                  0.05, -0.25, 0.18, 1.02, 1.03, 0.04, 0.01, 0.22, 0.06, 0.05, -0.02),
            .init("tungsten-500", "Cinema Tungsten 500", "Cool shadows / warm practical lights", .eterna,
                  -0.04, -0.23, 0.13, 1.00, 1.07, -0.08, 0.03, 0.34, 0.10, 0.13, -0.03),
            .init("night-neon", "Night Neon", "Electric color / luminous highlights", .standard,
                  -0.10, -0.18, 0.06, 1.19, 1.12, -0.12, 0.09, 0.25, 0.18, 0.22, 0.06),
            .init("silver-screen", "Silver Screen Color", "Bleached color / dense blacks", .eternaBleachBypass,
                  -0.06, -0.04, -0.04, 0.86, 1.10, -0.02, 0.00, 0.33, 0.12, 0.03, 0.12),
            .init("amber-teal", "Amber and Teal", "Warm mids / blue-green shadows", .eterna,
                  0.00, -0.20, 0.08, 1.06, 1.10, 0.07, -0.04, 0.21, 0.11, 0.09, 0.01),
            .init("matinee", "Matinee", "Soft highlights / nostalgic color", .eterna,
                  0.12, -0.32, 0.25, 0.93, 0.94, 0.08, 0.01, 0.18, 0.06, 0.07, -0.09),
            .init("noir-color", "Color Noir", "Low saturation / hard street light", .eternaBleachBypass,
                  -0.14, 0.02, -0.12, 0.57, 1.17, -0.06, 0.02, 0.41, 0.21, 0.07, 0.14),
            .init("road-movie", "Road Movie", "Dry earth / muted sky", .classicChrome,
                  0.00, -0.18, 0.14, 0.86, 1.06, 0.10, -0.03, 0.27, 0.12, 0.05, 0.03),
            .init("rainy-city", "Rainy City", "Cool concrete / restrained neon", .eterna,
                  -0.08, -0.20, 0.18, 0.82, 1.07, -0.13, 0.03, 0.28, 0.13, 0.08, 0.02),
            .init("summer-feature", "Summer Feature", "Sunlit warmth / soft greens", .eterna,
                  0.13, -0.25, 0.22, 1.06, 0.97, 0.12, -0.02, 0.19, 0.05, 0.08, -0.04),
            .init("velvet-night", "Velvet Night", "Violet dusk / soft highlight bloom", .standard,
                  -0.09, -0.26, 0.17, 0.92, 1.02, -0.05, 0.11, 0.36, 0.17, 0.18, -0.11),
            .init("newsreel-color", "Newsreel Color", "Muted reporting / coarse texture", .classicChrome,
                  -0.03, -0.08, 0.10, 0.72, 1.13, 0.03, -0.01, 0.52, 0.10, 0.02, 0.09),
        ]
        result += cinema.map { $0.recipe(in: .cinema) }
        let instant: [CreativeLook] = [
            .init("cream-square", "Cream Square", "Cream whites / gentle instant color", .nostalgicNegative,
                  0.12, -0.34, 0.28, 0.87, 0.91, 0.10, 0.02, 0.28, 0.16, 0.08, -0.11),
            .init("pastel-square", "Pastel Square", "Pale blue shadows / pink highlights", .astia,
                  0.20, -0.30, 0.25, 0.79, 0.90, -0.03, 0.05, 0.20, 0.12, 0.07, -0.12),
            .init("sun-faded", "Sun Faded Instant", "Faded warm print / dusty greens", .classicNegative,
                  0.08, -0.36, 0.31, 0.71, 0.89, 0.15, -0.02, 0.36, 0.22, 0.10, -0.08),
            .init("cool-pack", "Cool Pack", "Cool cyan / clean paper whites", .proNegStandard,
                  0.10, -0.24, 0.22, 0.86, 0.94, -0.13, -0.04, 0.25, 0.13, 0.04, -0.04),
            .init("party-pack", "Party Pack", "Punchy color / direct-light mood", .standard,
                  0.05, -0.06, -0.05, 1.20, 1.15, 0.04, 0.04, 0.32, 0.25, 0.08, 0.08),
            .init("warm-pack", "Warm Pack", "Warm orange / soft indoor color", .nostalgicNegative,
                  0.07, -0.23, 0.20, 0.95, 0.96, 0.17, 0.03, 0.31, 0.17, 0.11, -0.05),
            .init("soft-focus", "Soft Focus Instant", "Low clarity / luminous white edges", .astia,
                  0.19, -0.38, 0.29, 0.85, 0.88, 0.05, 0.02, 0.22, 0.15, 0.19, -0.25),
            .init("expired-pack", "Expired Pack", "Green cast / aged instant mood", .standard,
                  0.00, -0.27, 0.23, 0.77, 0.95, 0.08, -0.13, 0.47, 0.30, 0.09, -0.09),
        ]
        result += instant.map { $0.recipe(in: .instant) }
        let digital: [CreativeLook] = [
            .init("ccd-daylight", "CCD Daylight", "Pocket CCD-inspired / crisp blue skies", .standard,
                  0.00, -0.03, -0.02, 1.15, 1.12, -0.04, 0.01, 0.05, 0.08, 0.00, 0.14),
            .init("ccd-twilight", "CCD Twilight", "Early digital mood / cool evening color", .standard,
                  -0.08, -0.09, 0.05, 1.03, 1.09, -0.12, 0.04, 0.18, 0.12, 0.04, 0.10),
            .init("pocket-positive", "Pocket Positive", "Street compact-inspired / vivid reds", .standard,
                  -0.03, -0.04, -0.07, 1.19, 1.16, 0.04, 0.02, 0.04, 0.14, 0.00, 0.16),
            .init("pocket-negative", "Pocket Negative", "Street compact-inspired / muted earth", .classicChrome,
                  0.02, -0.21, 0.18, 0.87, 1.00, 0.07, -0.02, 0.12, 0.10, 0.02, 0.04),
            .init("rangefinder-color", "Rangefinder Color", "Crisp edges / restrained primary color", .standard,
                  -0.03, -0.08, -0.06, 0.96, 1.14, 0.01, 0.00, 0.03, 0.11, 0.00, 0.18),
            .init("rangefinder-soft", "Rangefinder Soft", "Gentle mids / warm portrait rendering", .proNegStandard,
                  0.08, -0.22, 0.14, 0.94, 0.98, 0.06, 0.02, 0.02, 0.08, 0.01, -0.07),
            .init("mirrorless-clean", "Mirrorless Clean", "Neutral modern color / low texture", .standard,
                  0.00, -0.10, 0.08, 1.00, 1.03, 0.00, 0.00, 0.00, 0.00, 0.00, 0.07),
            .init("mirrorless-vivid", "Mirrorless Vivid", "Crisp detail / high color separation", .standard,
                  -0.03, -0.06, 0.02, 1.22, 1.12, 0.01, -0.01, 0.00, 0.03, 0.00, 0.19),
            .init("mirrorless-portrait", "Mirrorless Portrait", "Gentle skin / soft local contrast", .standard,
                  0.10, -0.22, 0.18, 0.95, 0.96, 0.04, 0.03, 0.00, 0.03, 0.01, -0.08),
            .init("bridge-zoom", "Bridge Zoom", "Early bridge-camera mood / crisp greens", .standard,
                  -0.01, -0.04, -0.04, 1.10, 1.10, -0.02, -0.04, 0.08, 0.13, 0.00, 0.17),
            .init("pocket-flash", "Pocket Flash Color", "Direct-flash aesthetic / does not fire flash", .standard,
                  0.05, 0.03, -0.11, 1.14, 1.19, 0.03, 0.03, 0.10, 0.25, 0.04, 0.13),
            .init("pocket-soft", "Pocket Soft", "Compact-camera mood / gentle highlights", .standard,
                  0.12, -0.25, 0.16, 0.98, 0.94, 0.08, 0.01, 0.05, 0.09, 0.06, -0.10),
            .init("cmos-studio", "CMOS Studio", "Clean neutral whites / precise mids", .standard,
                  0.04, -0.16, 0.09, 1.02, 1.06, 0.00, 0.01, 0.00, 0.01, 0.00, 0.11),
            .init("cmos-night", "CMOS Night Color", "Cool low-key mood / no exposure stacking", .standard,
                  -0.07, -0.19, 0.20, 0.92, 1.04, -0.08, 0.02, 0.04, 0.08, 0.05, -0.02),
            .init("toy-digital", "Toy Digital", "Punchy low-fi color / heavy corner shade", .standard,
                  -0.02, 0.08, -0.16, 1.29, 1.24, 0.07, -0.05, 0.23, 0.44, 0.04, 0.09),
            .init("compact-sunset", "Compact Sunset", "Warm compact style / rich evening color", .standard,
                  0.01, -0.18, 0.10, 1.10, 1.07, 0.16, 0.03, 0.06, 0.12, 0.06, 0.04),
        ]
        result += digital.map { $0.recipe(in: .digital) }
        let experimental: [CreativeLook] = [
            .init("cross-process", "Cross Process", "Cyan shadows / shifted warm highlights", .standard,
                  -0.03, -0.03, -0.05, 1.22, 1.18, -0.05, -0.12, 0.25, 0.17, 0.06, 0.07),
            .init("red-dusk", "Red Dusk", "Red-cast fantasy / low-key color", .standard,
                  -0.10, -0.09, 0.10, 0.93, 1.10, 0.27, 0.11, 0.32, 0.23, 0.11, -0.03),
            .init("mint-dream", "Mint Dream", "Mint shadows / soft pink midtones", .astia,
                  0.17, -0.33, 0.28, 0.81, 0.90, -0.10, -0.10, 0.20, 0.09, 0.12, -0.14),
            .init("violet-hour", "Violet Hour", "Purple cast / cool dreamlike color", .standard,
                  -0.03, -0.20, 0.16, 0.98, 1.04, -0.15, 0.19, 0.27, 0.16, 0.14, -0.08),
            .init("solar-gold", "Solar Gold", "Hot gold / dense summer reds", .classicNegative,
                  0.08, 0.04, -0.09, 1.14, 1.16, 0.25, 0.02, 0.22, 0.20, 0.16, 0.03),
            .init("washed-cyan", "Washed Cyan", "Faded cyan / experimental dye mood", .standard,
                  0.13, -0.35, 0.31, 0.75, 0.88, -0.16, -0.06, 0.37, 0.17, 0.08, -0.12),
        ]
        result += experimental.map { $0.recipe(in: .experimental) }
        let monochrome: [CreativeLook] = [
            .init("silver-100", "Silver 100", "Fine neutral grain / everyday monochrome", .acros,
                  0.02, -0.12, 0.09, 0, 1.06, 0, 0, 0.16, 0.06, 0.01, 0.08),
            .init("silver-400", "Silver 400", "Classic grain / documentary contrast", .acros,
                  0.00, -0.04, 0.03, 0, 1.13, 0, 0, 0.34, 0.10, 0.02, 0.12),
            .init("silver-1600", "Silver 1600", "Pushed texture / dense midtones", .acros,
                  -0.08, 0.08, -0.06, 0, 1.24, 0, 0, 0.60, 0.15, 0.04, 0.17),
            .init("fine-25", "Fine 25", "Smooth grayscale / crisp studio light", .monochrome,
                  0.04, -0.18, 0.12, 0, 1.03, 0, 0, 0.05, 0.02, 0.00, 0.10),
            .init("street-hard", "Street Hard", "Hard blacks / bold reportage", .acrosRed,
                  -0.12, 0.11, -0.17, 0, 1.30, 0, 0, 0.47, 0.19, 0.02, 0.23),
            .init("street-soft", "Street Soft", "Open shadows / gentle reportage", .acros,
                  0.08, -0.28, 0.24, 0, 0.95, 0, 0, 0.29, 0.09, 0.02, -0.04),
            .init("portrait-green", "Portrait Green Filter", "Green-channel emphasis / nuanced skin", .acrosGreen,
                  0.07, -0.22, 0.17, 0, 1.01, 0, 0, 0.18, 0.06, 0.02, -0.06),
            .init("landscape-red", "Landscape Red Filter", "Dark skies / dramatic cloud contrast", .acrosRed,
                  -0.07, 0.05, -0.08, 0, 1.20, 0, 0, 0.21, 0.10, 0.01, 0.15),
            .init("classic-yellow", "Classic Yellow Filter", "Balanced skin / gentle sky separation", .acrosYellow,
                  0.01, -0.12, 0.07, 0, 1.10, 0, 0, 0.26, 0.07, 0.02, 0.09),
            .init("matte-paper", "Matte Paper", "Lifted blacks / soft fiber-print mood", .monochrome,
                  0.12, -0.36, 0.34, 0, 0.87, 0, 0, 0.31, 0.12, 0.05, -0.12),
            .init("gloss-paper", "Gloss Paper", "Dense blacks / brilliant print whites", .acros,
                  -0.04, 0.07, -0.12, 0, 1.22, 0, 0, 0.12, 0.08, 0.01, 0.17),
            .init("noir-rain", "Noir Rain", "Deep cool grayscale / wet streets", .acrosRed,
                  -0.15, 0.01, -0.13, 0, 1.25, 0, 0, 0.39, 0.24, 0.08, 0.13),
            .init("high-key", "High Key Silver", "Airy whites / gentle portraits", .acrosGreen,
                  0.28, -0.35, 0.28, 0, 0.91, 0, 0, 0.14, 0.02, 0.04, -0.10),
            .init("low-key", "Low Key Silver", "Dense midtones / dark studio mood", .acros,
                  -0.26, -0.05, -0.18, 0, 1.19, 0, 0, 0.20, 0.22, 0.01, 0.11),
            .init("warm-fiber", "Warm Fiber", "Warm silver tone / soft paper texture", .monochrome,
                  0.05, -0.22, 0.20, 0, 0.98, 0, 0, 0.28, 0.12, 0.04, -0.02),
            .init("cool-silver", "Cool Silver", "Cool silver tone / clean tonal detail", .acros,
                  0.00, -0.14, 0.08, 0, 1.12, 0, 0, 0.17, 0.08, 0.01, 0.14),
            .init("selenium", "Selenium Mood", "Subtle purple tone / dense darks", .acros,
                  -0.04, -0.08, -0.06, 0, 1.16, 0, 0, 0.23, 0.14, 0.02, 0.09),
            .init("copper-print", "Copper Print", "Warm brown tone / archival print mood", .sepia,
                  0.06, -0.24, 0.20, 0, 0.97, 0, 0, 0.34, 0.19, 0.05, -0.03),
            .init("blue-print", "Blue Print", "Blue-toned monochrome / graphic mood", .monochrome,
                  0.03, -0.14, 0.08, 0, 1.11, 0, 0, 0.12, 0.08, 0.01, 0.12),
            .init("press-3200", "Press 3200", "Coarse grain / pushed reporting", .acrosYellow,
                  -0.09, 0.12, -0.05, 0, 1.27, 0, 0, 0.78, 0.16, 0.07, 0.19),
            .init("night-silver", "Night Silver", "Soft highlight roll-off / textured darks", .acros,
                  -0.12, -0.22, 0.09, 0, 1.14, 0, 0, 0.51, 0.23, 0.19, -0.05),
            .init("architecture", "Architectural Silver", "Clean geometry / crisp neutral edges", .monochrome,
                  -0.03, -0.07, -0.03, 0, 1.18, 0, 0, 0.08, 0.04, 0.00, 0.26),
            .init("soft-charcoal", "Soft Charcoal", "Muted graphite / gentle texture", .acrosGreen,
                  0.10, -0.31, 0.30, 0, 0.90, 0, 0, 0.42, 0.11, 0.06, -0.16),
            .init("silver-rangefinder", "Silver Rangefinder", "Rangefinder-inspired / fine tonal separation", .monochrome,
                  0.00, -0.10, 0.02, 0, 1.15, 0, 0, 0.09, 0.09, 0.00, 0.18),
        ]
        result += monochrome.map { $0.recipe(in: .monochrome) }
        return result
    }()
}
