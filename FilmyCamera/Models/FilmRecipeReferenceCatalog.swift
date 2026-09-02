import Foundation

/// A traceable, machine-readable boundary between public camera vocabulary and
/// Filmy Camera's independent recipe implementation.
///
/// The prior preset snapshot contains public control values from the old
/// FilmyCam model. It is reference data only: it is not a LUT, a calibration
/// profile, or a claim that the current normalized `FilmRecipe` values have
/// Fujifilm hardware semantics.
public enum FilmRecipeReferenceCatalog {
    public static let schemaVersion = 1
    public static let referenceLookCount = 16
    public static let disclosure = FilmRecipe.independentApproximationDisclaimer

    /// The repository snapshot used for the comparison pass. Only names and
    /// public control values are represented below; no source code or assets
    /// from that repository are shipped by this app.
    public struct SourceSnapshot: Codable, Hashable, Sendable {
        public let repository: String
        public let commit: String
        public let path: String
        public let scope: String

        public init(repository: String, commit: String, path: String, scope: String) {
            self.repository = repository
            self.commit = commit
            self.path = path
            self.scope = scope
        }
    }

    public static let sourceSnapshot = SourceSnapshot(
        repository: "dheeraj5612/filmycam",
        commit: "8d2698881f602c37ddce0585890cbf729db867ca",
        path: "FilmyCam/FilmyCam/Domain/Models/FujifilmRecipe+Presets.swift",
        scope: "Public preset names and public control values only"
    )

    public enum SettingsSource: String, Codable, Hashable, Sendable {
        case priorPrivateRepositoryPresetSnapshot
        case currentAppPublicBaseline
    }

    /// The old model's public-facing recipe controls, retained at their
    /// original discrete scales for auditability. These values are not
    /// converted into the app's normalized renderer controls.
    public struct PublicControls: Codable, Hashable, Sendable {
        public let filmSimulation: String
        public let dynamicRange: String
        public let highlightTone: Int
        public let shadowTone: Int
        public let color: Int
        public let colorChromeEffect: String
        public let colorChromeFXBlue: String
        public let sharpness: Int
        public let noiseReduction: Int
        public let clarity: Int
        public let grainEffect: String
        public let grainSize: String
        public let whiteBalance: String
        public let whiteBalanceShiftRed: Int
        public let whiteBalanceShiftBlue: Int
        public let exposureCompensationEV: Double
        public let colorTemperatureKelvin: Int?

        public init(
            filmSimulation: String,
            dynamicRange: String,
            highlightTone: Int,
            shadowTone: Int,
            color: Int,
            colorChromeEffect: String,
            colorChromeFXBlue: String,
            sharpness: Int,
            noiseReduction: Int,
            clarity: Int,
            grainEffect: String,
            grainSize: String,
            whiteBalance: String,
            whiteBalanceShiftRed: Int,
            whiteBalanceShiftBlue: Int,
            exposureCompensationEV: Double,
            colorTemperatureKelvin: Int? = nil
        ) {
            self.filmSimulation = filmSimulation
            self.dynamicRange = dynamicRange
            self.highlightTone = highlightTone
            self.shadowTone = shadowTone
            self.color = color
            self.colorChromeEffect = colorChromeEffect
            self.colorChromeFXBlue = colorChromeFXBlue
            self.sharpness = sharpness
            self.noiseReduction = noiseReduction
            self.clarity = clarity
            self.grainEffect = grainEffect
            self.grainSize = grainSize
            self.whiteBalance = whiteBalance
            self.whiteBalanceShiftRed = whiteBalanceShiftRed
            self.whiteBalanceShiftBlue = whiteBalanceShiftBlue
            self.exposureCompensationEV = exposureCompensationEV
            self.colorTemperatureKelvin = colorTemperatureKelvin
        }
    }

    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        /// Equal to the current app recipe id so the relationship is stable
        /// across display-name changes.
        public let id: String
        public let currentRecipeID: String
        public let canonicalPublicName: String
        public let currentFilmBase: FilmRecipe.FilmBase
        public let settingsSource: SettingsSource
        public let priorPresetOrdinal: Int?
        public let priorPresetID: String?
        public let priorPresetName: String?
        public let publicControls: PublicControls?
        public let note: String

        public init(
            id: String,
            currentRecipeID: String,
            canonicalPublicName: String,
            currentFilmBase: FilmRecipe.FilmBase,
            settingsSource: SettingsSource,
            priorPresetOrdinal: Int? = nil,
            priorPresetID: String? = nil,
            priorPresetName: String? = nil,
            publicControls: PublicControls? = nil,
            note: String
        ) {
            self.id = id
            self.currentRecipeID = currentRecipeID
            self.canonicalPublicName = canonicalPublicName
            self.currentFilmBase = currentFilmBase
            self.settingsSource = settingsSource
            self.priorPresetOrdinal = priorPresetOrdinal
            self.priorPresetID = priorPresetID
            self.priorPresetName = priorPresetName
            self.publicControls = publicControls
            self.note = note
        }

        /// The current implementation that this reference entry audits.
        /// This lookup is intentionally separate from the Codable payload so
        /// a catalog entry cannot silently overwrite the production recipe.
        public var currentRecipe: FilmRecipe? {
            FilmRecipe.builtIns.first { $0.id == currentRecipeID }
        }
    }

    public struct Document: Codable, Hashable, Sendable {
        public let schemaVersion: Int
        public let referenceLookCount: Int
        public let sourceSnapshot: SourceSnapshot
        public let disclosure: String
        public let entries: [Entry]
        public let intentionallyUnlistedBuiltInRecipeIDs: [String]

        public init(
            schemaVersion: Int,
            referenceLookCount: Int,
            sourceSnapshot: SourceSnapshot,
            disclosure: String,
            entries: [Entry],
            intentionallyUnlistedBuiltInRecipeIDs: [String]
        ) {
            self.schemaVersion = schemaVersion
            self.referenceLookCount = referenceLookCount
            self.sourceSnapshot = sourceSnapshot
            self.disclosure = disclosure
            self.entries = entries
            self.intentionallyUnlistedBuiltInRecipeIDs = intentionallyUnlistedBuiltInRecipeIDs
        }
    }

    /// Sixteen public-reference looks: the fifteen prior-repo core presets
    /// plus the current app's public MONOCHROME baseline. `sepia-archive` is
    /// intentionally excluded because it is an app-original extra, not a
    /// prior-repo Fujifilm reference preset.
    public static let entries: [Entry] = [
        prior(
            currentRecipeID: "provia-standard",
            canonicalPublicName: "PROVIA/STANDARD",
            currentFilmBase: .provia,
            priorPresetOrdinal: 1,
            priorPresetID: "00000001-0001-0001-0001-000000000001",
            priorPresetName: "Provia Standard",
            controls: PublicControls(
                filmSimulation: "provia",
                dynamicRange: "auto",
                highlightTone: 0,
                shadowTone: 0,
                color: 0,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: 0,
                noiseReduction: 0,
                clarity: 0,
                grainEffect: "off",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "classic-chrome",
            canonicalPublicName: "CLASSIC CHROME",
            currentFilmBase: .classicChrome,
            priorPresetOrdinal: 4,
            priorPresetID: "00000001-0001-0001-0001-000000000004",
            priorPresetName: "Classic Chrome",
            controls: PublicControls(
                filmSimulation: "classic_chrome",
                dynamicRange: "dr200",
                highlightTone: 0,
                shadowTone: 1,
                color: -1,
                colorChromeEffect: "weak",
                colorChromeFXBlue: "off",
                sharpness: 0,
                noiseReduction: 0,
                clarity: 0,
                grainEffect: "weak",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "velvia-vivid",
            canonicalPublicName: "Velvia/VIVID",
            currentFilmBase: .velvia,
            priorPresetOrdinal: 2,
            priorPresetID: "00000001-0001-0001-0001-000000000002",
            priorPresetName: "Velvia Vivid",
            controls: PublicControls(
                filmSimulation: "velvia",
                dynamicRange: "dr200",
                highlightTone: 0,
                shadowTone: 0,
                color: 2,
                colorChromeEffect: "weak",
                colorChromeFXBlue: "weak",
                sharpness: 1,
                noiseReduction: 0,
                clarity: 1,
                grainEffect: "off",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "astia-soft",
            canonicalPublicName: "ASTIA/SOFT",
            currentFilmBase: .astia,
            priorPresetOrdinal: 3,
            priorPresetID: "00000001-0001-0001-0001-000000000003",
            priorPresetName: "Astia Soft",
            controls: PublicControls(
                filmSimulation: "astia",
                dynamicRange: "dr200",
                highlightTone: -1,
                shadowTone: 0,
                color: 0,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: -1,
                noiseReduction: 1,
                clarity: -1,
                grainEffect: "off",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 1,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0.3
            )
        ),
        prior(
            currentRecipeID: "pro-neg-high",
            canonicalPublicName: "PRO Neg. Hi",
            currentFilmBase: .proNegative,
            priorPresetOrdinal: 5,
            priorPresetID: "00000001-0001-0001-0001-000000000005",
            priorPresetName: "Pro Neg Hi",
            controls: PublicControls(
                filmSimulation: "pro_neg_hi",
                dynamicRange: "dr200",
                highlightTone: 1,
                shadowTone: -1,
                color: -1,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: 1,
                noiseReduction: 0,
                clarity: 1,
                grainEffect: "off",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "eterna-cinema",
            canonicalPublicName: "ETERNA/CINEMA",
            currentFilmBase: .eterna,
            priorPresetOrdinal: 7,
            priorPresetID: "00000001-0001-0001-0001-000000000007",
            priorPresetName: "Eterna Cinema",
            controls: PublicControls(
                filmSimulation: "eterna",
                dynamicRange: "dr400",
                highlightTone: -2,
                shadowTone: 2,
                color: -2,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: -1,
                noiseReduction: 0,
                clarity: 0,
                grainEffect: "off",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        currentBaseline(
            currentRecipeID: "acros-monochrome",
            canonicalPublicName: "MONOCHROME",
            currentFilmBase: .monochrome,
            note: "No counterpart exists in the prior repo snapshot. The current FilmRecipe values are an app-defined normalized baseline using public MONOCHROME vocabulary."
        ),
        prior(
            currentRecipeID: "acros-neutral-filter",
            canonicalPublicName: "ACROS",
            currentFilmBase: .acros,
            priorPresetOrdinal: 9,
            priorPresetID: "00000001-0001-0001-0001-000000000009",
            priorPresetName: "Acros",
            controls: PublicControls(
                filmSimulation: "acros",
                dynamicRange: "dr200",
                highlightTone: 0,
                shadowTone: 0,
                color: 0,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: 1,
                noiseReduction: 0,
                clarity: 1,
                grainEffect: "weak",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "acros-yellow-filter",
            canonicalPublicName: "ACROS + Ye",
            currentFilmBase: .acrosYellow,
            priorPresetOrdinal: 10,
            priorPresetID: "00000001-0001-0001-0001-00000000000a",
            priorPresetName: "Acros+Ye Filter",
            controls: PublicControls(
                filmSimulation: "acros_ye",
                dynamicRange: "dr200",
                highlightTone: 1,
                shadowTone: 0,
                color: 0,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: 1,
                noiseReduction: 0,
                clarity: 1,
                grainEffect: "weak",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "acros-red-filter",
            canonicalPublicName: "ACROS + R",
            currentFilmBase: .acrosRed,
            priorPresetOrdinal: 11,
            priorPresetID: "00000001-0001-0001-0001-00000000000b",
            priorPresetName: "Acros+R Filter",
            controls: PublicControls(
                filmSimulation: "acros_r",
                dynamicRange: "dr200",
                highlightTone: 2,
                shadowTone: -1,
                color: 0,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: 2,
                noiseReduction: 0,
                clarity: 2,
                grainEffect: "weak",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "acros-green-filter",
            canonicalPublicName: "ACROS + G",
            currentFilmBase: .acrosGreen,
            priorPresetOrdinal: 12,
            priorPresetID: "00000001-0001-0001-0001-00000000000c",
            priorPresetName: "Acros+G Filter",
            controls: PublicControls(
                filmSimulation: "acros_g",
                dynamicRange: "dr200",
                highlightTone: -1,
                shadowTone: 1,
                color: 0,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: 0,
                noiseReduction: 1,
                clarity: 0,
                grainEffect: "weak",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "classic-negative",
            canonicalPublicName: "CLASSIC Neg.",
            currentFilmBase: .classicNegative,
            priorPresetOrdinal: 13,
            priorPresetID: "00000001-0001-0001-0001-00000000000d",
            priorPresetName: "Classic Negative",
            controls: PublicControls(
                filmSimulation: "classic_neg",
                dynamicRange: "dr200",
                highlightTone: 0,
                shadowTone: 2,
                color: 2,
                colorChromeEffect: "strong",
                colorChromeFXBlue: "weak",
                sharpness: 0,
                noiseReduction: 0,
                clarity: 0,
                grainEffect: "weak",
                grainSize: "small",
                whiteBalance: "daylight",
                whiteBalanceShiftRed: 3,
                whiteBalanceShiftBlue: -2,
                exposureCompensationEV: 0.3
            )
        ),
        prior(
            currentRecipeID: "nostalgic-negative",
            canonicalPublicName: "NOSTALGIC Neg.",
            currentFilmBase: .nostalgicNegative,
            priorPresetOrdinal: 14,
            priorPresetID: "00000001-0001-0001-0001-00000000000e",
            priorPresetName: "Nostalgic Negative",
            controls: PublicControls(
                filmSimulation: "nostalgic_neg",
                dynamicRange: "dr200",
                highlightTone: -1,
                shadowTone: 2,
                color: 1,
                colorChromeEffect: "weak",
                colorChromeFXBlue: "weak",
                sharpness: 0,
                noiseReduction: 0,
                clarity: 0,
                grainEffect: "weak",
                grainSize: "large",
                whiteBalance: "daylight",
                whiteBalanceShiftRed: 4,
                whiteBalanceShiftBlue: -3,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "eterna-bleach-bypass",
            canonicalPublicName: "ETERNA BLEACH BYPASS",
            currentFilmBase: .eternaBleachBypass,
            priorPresetOrdinal: 8,
            priorPresetID: "00000001-0001-0001-0001-000000000008",
            priorPresetName: "Eterna Bleach Bypass",
            controls: PublicControls(
                filmSimulation: "eterna_bleach_bypass",
                dynamicRange: "dr200",
                highlightTone: 2,
                shadowTone: -1,
                color: -3,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: 1,
                noiseReduction: 0,
                clarity: 2,
                grainEffect: "weak",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "pro-neg-standard",
            canonicalPublicName: "PRO Neg. Std",
            currentFilmBase: .proNegStandard,
            priorPresetOrdinal: 6,
            priorPresetID: "00000001-0001-0001-0001-000000000006",
            priorPresetName: "Pro Neg Std",
            controls: PublicControls(
                filmSimulation: "pro_neg_std",
                dynamicRange: "dr200",
                highlightTone: -1,
                shadowTone: 1,
                color: -1,
                colorChromeEffect: "off",
                colorChromeFXBlue: "off",
                sharpness: -1,
                noiseReduction: 1,
                clarity: -1,
                grainEffect: "off",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 1,
                whiteBalanceShiftBlue: 0,
                exposureCompensationEV: 0
            )
        ),
        prior(
            currentRecipeID: "reala-ace",
            canonicalPublicName: "REALA ACE",
            currentFilmBase: .realaAce,
            priorPresetOrdinal: 15,
            priorPresetID: "00000001-0001-0001-0001-00000000000f",
            priorPresetName: "Reala Ace",
            controls: PublicControls(
                filmSimulation: "reala_ace",
                dynamicRange: "dr200",
                highlightTone: 0,
                shadowTone: 0,
                color: -1,
                colorChromeEffect: "off",
                colorChromeFXBlue: "weak",
                sharpness: 0,
                noiseReduction: 0,
                clarity: 0,
                grainEffect: "off",
                grainSize: "small",
                whiteBalance: "auto",
                whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 1,
                exposureCompensationEV: 0
            )
        )
    ]

    public static let document = Document(
        schemaVersion: schemaVersion,
        referenceLookCount: referenceLookCount,
        sourceSnapshot: sourceSnapshot,
        disclosure: disclosure,
        entries: entries,
        intentionallyUnlistedBuiltInRecipeIDs: ["sepia-archive", "g7x-compact"]
            + FilmRecipe.expandedInternetRecipeIDs
    )

    /// Exports the catalog without exposing any non-catalog renderer state.
    public static func jsonData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(document)
    }

    private static func prior(
        currentRecipeID: String,
        canonicalPublicName: String,
        currentFilmBase: FilmRecipe.FilmBase,
        priorPresetOrdinal: Int,
        priorPresetID: String,
        priorPresetName: String,
        controls: PublicControls
    ) -> Entry {
        Entry(
            id: currentRecipeID,
            currentRecipeID: currentRecipeID,
            canonicalPublicName: canonicalPublicName,
            currentFilmBase: currentFilmBase,
            settingsSource: .priorPrivateRepositoryPresetSnapshot,
            priorPresetOrdinal: priorPresetOrdinal,
            priorPresetID: priorPresetID,
            priorPresetName: priorPresetName,
            publicControls: controls,
            note: "Public control values are retained at the prior model's discrete scales. The current FilmRecipe remains an independent normalized approximation."
        )
    }

    private static func currentBaseline(
        currentRecipeID: String,
        canonicalPublicName: String,
        currentFilmBase: FilmRecipe.FilmBase,
        note: String
    ) -> Entry {
        Entry(
            id: currentRecipeID,
            currentRecipeID: currentRecipeID,
            canonicalPublicName: canonicalPublicName,
            currentFilmBase: currentFilmBase,
            settingsSource: .currentAppPublicBaseline,
            note: note
        )
    }
}
