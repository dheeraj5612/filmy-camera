import Foundation
import XCTest
@testable import FilmyCamera

final class ReviewComparisonStateTests: XCTestCase {
    func testStartsWithTheEditedPhotoAndCenteredDivider() {
        let state = ReviewComparisonState()
        XCTAssertEqual(state.mode, .look)
        XCTAssertNil(state.pendingMode)
        XCTAssertEqual(state.originalFraction, 0.5)
    }

    func testSplitWaitsForTheActualOriginalWithoutRelabelingTheLook() {
        var state = ReviewComparisonState()
        XCTAssertTrue(state.select(.split, originalAvailable: false, splitSupported: true))
        XCTAssertEqual(state.mode, .look)
        XCTAssertEqual(state.pendingMode, .split)
        state.originalDidLoad(splitSupported: true)
        XCTAssertEqual(state.mode, .split)
        XCTAssertNil(state.pendingMode)
    }

    func testCachedOriginalNeedsNoAdditionalRender() {
        var state = ReviewComparisonState()
        XCTAssertFalse(state.select(.original, originalAvailable: true, splitSupported: true))
        XCTAssertEqual(state.mode, .original)
        XCTAssertFalse(state.select(.split, originalAvailable: true, splitSupported: true))
        XCTAssertEqual(state.mode, .split)
    }

    func testLateCompletionCannotReopenComparisonAfterARecipeOrFinishChange() {
        var state = ReviewComparisonState()
        state.select(.split, originalAvailable: false, splitSupported: true)
        state.reset()
        state.originalDidLoad(splitSupported: true)
        XCTAssertEqual(state.mode, .look)
        XCTAssertNil(state.pendingMode)
    }

    func testChoosingLookCancelsPendingOriginalIntent() {
        var state = ReviewComparisonState()
        state.select(.original, originalAvailable: false, splitSupported: true)
        XCTAssertFalse(state.select(.look, originalAvailable: false, splitSupported: true))
        state.originalDidLoad(splitSupported: true)
        XCTAssertEqual(state.mode, .look)
    }

    func testFailureClearsIntentAndAllowsRetry() {
        var state = ReviewComparisonState()
        state.select(.split, originalAvailable: false, splitSupported: true)
        state.preparationFailed()
        state.originalDidLoad(splitSupported: true)
        XCTAssertEqual(state.mode, .look)
        XCTAssertNil(state.pendingMode)
        XCTAssertTrue(state.select(.split, originalAvailable: false, splitSupported: true))
    }

    func testUnsupportedSplitNeverRequestsImageWork() {
        var state = ReviewComparisonState()
        XCTAssertFalse(state.select(.split, originalAvailable: false, splitSupported: false))
        XCTAssertEqual(state.mode, .look)
        XCTAssertNil(state.pendingMode)
        // Full-frame A/B remains available for Instant Print.
        XCTAssertTrue(state.select(.original, originalAvailable: false, splitSupported: false))
        state.originalDidLoad(splitSupported: false)
        XCTAssertEqual(state.mode, .original)
    }

    func testLateGeometryMismatchFallsBackToAnHonestFullFrameOriginal() {
        var state = ReviewComparisonState()
        state.select(.split, originalAvailable: false, splitSupported: true)
        state.originalDidLoad(splitSupported: false)
        XCTAssertEqual(state.mode, .original)
    }

    func testDividerClampsAtBothPhotoEdges() {
        var state = ReviewComparisonState()
        state.moveDivider(to: -100)
        XCTAssertEqual(state.originalFraction, 0)
        state.moveDivider(to: 100)
        XCTAssertEqual(state.originalFraction, 1)
        state.moveDivider(to: 0.37)
        XCTAssertEqual(state.originalFraction, 0.37)
    }

    func testNonfiniteGestureSamplesCannotCorruptLayout() {
        var state = ReviewComparisonState()
        state.moveDivider(to: 0.37)
        for invalid in [Double.nan, .infinity, -.infinity] {
            state.moveDivider(to: invalid)
            XCTAssertEqual(state.originalFraction, 0.37)
        }
    }

    func testVoiceOverAdjustmentsMatchDirectManipulationAndStayBounded() {
        var state = ReviewComparisonState()
        state.stepDivider(increasing: true)
        XCTAssertEqual(state.originalFraction, 0.6, accuracy: 0.0001)
        state.stepDivider(increasing: false)
        XCTAssertEqual(state.originalFraction, 0.5, accuracy: 0.0001)
        for _ in 0..<50 { state.stepDivider(increasing: false) }
        XCTAssertEqual(state.originalFraction, 0)
        for _ in 0..<50 { state.stepDivider(increasing: true) }
        XCTAssertEqual(state.originalFraction, 1)
        state.reset()
        XCTAssertEqual(state.originalFraction, 0.5)
    }

    func testMatchingPortraitAndLandscapeFramingSupportSplitAtDifferentResolutions() {
        XCTAssertTrue(ReviewComparisonGeometry.supportsSplit(
            original: CGSize(width: 3024, height: 4032), edited: CGSize(width: 1350, height: 1800), finish: .photo))
        XCTAssertTrue(ReviewComparisonGeometry.supportsSplit(
            original: CGSize(width: 4032, height: 3024), edited: CGSize(width: 1800, height: 1350), finish: .photo))
    }

    func testRoundedPreviewDimensionsDoNotDisableMatchingFraming() {
        XCTAssertTrue(ReviewComparisonGeometry.supportsSplit(
            original: CGSize(width: 1086, height: 1448), edited: CGSize(width: 1350, height: 1801), finish: .photo))
    }

    func testPrintAndMismatchedCropsCannotBeShownAsAlignedWipes() {
        let size = CGSize(width: 1200, height: 1600)
        XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(original: size, edited: size, finish: .instantPrint))
        XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(
            original: size, edited: CGSize(width: 1200, height: 1200), finish: .photo))
        XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(
            original: size, edited: CGSize(width: 1600, height: 1200), finish: .photo))
    }

    func testInvalidImageDimensionsNeverEnableSplit() {
        let valid = CGSize(width: 1200, height: 1600)
        for invalid in [CGSize.zero, CGSize(width: -1, height: 10),
                        CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 10, height: CGFloat.nan)] {
            XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(original: invalid, edited: valid, finish: .photo))
            XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(original: valid, edited: invalid, finish: .photo))
        }
    }

    func testCachedSelectionTransitionMatrixPreservesDivider() {
        let modes: [ReviewComparisonState.Mode] = [.look, .original, .split]
        for initial in modes {
            for requested in modes {
                for splitSupported in [false, true] {
                    var state = ReviewComparisonState()
                    state.select(initial, originalAvailable: true, splitSupported: true)
                    state.moveDivider(to: 0.27)
                    XCTAssertFalse(state.select(requested, originalAvailable: true, splitSupported: splitSupported))
                    XCTAssertEqual(state.mode, requested == .split && !splitSupported ? initial : requested)
                    XCTAssertNil(state.pendingMode)
                    XCTAssertEqual(state.originalFraction, 0.27)
                }
            }
        }
    }

    func testLatestSupportedPendingIntentWinsBeforeOriginalCompletes() {
        for first in [ReviewComparisonState.Mode.original, .split] {
            for last in [ReviewComparisonState.Mode.original, .split] {
                var state = ReviewComparisonState()
                XCTAssertTrue(state.select(first, originalAvailable: false, splitSupported: true))
                XCTAssertTrue(state.select(last, originalAvailable: false, splitSupported: true))
                XCTAssertEqual(state.mode, .look)
                XCTAssertEqual(state.pendingMode, last)
                state.originalDidLoad(splitSupported: true)
                XCTAssertEqual(state.mode, last)
                XCTAssertNil(state.pendingMode)
            }
        }
    }

    func testRejectedSplitIsANoOpEvenWhenAnotherIntentIsPending() {
        for initial in [ReviewComparisonState.Mode.look, .original, .split] {
            var state = ReviewComparisonState()
            state.select(initial, originalAvailable: true, splitSupported: true)
            state.select(.original, originalAvailable: false, splitSupported: true)
            state.moveDivider(to: 0.81)
            let before = state
            for available in [false, true] {
                XCTAssertFalse(state.select(.split, originalAvailable: available, splitSupported: false))
                XCTAssertEqual(state, before)
            }
            state.originalDidLoad(splitSupported: false)
            XCTAssertEqual(state.mode, .original)
        }
    }

    func testCachedChoiceCancelsPendingWorkAndLateCompletionIsIgnored() {
        for pending in [ReviewComparisonState.Mode.original, .split] {
            for cached in [ReviewComparisonState.Mode.look, .original, .split] {
                var state = ReviewComparisonState()
                state.select(pending, originalAvailable: false, splitSupported: true)
                XCTAssertFalse(state.select(cached, originalAvailable: true, splitSupported: true))
                let before = state
                state.originalDidLoad(splitSupported: false)
                XCTAssertEqual(state, before)
                XCTAssertNil(state.pendingMode)
            }
        }
    }

    func testPreparationFailureDoesNotDiscardTheAlreadyDisplayedComparison() {
        for visible in [ReviewComparisonState.Mode.look, .original, .split] {
            var state = ReviewComparisonState()
            state.select(visible, originalAvailable: true, splitSupported: true)
            state.moveDivider(to: 0.18)
            state.select(.original, originalAvailable: false, splitSupported: true)
            state.preparationFailed()
            XCTAssertEqual(state.mode, visible)
            XCTAssertEqual(state.originalFraction, 0.18)
            XCTAssertNil(state.pendingMode)
            let failed = state
            state.preparationFailed()
            state.originalDidLoad(splitSupported: true)
            XCTAssertEqual(state, failed)
        }
    }

    func testDuplicateOriginalCompletionsCannotChangeResolvedMode() {
        for requested in [ReviewComparisonState.Mode.original, .split] {
            for supported in [false, true] {
                var state = ReviewComparisonState()
                state.select(requested, originalAvailable: false, splitSupported: true)
                state.originalDidLoad(splitSupported: supported)
                let completed = state
                for _ in 0..<10 {
                    state.originalDidLoad(splitSupported: !supported)
                    XCTAssertEqual(state, completed)
                }
            }
        }
    }

    func testResetIsIdempotentFromEveryVisibleAndPendingMode() {
        for visible in [ReviewComparisonState.Mode.look, .original, .split] {
            for pending in [ReviewComparisonState.Mode.original, .split] {
                var state = ReviewComparisonState()
                state.select(visible, originalAvailable: true, splitSupported: true)
                state.moveDivider(to: 0.99)
                state.select(pending, originalAvailable: false, splitSupported: true)
                state.reset()
                state.reset()
                state.originalDidLoad(splitSupported: true)
                XCTAssertEqual(state, ReviewComparisonState())
            }
        }
    }

    func testDividerAndPendingLoadAreIndependentStateDimensions() {
        var state = ReviewComparisonState()
        state.select(.split, originalAvailable: false, splitSupported: true)
        for step in 0...100 {
            state.moveDivider(to: Double(step) / 100)
            XCTAssertEqual(state.mode, .look)
            XCTAssertEqual(state.pendingMode, .split)
        }
        state.originalDidLoad(splitSupported: true)
        XCTAssertEqual(state.originalFraction, 1)
        state.select(.look, originalAvailable: true, splitSupported: true)
        XCTAssertEqual(state.originalFraction, 1, "Toggling comparison must not reset the user's divider")
    }

    func testDividerIsMonotonicBoundedAndExactWithinItsDomain() {
        var state = ReviewComparisonState()
        var previous = 0.0
        for sample in -1000...2000 {
            let fraction = Double(sample) / 1000
            state.moveDivider(to: fraction)
            XCTAssertGreaterThanOrEqual(state.originalFraction, previous, "sample=\(sample)")
            XCTAssertTrue((0...1).contains(state.originalFraction))
            if (0...1).contains(fraction) { XCTAssertEqual(state.originalFraction, fraction) }
            previous = state.originalFraction
        }
    }

    func testExtremeFiniteDividerValuesClampWithoutProducingNaN() {
        var state = ReviewComparisonState()
        state.moveDivider(to: -Double.greatestFiniteMagnitude)
        XCTAssertEqual(state.originalFraction, 0)
        state.moveDivider(to: Double.greatestFiniteMagnitude)
        XCTAssertEqual(state.originalFraction, 1)
        state.moveDivider(to: Double.leastNonzeroMagnitude)
        XCTAssertEqual(state.originalFraction, Double.leastNonzeroMagnitude)
    }

    func testSplitToleranceAcceptsInsideAndRejectsOutsideBothSides() {
        let original = CGSize(width: 1000, height: 1000)
        for deviation: CGFloat in [-0.0031, -0.0029, 0.0029, 0.0031] {
            let edited = CGSize(width: 1000 / (1 + deviation), height: 1000)
            XCTAssertEqual(ReviewComparisonGeometry.supportsSplit(original: original, edited: edited, finish: .photo),
                           abs(deviation) < 0.003, "deviation=\(deviation)")
        }
    }

    func testMatchingGeometryIsIndependentOfImageResolution() {
        let aspects: [CGFloat] = [1, 0.75, 2.0 / 3, 0.5625, 4.0 / 3, 1.5, 16.0 / 9]
        for aspect in aspects {
            for sourceScale: CGFloat in [1, 37, 1000, 4032] {
                for previewScale: CGFloat in [1, 17, 1800] {
                    let source = CGSize(width: aspect * sourceScale, height: sourceScale)
                    let preview = CGSize(width: aspect * previewScale, height: previewScale)
                    XCTAssertTrue(ReviewComparisonGeometry.supportsSplit(original: source, edited: preview, finish: .photo))
                    XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(original: source, edited: preview, finish: .instantPrint))
                }
            }
        }
    }

    func testInvalidGeometryIsRejectedInEveryDimension() {
        let valid = CGSize(width: 300, height: 400)
        for invalid: CGFloat in [0, -1, -.infinity, .infinity, .nan] {
            for size in [CGSize(width: invalid, height: 400), CGSize(width: 300, height: invalid)] {
                XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(original: size, edited: valid, finish: .photo))
                XCTAssertFalse(ReviewComparisonGeometry.supportsSplit(original: valid, edited: size, finish: .photo))
            }
        }
    }

}
