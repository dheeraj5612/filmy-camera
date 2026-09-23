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

    func testExposureDragAxisRejectsDiagonalAndSmallMovement() {
        XCTAssertEqual(CameraPreviewGesturePolicy.dragAxis(translation: CGSize(width: 3, height: -30)), .exposure)
        XCTAssertEqual(CameraPreviewGesturePolicy.dragAxis(translation: CGSize(width: -30, height: 3)), .look)
        XCTAssertNil(CameraPreviewGesturePolicy.dragAxis(translation: CGSize(width: 20, height: 20)))
        XCTAssertNil(CameraPreviewGesturePolicy.dragAxis(translation: CGSize(width: 0, height: 8)))
        XCTAssertNil(CameraPreviewGesturePolicy.dragAxis(translation: CGSize(width: CGFloat.infinity, height: 20)))
    }

    func testVerticalDragWaitsForTapFocusBeforeClaimingExposureAxis() {
        XCTAssertNil(CameraPreviewGesturePolicy.eligibleDragAxis(
            translation: CGSize(width: 3, height: -30),
            hasFocusPoint: false,
            canAdjustExposure: true
        ))
        XCTAssertNil(CameraPreviewGesturePolicy.eligibleDragAxis(
            translation: CGSize(width: 3, height: -30),
            hasFocusPoint: true,
            canAdjustExposure: false
        ))
        XCTAssertEqual(CameraPreviewGesturePolicy.eligibleDragAxis(
            translation: CGSize(width: 3, height: -30),
            hasFocusPoint: true,
            canAdjustExposure: true
        ), .exposure)
    }

    func testExposureDragUsesStartingBiasAndScalesForViewport() throws {
        XCTAssertEqual(try XCTUnwrap(CameraPreviewGesturePolicy.exposureBias(start: 0.3,
            translation: CGSize(width: 0, height: -100), viewportHeight: 400)), 1.3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(CameraPreviewGesturePolicy.exposureBias(start: 0.3,
            translation: CGSize(width: 0, height: 200), viewportHeight: 800)), -0.7, accuracy: 0.001)
        XCTAssertNil(CameraPreviewGesturePolicy.exposureBias(start: .nan,
            translation: .zero, viewportHeight: 400))
        XCTAssertNil(CameraPreviewGesturePolicy.exposureBias(start: 0,
            translation: CGSize(width: 0, height: CGFloat.infinity), viewportHeight: 400))
        XCTAssertNil(CameraPreviewGesturePolicy.exposureBias(start: 0,
            translation: .zero, viewportHeight: 0))
    }

    private func direction(x: CGFloat, y: CGFloat) -> CameraLookDirection? {
        CameraPreviewGesturePolicy.lookDirection(translation: CGSize(width: x, height: y), viewportWidth: 390,
                                                interactionEnabled: true, includesPinch: false)
    }
}

/// Kept in an existing test-target source so Xcode and XcodeGen builds both
/// discover these regressions without an unregistered source-file reference.
final class FilmyControlInteractionTests: XCTestCase {
    func testReducedMotionNeverTransformsAPressedControl() {
        for requested: CGFloat in [0.88, 0.94, 0.97, 0.98, 1] {
            XCTAssertEqual(FilmyInteractionPolicy.pressScale(
                isPressed: true, isEnabled: true, reduceMotion: true, requestedScale: requested), 1)
        }
    }

    func testDisabledAndRestingControlsKeepTheirOriginalGeometry() {
        for pressed in [false, true] {
            XCTAssertEqual(FilmyInteractionPolicy.pressScale(
                isPressed: pressed, isEnabled: false, reduceMotion: false, requestedScale: 0.94), 1)
        }
        XCTAssertEqual(FilmyInteractionPolicy.pressScale(
            isPressed: false, isEnabled: true, reduceMotion: false, requestedScale: 0.94), 1)
    }

    func testEnabledPressUsesTheRequestedFeedback() {
        for requested: CGFloat in [0.94, 0.97, 0.98, 1] {
            XCTAssertEqual(FilmyInteractionPolicy.pressScale(
                isPressed: true, isEnabled: true, reduceMotion: false, requestedScale: requested), requested)
        }
    }

    func testInvalidPressScalesCannotExpandOrCollapseTheControl() {
        for requested: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertEqual(FilmyInteractionPolicy.pressScale(
                isPressed: true, isEnabled: true, reduceMotion: false, requestedScale: requested), 1)
        }
        XCTAssertEqual(FilmyInteractionPolicy.pressScale(
            isPressed: true, isEnabled: true, reduceMotion: false, requestedScale: -2), 0.85)
        XCTAssertEqual(FilmyInteractionPolicy.pressScale(
            isPressed: true, isEnabled: true, reduceMotion: false, requestedScale: 2), 1)
    }

    func testZoomPresetsRespectStandardCameraRanges() {
        XCTAssertEqual(FilmyInteractionPolicy.zoomPresets(minZoom: 0.5, maxZoom: 5), [0.5, 1, 2, 3, 5])
        XCTAssertEqual(FilmyInteractionPolicy.zoomPresets(minZoom: 1, maxZoom: 3), [1, 2, 3])
        XCTAssertEqual(FilmyInteractionPolicy.zoomPresets(minZoom: 2, maxZoom: 2), [2])
    }

    func testNarrowZoomRangeNeverOffersAnOutOfRangeOneTimesPreset() {
        XCTAssertEqual(FilmyInteractionPolicy.zoomPresets(minZoom: 1.2, maxZoom: 1.8), [1.2])
        XCTAssertEqual(FilmyInteractionPolicy.zoomPresets(minZoom: 6, maxZoom: 8), [6])
    }

    func testInvalidZoomRangesHaveADeterministicFallback() {
        let ranges: [(CGFloat, CGFloat)] = [(0, 5), (-1, 3), (3, 1), (.nan, 3), (1, .infinity), (1, .nan)]
        for (minimum, maximum) in ranges {
            XCTAssertEqual(FilmyInteractionPolicy.zoomPresets(minZoom: minimum, maxZoom: maximum), [1])
        }
    }

    func testEveryOfferedPresetIsInsideItsValidHardwareRange() {
        for minimum in stride(from: 0.25, through: 8.0, by: 0.25) {
            for span in [0.0, 0.1, 0.5, 1.5, 5.0] {
                let lower = CGFloat(minimum)
                let upper = CGFloat(minimum + span)
                let presets = FilmyInteractionPolicy.zoomPresets(minZoom: lower, maxZoom: upper)
                XCTAssertFalse(presets.isEmpty)
                XCTAssertEqual(presets, presets.sorted())
                XCTAssertEqual(Set(presets).count, presets.count)
                for preset in presets {
                    XCTAssertGreaterThanOrEqual(preset, lower)
                    XCTAssertLessThanOrEqual(preset, upper)
                }
            }
        }
    }
}
