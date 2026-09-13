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
}
