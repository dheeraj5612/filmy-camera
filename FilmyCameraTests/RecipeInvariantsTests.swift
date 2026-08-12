import Foundation
import XCTest
@testable import FilmyCamera

final class RecipeInvariantsTests: XCTestCase {
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
            XCTAssertTrue((-1.0...1.0).contains(recipe.whiteBalance.temperature), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.whiteBalance.tint), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.colorChrome), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.blueResponse), recipe.id)
            XCTAssertTrue((-1.0...1.0).contains(recipe.clarity), recipe.id)
            XCTAssertTrue((0.0...1.0).contains(recipe.grain), recipe.id)
            XCTAssertTrue((0.1...4.0).contains(recipe.grainSize), recipe.id)
            XCTAssertTrue((0.0...1.0).contains(recipe.vignette), recipe.id)
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
                recipe.whiteBalance.temperature,
                recipe.whiteBalance.tint,
                recipe.colorChrome,
                recipe.blueResponse,
                recipe.clarity,
                recipe.grain,
                recipe.grainSize,
                recipe.vignette,
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
}
