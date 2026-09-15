import Foundation

/// Factual camera settings and their source are retained separately from Filmy's
/// display-referred approximation. A settings trace is not a camera calibration.
public struct CameraRecipeSource: Codable, Hashable, Sendable {
    public enum Publisher: String, Codable, CaseIterable, Sendable {
        case fujiXWeekly, filmRecipes, fujifilm

        public var title: String {
            switch self {
            case .fujiXWeekly: return "Fuji X Weekly"
            case .filmRecipes: return "Film Recipes"
            case .fujifilm: return "Fujifilm documentation"
            }
        }

        var references: [FilmRecipe.PublicReference] {
            switch self {
            case .fujiXWeekly: return FilmRecipe.communityRecipeReferences
            case .filmRecipes: return FilmRecipe.fujifilmPublicReferences + [.filmRecipesLibrary]
            case .fujifilm: return FilmRecipe.fujifilmPublicReferences
            }
        }
    }

    public let publisher: Publisher
    public let originalName: String
    public let url: String
    /// Source index scope, not a claim that the phone reproduces that sensor.
    public let cameraScope: String
    public let retrievedOn: String
    public let sourceSHA256: String
    public let settings: [String: String]
    /// Only original implementation notes, never copied article prose.
    public let limitations: [String]
    public let mappingVersion: Int

    public var sourceURL: URL? {
        guard let value = URL(string: url), value.scheme == "https",
              value.user == nil, value.password == nil, value.port == nil else { return nil }
        let allowedHosts: Set<String>
        switch publisher {
        case .fujiXWeekly: allowedHosts = ["fujixweekly.com"]
        case .filmRecipes: allowedHosts = ["film.recipes"]
        case .fujifilm: allowedHosts = ["fujifilm-dsc.com", "www.fujifilm-x.com"]
        }
        return allowedHosts.contains(value.host?.lowercased() ?? "") ? value : nil
    }

    var isValid: Bool {
        sourceURL != nil && !originalName.isEmpty && originalName.utf8.count <= 240
            && !cameraScope.isEmpty && cameraScope.utf8.count <= 240
            && retrievedOn.count == 10 && mappingVersion == CameraRecipeSettings.mappingVersion
            && sourceSHA256.count == 64 && sourceSHA256.allSatisfy { $0.isHexDigit }
            && !settings.isEmpty && settings.count <= 40
            && settings.allSatisfy { !$0.key.isEmpty && $0.key.utf8.count <= 100 && $0.value.utf8.count <= 600 }
            && limitations.count <= 16 && limitations.allSatisfy { $0.utf8.count <= 600 }
    }
}

/// Camera-menu units, not renderer units. All scalar mappings below are original
/// estimates on an already processed phone image. ISO, exposure advice, capture
/// DR headroom, and sensor generation are deliberately not fabricated in software.
struct CameraRecipeSettings: Codable, Hashable, Sendable {
    static let mappingVersion = 1
    let filmBase: FilmRecipe.FilmBase
    let dynamicRange: FilmRecipe.DynamicRange
    let highlight: Double
    let shadow: Double
    let color: Double
    let whiteBalanceMode: FilmRecipe.WhiteBalanceMode
    let kelvin: Double
    let redShift: Double
    let blueShift: Double
    let colorChrome: FilmRecipe.ColorChromeLevel
    let fxBlue: FilmRecipe.FXBlueLevel
    let sharpness: Double
    let noiseReduction: Double
    let clarity: Double
    let grain: FilmRecipe.GrainEffectLevel
    let grainSize: FilmRecipe.GrainSizeLevel
    let monochromaticWarmCool: Double
    let monochromaticGreenMagenta: Double

    var isValid: Bool {
        let bounded: [(Double, ClosedRange<Double>)] = [
            (highlight, -2...4), (shadow, -2...4), (color, -4...4),
            (kelvin, 2500...10000), (redShift, -9...9), (blueShift, -9...9),
            (sharpness, -4...4), (noiseReduction, -4...4), (clarity, -5...5),
            (monochromaticWarmCool, -18...18), (monochromaticGreenMagenta, -18...18)
        ]
        return filmBase != .standard && filmBase != .compactDigital
            && bounded.allSatisfy { $0.0.isFinite && $0.1.contains($0.0) }
            && (filmBase.monochromeFilter == nil || color == 0)
    }

    func recipe(id: String, name: String, source: CameraRecipeSource) -> FilmRecipe {
        let mono = filmBase.monochromeFilter != nil || filmBase == .sepia
        return FilmRecipe(
            id: id, name: name, subtitle: "\(source.publisher.title) / \(source.cameraScope)",
            filmBase: filmBase,
            // Metering recommendations are displayed in the source sheet, not
            // applied again as exposure to an already exposed phone frame.
            exposure: 0,
            tone: .init(highlight: highlight / 4, shadow: shadow / 4),
            saturation: mono ? 0 : 1 + color * 0.07,
            contrast: 1, dynamicRange: dynamicRange, dRangePriority: .off,
            whiteBalance: .init(
                temperature: (redShift - blueShift) * 0.018,
                tint: (redShift + blueShift) * 0.008,
                mode: whiteBalanceMode, kelvin: kelvin
            ),
            monochromaticColor: .init(
                warmCool: monochromaticWarmCool / 18,
                // Camera +MG is green; Filmy's existing +axis is magenta.
                // Preserve the renderer/editor contract and invert only at import.
                greenMagenta: -monochromaticGreenMagenta / 18
            ),
            colorChrome: colorChrome.scalarValue,
            // The base transform already owns its blue response. Do not add
            // a second undocumented blue treatment to sourced camera settings.
            blueResponse: 0, fxBlue: fxBlue.scalarValue,
            sharpness: sharpness * 0.04, noiseReduction: (noiseReduction + 4) * 0.01,
            clarity: clarity * 0.04, grain: grain.scalarValue, grainSize: grainSize.scalarValue,
            vignette: 0, halation: 0, palette: .init(saturation: mono ? 0 : 1),
            provenance: .init(
                source: source.publisher == .fujifilm ? .publicOfficialDocumentation : .publicCommunityRecipe,
                implementation: .originalParametricApproximation,
                calibration: .notCalibratedToFujifilmHardware,
                references: source.publisher.references, cameraSource: source
            )
        )
    }
}

enum RecipeCatalog {
    struct Record: Codable, Hashable, Sendable, Identifiable {
        let id: String
        let name: String
        let source: CameraRecipeSource
        let controls: CameraRecipeSettings

        var isValid: Bool {
            id.hasPrefix("source-") && id.utf8.count <= 128
                && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                && !name.isEmpty && name.utf8.count <= 240 && source.isValid && controls.isValid
        }

        var recipe: FilmRecipe { controls.recipe(id: id, name: name, source: source) }
    }

    struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let records: [Record]
    }

    struct LoadResult: Sendable {
        let records: [Record]
        let issues: [String]
    }

    static let maximumRecords = 4096
    static let maximumBytes = 8_388_608

    /// Resource damage never takes the camera or existing saved edits offline.
    /// Tests fail on any load issue; the management UI reports degraded loading.
    static func decode(_ data: Data) -> LoadResult {
        guard data.count <= maximumBytes else { return .init(records: [], issues: ["Catalog exceeds its byte limit."]) }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.schemaVersion == 1,
              envelope.records.count <= maximumRecords else {
            return .init(records: [], issues: ["Catalog format is not supported."])
        }
        var seen = Set<String>()
        var accepted: [Record] = []
        var issues: [String] = []
        for record in envelope.records {
            guard record.isValid, seen.insert(record.id).inserted else {
                issues.append("A duplicate or invalid recipe was skipped: \(record.id.prefix(128)).")
                continue
            }
            accepted.append(record)
        }
        return .init(records: accepted, issues: issues)
    }

    private static let loaded: LoadResult = {
        guard let url = Bundle.main.url(forResource: "RecipeCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .init(records: [], issues: ["The extended recipe catalog could not be loaded. Original looks are still available."])
        }
        return decode(data)
    }()

    static let records = loaded.records
    static let loadIssues = loaded.issues
    static let sourcedRecipes = records.map(\.recipe)
    static let sourcesByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.source) })

    /// Clean starting points for all 20 documented modes, including MONOCHROME
    /// color filters that were missing before this catalog. These are not extra
    /// Internet recipes and are reported separately from sourced adaptations.
    static let cameraBaselines: [FilmRecipe] = FilmRecipe.FilmBase.allCases.compactMap { base in
        guard base != .standard && base != .compactDigital else { return nil }
        let mono = base.monochromeFilter != nil || base == .sepia
        let suffix: String
        switch base.monochromeFilter {
        case .yellow: suffix = " + Ye"
        case .red: suffix = " + R"
        case .green: suffix = " + G"
        default: suffix = ""
        }
        return FilmRecipe(
            id: "camera-\(base.rawValue)", name: "\(base.officialName)\(suffix) / Camera Base",
            subtitle: "Neutral controls / independent camera-mode approximation", filmBase: base,
            saturation: mono ? 0 : 1, dynamicRange: .dr100,
            noiseReduction: 0, grain: 0, grainSize: FilmRecipe.GrainSizeLevel.small.scalarValue,
            vignette: 0, halation: 0, palette: .init(saturation: mono ? 0 : 1)
        )
    }

    /// Stable, disjoint ownership means pack switches never fight each other.
    /// Source and sensor metadata remain searchable across all packs.
    static func packID(for recipe: FilmRecipe) -> String {
        if recipe.id.hasPrefix("camera-") { return "camera-bases" }
        if let source = recipe.provenance.cameraSource {
            return "\(source.publisher.rawValue)-\(family(for: recipe.filmBase))"
        }
        if let collection = recipe.creativeCollection { return "filmy-\(collection.rawValue)" }
        return "filmy-essentials"
    }

    static func family(for base: FilmRecipe.FilmBase) -> String {
        if base.monochromeFilter != nil || base == .sepia { return "monochrome" }
        switch base {
        case .classicChrome: return "chrome"
        case .eterna, .eternaBleachBypass: return "cinema"
        case .classicNegative, .nostalgicNegative, .realaAce, .proNegative, .proNegStandard: return "negative"
        default: return "slide"
        }
    }

    static let packs: [RecipePack] = makePacks(recipes: FilmRecipe.builtIns)
    static let packsByID = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0) })
    static let packByRecipeID: [String: RecipePack] = Dictionary(
        uniqueKeysWithValues: packs.flatMap { pack in pack.recipeIDs.map { ($0, pack) } }
    )

    static func makePacks(recipes: [FilmRecipe]) -> [RecipePack] {
        let groups = Dictionary(grouping: recipes, by: packID(for:))
        return groups.map { id, members in
            let original = id.hasPrefix("filmy-")
            let title: String
            let subtitle: String
            let order: Int
            if id == "filmy-essentials" {
                title = "Filmy Essentials"; subtitle = "Your original camera and community-inspired looks"; order = 0
            } else if original {
                title = "Filmy \(members[0].creativeCollection?.title ?? "Originals")"
                subtitle = "Original creative treatments, not camera settings"; order = 1
            } else if id == "camera-bases" {
                title = "Camera Foundations"; subtitle = "All 20 modes with neutral controls"; order = 2
            } else {
                let publisher = members[0].provenance.cameraSource?.publisher.title ?? "Community"
                title = "\(publisher) / \(family(for: members[0].filmBase).capitalized)"
                subtitle = "Source-linked camera settings, independently rendered"; order = 3
            }
            return RecipePack(id: id, title: title, subtitle: subtitle, recipeIDs: members.map(\.id),
                              enabledByDefault: original, sortOrder: order)
        }.sorted { left, right in
            left.sortOrder == right.sortOrder ? left.title.localizedStandardCompare(right.title) == .orderedAscending
                : left.sortOrder < right.sortOrder
        }
    }

    static func searchText(for recipe: FilmRecipe) -> String {
        let source = recipe.provenance.cameraSource
        return [recipe.name, recipe.subtitle, recipe.filmBase.officialName, recipe.filmBase.displayName,
                recipe.creativeCollection?.title ?? "", source?.originalName ?? "",
                source?.publisher.title ?? "", source?.cameraScope ?? "", source?.url ?? "",
                packByRecipeID[recipe.id]?.title ?? ""].joined(separator: " ")
    }
}

struct RecipePack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let recipeIDs: [String]
    let enabledByDefault: Bool
    let sortOrder: Int
}
