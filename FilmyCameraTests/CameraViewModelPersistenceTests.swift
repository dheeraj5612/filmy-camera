import Foundation
import XCTest
@testable import FilmyCamera

@MainActor
final class CameraViewModelPersistenceTests: XCTestCase {
    func testLaunchWarmupResolvesTheSelectedCustomLook() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var customized = FilmRecipe.builtIns[1]
        customized.colorChrome = 0.8
        customized.whiteBalance.temperature = 0.5
        defaults.set(customized.id, forKey: CameraViewModel.selectedRecipeIDKey)
        defaults.set(try JSONEncoder().encode([customized.id: customized]),
                     forKey: CameraViewModel.recipeOverridesKey)

        let warmed = CameraViewModel.launchRecipe(defaults: defaults)
        let model = CameraViewModel(defaults: defaults)
        XCTAssertEqual(warmed, model.selectedRecipe)
        XCTAssertEqual(warmed.colorChrome, 0.8)
    }

    func testInvalidSelectedRecipeIDIsNormalizedAndRewritten() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "removed-recipe",
            forKey: CameraViewModel.selectedRecipeIDKey
        )

        let viewModel = CameraViewModel(defaults: defaults)
        let fallbackID = CameraViewModel.defaultRecipeID

        XCTAssertEqual(viewModel.selectedRecipeID, fallbackID)
        XCTAssertEqual(
            defaults.string(forKey: CameraViewModel.selectedRecipeIDKey),
            fallbackID
        )

        viewModel.selectedRecipeID = "still-invalid"
        XCTAssertEqual(viewModel.selectedRecipeID, fallbackID)
        XCTAssertEqual(
            defaults.string(forKey: CameraViewModel.selectedRecipeIDKey),
            fallbackID
        )
    }

    func testValidSelectedRecipeIDIsPreserved() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectedID = FilmRecipe.builtIns[3].id
        defaults.set(
            selectedID,
            forKey: CameraViewModel.selectedRecipeIDKey
        )

        let viewModel = CameraViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.selectedRecipeID, selectedID)
        XCTAssertEqual(viewModel.selectedRecipe.id, selectedID)
    }

    func testCorruptOverrideDoesNotDiscardValidCustomRecipes() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var validRecipe = FilmRecipe.builtIns[1]
        validRecipe.exposure = 1.25
        validRecipe.contrast = 1.4

        let validData = try JSONEncoder().encode(validRecipe)
        let validObject = try JSONSerialization.jsonObject(with: validData)
        let mixedObject: [String: Any] = [
            validRecipe.id: validObject,
            "broken-recipe": ["id": 42]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: mixedObject),
            forKey: CameraViewModel.recipeOverridesKey
        )
        defaults.set(
            validRecipe.id,
            forKey: CameraViewModel.selectedRecipeIDKey
        )

        let viewModel = CameraViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.isCustomized(validRecipe))
        XCTAssertEqual(viewModel.selectedRecipe.exposure, 1.25, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedRecipe.contrast, 1.4, accuracy: 0.0001)

        let rewrittenData = try XCTUnwrap(
            defaults.data(forKey: CameraViewModel.recipeOverridesKey)
        )
        let rewritten = try JSONDecoder().decode(
            [String: FilmRecipe].self,
            from: rewrittenData
        )
        XCTAssertEqual(Set(rewritten.keys), [validRecipe.id])
    }

    func testUnknownUpdatesAreIgnoredAndKnownUpdatesAreSanitized() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = CameraViewModel(defaults: defaults)
        let initialID = viewModel.selectedRecipeID
        let unknownRecipe = FilmRecipe(
            id: "unknown-recipe",
            name: "Unknown",
            subtitle: "Not part of the current catalog"
        )

        viewModel.select(recipe: unknownRecipe)
        viewModel.update(recipe: unknownRecipe)

        XCTAssertEqual(viewModel.selectedRecipeID, initialID)
        XCTAssertFalse(viewModel.isCustomized(unknownRecipe))

        let parent = FilmRecipe.builtIns[2]
        var damagedEdit = parent
        damagedEdit.exposure = .infinity
        damagedEdit.saturation = 99
        viewModel.update(recipe: damagedEdit)
        viewModel.select(recipe: parent)

        XCTAssertEqual(
            viewModel.selectedRecipe.exposure,
            parent.exposure,
            accuracy: 0.0001
        )
        XCTAssertEqual(viewModel.selectedRecipe.saturation, 2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedRecipe.id, parent.id)
    }

    func testRecipeLookupReturnsPersistedOverrideForUnselectedRecipe() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = CameraViewModel(defaults: defaults)
        let parent = FilmRecipe.builtIns[4]
        var customized = parent
        customized.exposure = 0.75

        viewModel.update(recipe: customized)

        XCTAssertTrue(viewModel.isCustomized(parent))
        XCTAssertEqual(
            viewModel.recipe(for: parent.id).exposure,
            0.75,
            accuracy: 0.0001
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CameraViewModelPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
