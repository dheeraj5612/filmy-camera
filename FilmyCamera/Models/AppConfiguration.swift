/// Compile-time product configuration shared by the Filmy Camera and G7X
/// targets. Keeping the product decision here prevents a second target from
/// silently growing a second, divergent source tree.
enum AppConfiguration {
    #if G7_APP
    static let isG7X = true
    static let displayName = "G7X Camera"
    static let wordmark = "g7x"
    static let defaultRecipeID = "g7x-compact"
    #else
    static let isG7X = false
    static let displayName = "Filmy Camera"
    static let wordmark = "filmy"
    static let defaultRecipeID = "g7x-compact"
    #endif

    static func isRecipeAllowed(_ id: String) -> Bool {
        #if G7_APP
        return id == defaultRecipeID
        #else
        return true
        #endif
    }
}
