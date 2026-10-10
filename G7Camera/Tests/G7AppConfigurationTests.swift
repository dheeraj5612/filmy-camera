import XCTest
@testable import G7Camera

final class G7AppConfigurationTests: XCTestCase {
    func testG7IdentityAndLockedRecipe() {
        XCTAssertTrue(AppConfiguration.isG7X)
        XCTAssertEqual(AppConfiguration.displayName, "G7X Camera")
        XCTAssertEqual(AppConfiguration.wordmark, "g7x")
        XCTAssertEqual(AppConfiguration.defaultRecipeID, "g7x-compact")
        XCTAssertTrue(AppConfiguration.isRecipeAllowed("g7x-compact"))
        XCTAssertFalse(AppConfiguration.isRecipeAllowed("filmy-natural"))
    }

    @MainActor
    func testModelExposesOnlyTheG7Recipe() {
        let defaults = UserDefaults(suiteName: "G7CameraTests.recipe-lock")!
        defaults.removePersistentDomain(forName: "G7CameraTests.recipe-lock")
        let model = CameraViewModel(defaults: defaults)

        XCTAssertEqual(model.selectedRecipeID, "g7x-compact")
        XCTAssertEqual(model.recipes.map(\.id), ["g7x-compact"])
        XCTAssertEqual(model.recipe(for: "filmy-natural").id, "g7x-compact")
    }
}
