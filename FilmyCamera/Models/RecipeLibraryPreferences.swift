import Foundation

/// Quick-menu membership only. This value never mutates the selected look,
/// recipe controls, favorites, or review choices. No 300/500-item truncation.
struct RecipeLibraryPreferences: Codable, Equatable, Sendable {
    static let storageKey = "recipeLibraryPreferences.v1"
    static let maximumBytes = 1_048_576
    private(set) var schemaVersion = 1
    private(set) var packOverrides: [String: Bool] = [:]
    private(set) var recipeOverrides: [String: Bool] = [:]

    enum PackState: Equatable {
        case off, mixed, on
    }

    static func decode(_ data: Data?) -> RecipeLibraryPreferences {
        guard let data, data.count <= maximumBytes,
              let decoded = try? JSONDecoder().decode(Self.self, from: data), decoded.schemaVersion == 1,
              decoded.packOverrides.count <= 512, decoded.recipeOverrides.count <= RecipeCatalog.maximumRecords,
              decoded.packOverrides.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
              decoded.recipeOverrides.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { return .init() }
        // Keep unknown IDs: an older build must not erase preferences for a
        // temporarily absent/newer pack. Only known catalog IDs can be shown.
        return decoded
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    func isEnabled(_ recipeID: String, in pack: RecipePack) -> Bool {
        recipeOverrides[recipeID] ?? packOverrides[pack.id] ?? pack.enabledByDefault
    }

    func isEnabled(_ recipeID: String) -> Bool {
        guard let pack = RecipeCatalog.packByRecipeID[recipeID] else { return false }
        return isEnabled(recipeID, in: pack)
    }

    func enabledCount(in pack: RecipePack) -> Int {
        pack.recipeIDs.reduce(0) { $0 + (isEnabled($1, in: pack) ? 1 : 0) }
    }

    func state(of pack: RecipePack) -> PackState {
        let count = enabledCount(in: pack)
        if count == 0 { return .off }
        return count == pack.recipeIDs.count ? .on : .mixed
    }

    mutating func setRecipe(_ recipeID: String, enabled: Bool, in pack: RecipePack) {
        guard pack.recipeIDs.contains(recipeID) else { return }
        let inherited = packOverrides[pack.id] ?? pack.enabledByDefault
        // Store only deviations. A single recipe can be enabled without
        // installing an entire pack, or hidden inside an otherwise active pack.
        recipeOverrides[recipeID] = enabled == inherited ? nil : enabled
    }

    mutating func setRecipe(_ recipeID: String, enabled: Bool) {
        guard let pack = RecipeCatalog.packByRecipeID[recipeID] else { return }
        setRecipe(recipeID, enabled: enabled, in: pack)
    }

    mutating func setPack(_ pack: RecipePack, enabled: Bool) {
        packOverrides[pack.id] = enabled
        // An explicit whole-pack action wins over individual exceptions. This
        // makes "Disable pack" actually hide every member, including favorites.
        for id in pack.recipeIDs { recipeOverrides.removeValue(forKey: id) }
    }

    mutating func setAll(_ packs: [RecipePack], enabled: Bool) {
        for pack in packs { setPack(pack, enabled: enabled) }
    }

    mutating func restoreDefaults() { self = .init() }
}
