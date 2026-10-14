import XCTest
@testable import FilmyCamera

final class RecipeDetailCommitPolicyTests: XCTestCase {
    func testUnchangedDraftDoesNotCommit() {
        let recipe = FilmRecipe.builtIns[0]

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: recipe,
                current: recipe,
                original: recipe
            ),
            .none
        )
    }

    func testReturningCustomizedRecipeToOriginalRequestsReset() {
        let original = FilmRecipe.builtIns[1]
        var current = original
        current.exposure = 1
        current.markUserModified(parentRecipeID: original.id)

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: original,
                current: current,
                original: original
            ),
            .reset
        )
    }

    func testEditedDraftRequestsUpdate() {
        let original = FilmRecipe.builtIns[2]
        var draft = original
        draft.contrast = 1.35

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: draft,
                current: original,
                original: original
            ),
            .update(draft)
        )
    }

    func testEditingCustomizedDraftRequestsUpdatedCustomization() {
        let original = FilmRecipe.builtIns[2]
        var current = original
        current.exposure = 0.5
        current.markUserModified(parentRecipeID: original.id)
        var draft = current
        draft.contrast = 1.3

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: draft,
                current: current,
                original: original
            ),
            .update(draft)
        )
    }

    func testEditingAfterResetPreviewRequestsUpdateInsteadOfReset() {
        let original = FilmRecipe.builtIns[3]
        var current = original
        current.exposure = 0.7
        current.markUserModified(parentRecipeID: original.id)
        var draft = original
        draft.saturation = 1.3

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: draft,
                current: current,
                original: original
            ),
            .update(draft)
        )
    }

    func testLookCharacterMirrorsControlSummaryAndLeavesRecipeUnchanged() throws {
        let classic = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "classic-chrome" })
        let compact = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let copy = classic

        let line = LookCharacter.line(for: classic)
        XCTAssertEqual(line, LookCharacter.line(for: classic))
        for pair in classic.controlSummary {
            XCTAssertTrue(line.contains(pair.1), "\(pair.1) missing from \(line)")
        }
        XCTAssertTrue(LookCharacter.line(for: compact).contains("Subtle warmth"))

        let mono = try XCTUnwrap(FilmRecipe.builtIns.first { $0.filmBase.supportsMonochromaticColorAxes })
        XCTAssertTrue(LookCharacter.line(for: mono).contains("Color: Black and white"))
        let colorValue = LookCharacter.pairs(for: mono).first { $0.0 == "Color" }?.1
        XCTAssertEqual(colorValue, "Black and white")

        XCTAssertEqual(classic, copy)
    }
}
