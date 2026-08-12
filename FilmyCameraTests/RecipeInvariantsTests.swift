import Foundation
import XCTest
@testable import FilmyCamera

final class RecipeInvariantsTests: XCTestCase {
    private let selectedRecipeKey = "selectedRecipeID"
    private let recipeOverridesKey = "recipeOverrides"
    private var hadSelectedRecipeValue = false
    private var previousSelectedRecipeID: String?
    private var hadRecipeOverridesValue = false
    private var previousRecipeOverrides: Data?

    override func setUp() {
        super.setUp()

        let defaults = UserDefaults.standard
        hadSelectedRecipeValue = defaults.object(forKey: selectedRecipeKey) != nil
        previousSelectedRecipeID = defaults.string(forKey: selectedRecipeKey)
        hadRecipeOverridesValue = defaults.object(forKey: recipeOverridesKey) != nil
        previousRecipeOverrides = defaults.data(forKey: recipeOverridesKey)
        defaults.removeObject(forKey: selectedRecipeKey)
        defaults.removeObject(forKey: recipeOverridesKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard

        if hadSelectedRecipeValue {
            defaults.set(previousSelectedRecipeID, forKey: selectedRecipeKey)
        } else {
            defaults.removeObject(forKey: selectedRecipeKey)
        }

        if hadRecipeOverridesValue {
            defaults.set(previousRecipeOverrides, forKey: recipeOverridesKey)
        } else {
            defaults.removeObject(forKey: recipeOverridesKey)
        }

        super.tearDown()
    }

    func testBuiltInRecipesHaveUniqueStableIdentityAndDisplayValues() {
        let recipes = FilmRecipe.builtIns

        XCTAssertFalse(recipes.isEmpty)
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count)
        XCTAssertEqual(Set(recipes.map(\.name)).count, recipes.count)

        for recipe in recipes {
            XCTAssertFalse(recipe.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(recipe.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testBuiltInRecipeControlsStayWithinNormalizedEditorBounds() {
        for recipe in FilmRecipe.builtIns {
            XCTAssertTrue((-2.0...2.0).contains(recipe.exposure), recipe.id)
            XCTAssertTrue((-2.0...2.0).contains(recipe.tone.highlight), recipe.id)
            XCTAssertTrue((-2.0...2.0).contains(recipe.tone.shadow), recipe.id)
            XCTAssertTrue((0.0...2.0).contains(recipe.saturation), recipe.id)
            XCTAssertTrue((0.0...2.0).contains(recipe.contrast), recipe.id)
            XCTAssertTrue(FilmRecipe.DynamicRange.allCases.contains(recipe.dynamicRange), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.whiteBalance.temperature), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.whiteBalance.tint), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.colorChrome), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.blueResponse), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.fxBlue), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.sharpness), recipe.id)
            XCTAssertTrue((0.0...1.0).contains(recipe.noiseReduction), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.clarity), recipe.id)
            XCTAssertTrue((0.0...1.0).contains(recipe.grain), recipe.id)
            XCTAssertTrue((0.1...4.0).contains(recipe.grainSize), recipe.id)
            XCTAssertTrue((0.0...1.0).contains(recipe.vignette), recipe.id)
            XCTAssertTrue((0.0...1.0).contains(recipe.halation), recipe.id)
            XCTAssertTrue((0.0...2.0).contains(recipe.palette.saturation), recipe.id)

            let paletteValues = [
                recipe.palette.redBias,
                recipe.palette.greenBias,
                recipe.palette.blueBias,
                recipe.palette.redGreenMix,
                recipe.palette.greenBlueMix,
                recipe.palette.blueRedMix
            ]
            XCTAssertTrue(paletteValues.allSatisfy { (-1.0...1.0).contains($0) }, recipe.id)
        }
    }

    func testBuiltInRecipeControlsAreFinite() {
        for recipe in FilmRecipe.builtIns {
            let values = [
                recipe.exposure,
                recipe.tone.highlight,
                recipe.tone.shadow,
                recipe.saturation,
                recipe.contrast,
                Double(recipe.dynamicRange.rawValue),
                recipe.whiteBalance.temperature,
                recipe.whiteBalance.tint,
                recipe.colorChrome,
                recipe.blueResponse,
                recipe.fxBlue,
                recipe.sharpness,
                recipe.noiseReduction,
                recipe.clarity,
                recipe.grain,
                recipe.grainSize,
                recipe.vignette,
                recipe.halation,
                recipe.palette.redBias,
                recipe.palette.greenBias,
                recipe.palette.blueBias,
                recipe.palette.redGreenMix,
                recipe.palette.greenBlueMix,
                recipe.palette.blueRedMix,
                recipe.palette.saturation
            ]

            XCTAssertTrue(values.allSatisfy(\.isFinite), recipe.id)
        }
    }

    func testRecipeRoundTripsThroughPersistentRepresentation() throws {
        let original = FilmRecipe.builtIns[0]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilmRecipe.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testSelectedRecipePersistsAcrossViewModelInstances() async {
        let expected = FilmRecipe.builtIns[2]
        let model = await CameraViewModel()

        await model.select(recipe: expected)

        let storedID = UserDefaults.standard.string(forKey: selectedRecipeKey)
        let reloadedModel = await CameraViewModel()
        let reloadedID = await reloadedModel.selectedRecipeID
        let reloadedRecipe = await reloadedModel.selectedRecipe

        XCTAssertEqual(storedID, expected.id)
        XCTAssertEqual(reloadedID, expected.id)
        XCTAssertEqual(reloadedRecipe, expected)
    }

    func testCustomizedRecipePersistsAndResetRestoresBuiltIn() async {
        let original = FilmRecipe.builtIns[1]
        var customized = original
        customized.exposure = 1.25
        customized.tone = FilmRecipe.Tone(highlight: -0.45, shadow: 0.60)
        customized.grain = 0.72
        customized.palette.blueBias = 0.18

        let model = await CameraViewModel()
        await model.select(recipe: original)
        await model.update(recipe: customized)

        let reloadedModel = await CameraViewModel()
        let reloadedRecipe = await reloadedModel.selectedRecipe
        let isCustomizedBeforeReset = await reloadedModel.isCustomized(original)

        XCTAssertEqual(reloadedRecipe, customized)
        XCTAssertTrue(isCustomizedBeforeReset)

        await reloadedModel.reset(recipeID: original.id)

        let resetRecipe = await reloadedModel.selectedRecipe
        let isCustomizedAfterReset = await reloadedModel.isCustomized(original)
        XCTAssertEqual(resetRecipe, original)
        XCTAssertFalse(isCustomizedAfterReset)
    }

    func testUnknownPersistedSelectionFallsBackToFirstBuiltInRecipe() async {
        UserDefaults.standard.set("recipe-that-no-longer-exists", forKey: selectedRecipeKey)

        let model = await CameraViewModel()
        let persistedID = await model.selectedRecipeID
        let resolvedRecipe = await model.selectedRecipe

        XCTAssertEqual(persistedID, "recipe-that-no-longer-exists")
        XCTAssertEqual(resolvedRecipe, FilmRecipe.builtIns[0])
    }

    func testCaptureFailureReturnsToIdleWithoutLeavingAReviewFrame() async {
        let model = await CameraViewModel()
        let camera = CameraService()

        // The session is intentionally never started. CameraService must
        // report this as a clean, recoverable capture failure on any device.
        await model.capture(camera: camera)

        for _ in 0..<100 {
            if await model.isCapturing == false { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let isCapturing = await model.isCapturing
        let reviewImage = await model.reviewImage
        let reviewRecipe = await model.reviewRecipe
        let toastMessage = await model.toastMessage

        XCTAssertFalse(isCapturing)
        XCTAssertNil(reviewImage)
        XCTAssertNil(reviewRecipe)
        XCTAssertEqual(toastMessage, "Capture could not be completed. Resume the camera and try again.")
    }
}
