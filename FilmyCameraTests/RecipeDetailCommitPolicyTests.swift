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
}
