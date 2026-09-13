import XCTest
@testable import FilmyCamera

final class CameraPreviewGesturePolicyTests: XCTestCase {
    func testHorizontalSwipesMoveThroughLookOrder() {
        XCTAssertEqual(direction(x: -120, y: 5), .next)
        XCTAssertEqual(direction(x: 120, y: -5), .previous)
    }

    func testFocusTapsAndVerticalOrDiagonalDragsDoNotChangeLook() {
        XCTAssertNil(direction(x: 2, y: 0))
        XCTAssertNil(direction(x: 50, y: 0))
        XCTAssertNil(direction(x: 100, y: 100))
        XCTAssertNil(direction(x: 10, y: 200))
    }

    func testBusyOrPinchingPreviewNeverSelectsLook() {
        for enabled in [false, true] {
            for pinching in [false, true] where !enabled || pinching {
                XCTAssertNil(CameraPreviewGesturePolicy.lookDirection(
                    translation: CGSize(width: -200, height: 0), viewportWidth: 390,
                    interactionEnabled: enabled, includesPinch: pinching))
            }
        }
    }

    func testInvalidGeometryCannotSelectLook() {
        for translation in [CGSize(width: CGFloat.nan, height: 0), CGSize(width: 100, height: CGFloat.infinity)] {
            XCTAssertNil(CameraPreviewGesturePolicy.lookDirection(
                translation: translation, viewportWidth: 390, interactionEnabled: true, includesPinch: false))
        }
        XCTAssertNil(CameraPreviewGesturePolicy.lookDirection(
            translation: CGSize(width: -200, height: 0), viewportWidth: 0,
            interactionEnabled: true, includesPinch: false))
    }

    func testLookNavigationStopsAtBoundariesAndRejectsStaleSelection() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(CameraPreviewGesturePolicy.targetIdentifier(in: ids, selectedIdentifier: "b", direction: .next), "c")
        XCTAssertEqual(CameraPreviewGesturePolicy.targetIdentifier(in: ids, selectedIdentifier: "b", direction: .previous), "a")
        XCTAssertNil(CameraPreviewGesturePolicy.targetIdentifier(in: ids, selectedIdentifier: "a", direction: .previous))
        XCTAssertNil(CameraPreviewGesturePolicy.targetIdentifier(in: ids, selectedIdentifier: "c", direction: .next))
        XCTAssertNil(CameraPreviewGesturePolicy.targetIdentifier(in: ids, selectedIdentifier: "deleted", direction: .next))
        XCTAssertNil(CameraPreviewGesturePolicy.targetIdentifier(in: [], selectedIdentifier: "a", direction: .next))
    }

    func testRecipeSwipesUseTheSameCompactFirstOrderAsTheLookLibrary() {
        let recipes = FilmRecipe.builtIns
        XCTAssertEqual(CameraPreviewGesturePolicy.targetRecipe(in: recipes, selectedIdentifier: "g7x-compact",
                                                               direction: .next)?.id, "provia-standard")
        XCTAssertEqual(CameraPreviewGesturePolicy.targetRecipe(in: recipes, selectedIdentifier: "provia-standard",
                                                               direction: .previous)?.id, "g7x-compact")
        XCTAssertNil(CameraPreviewGesturePolicy.targetRecipe(in: recipes, selectedIdentifier: "g7x-compact",
                                                             direction: .previous))
        let library = LookLibraryIndex.results(in: recipes, query: "", filter: .all, favorites: [])
        for pair in zip(library, library.dropFirst()) {
            XCTAssertEqual(CameraPreviewGesturePolicy.targetRecipe(in: recipes, selectedIdentifier: pair.0.id,
                                                                   direction: .next)?.id, pair.1.id)
        }
    }

    func testRecipeSwipeKeepsTheEffectiveCustomSettings() throws {
        var recipes = FilmRecipe.builtIns
        let index = try XCTUnwrap(recipes.firstIndex { $0.id == "provia-standard" })
        recipes[index].exposure = 1.25
        let next = try XCTUnwrap(CameraPreviewGesturePolicy.targetRecipe(in: recipes,
                                                                         selectedIdentifier: "g7x-compact",
                                                                         direction: .next))
        XCTAssertEqual(next.exposure, 1.25)
    }

    private func direction(x: CGFloat, y: CGFloat) -> CameraLookDirection? {
        CameraPreviewGesturePolicy.lookDirection(translation: CGSize(width: x, height: y), viewportWidth: 390,
                                                interactionEnabled: true, includesPinch: false)
    }
}
