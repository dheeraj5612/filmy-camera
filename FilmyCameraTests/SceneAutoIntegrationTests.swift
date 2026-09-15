import XCTest
@testable import FilmyCamera

@MainActor
final class SceneAutoIntegrationTests: XCTestCase {
    func testCameraConstructionDoesNotEnableSceneAutoOrAlterManualControls() {
        let camera = CameraService()
        XCTAssertEqual(camera.sceneAuto, SceneAutoState())
        XCTAssertEqual(camera.manualControls, .unavailable)
        XCTAssertEqual(camera.exposureBias, 0)
    }

    func testNeutralDevelopmentIsExactIdentityForEveryBuiltIn() {
        for recipe in FilmRecipe.builtIns {
            XCTAssertEqual(SceneAutoDevelopment().applying(to: recipe), recipe, recipe.id)
        }
    }

    func testDevelopmentChangesOnlyTheFourOwnedFields() throws {
        let original = try XCTUnwrap(FilmRecipe.builtIns.first)
        let adjustment = SceneAutoDevelopment(highlights: -0.16, shadows: -0.12, noiseReduction: 0.16, sharpness: -0.1)
        let developed = adjustment.applying(to: original)
        var reversed = developed
        reversed.tone.highlight = original.tone.highlight
        reversed.tone.shadow = original.tone.shadow
        reversed.noiseReduction = original.noiseReduction
        reversed.sharpness = original.sharpness
        XCTAssertEqual(reversed, original)
        XCTAssertEqual(developed.id, original.id)
        XCTAssertEqual(developed.filmBase, original.filmBase)
        XCTAssertEqual(developed.grain, original.grain)
        XCTAssertEqual(developed.whiteBalance, original.whiteBalance)
    }

    func testDevelopmentClampsWithoutMutatingSavedRecipe() throws {
        var recipe = try XCTUnwrap(FilmRecipe.builtIns.first)
        recipe.tone.highlight = -0.95
        recipe.tone.shadow = -0.95
        recipe.noiseReduction = 0.95
        recipe.sharpness = -0.95
        let baseline = recipe
        let adjustment = SceneAutoDevelopment(highlights: -0.16, shadows: -0.12, noiseReduction: 0.16, sharpness: -0.1)
        let developed = adjustment.applying(to: recipe)
        XCTAssertEqual(developed.tone.highlight, -1)
        XCTAssertEqual(developed.tone.shadow, -1)
        XCTAssertEqual(developed.noiseReduction, 1)
        XCTAssertEqual(developed.sharpness, -1)
        XCTAssertEqual(recipe, baseline)
    }

    func testShutterSnapshotIsIndependentOfLaterAutoDevelopment() throws {
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first)
        var development = SceneAutoDevelopment(highlights: -0.1)
        let captured = development.applying(to: recipe)
        let expected = captured
        development.highlights = 0
        development.shadows = -0.12
        _ = development.applying(to: recipe)
        XCTAssertEqual(captured, expected)
        XCTAssertEqual(captured.tone.highlight, max(recipe.tone.highlight - 0.1, -1))
    }

    func testAutoFacePointUsesExistingPortraitAndFrontMirroringTransform() {
        let previewPoint = CGPoint(x: 0.2, y: 0.3)
        let rear = CameraService.captureDevicePoint(fromRotatedPreviewPoint: previewPoint, rotationAngle: 90, mirrored: false)
        let front = CameraService.captureDevicePoint(fromRotatedPreviewPoint: previewPoint, rotationAngle: 90, mirrored: true)
        XCTAssertEqual(rear.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(rear.y, 0.8, accuracy: 0.000001)
        XCTAssertEqual(front.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(front.y, 0.2, accuracy: 0.000001)
    }
}
