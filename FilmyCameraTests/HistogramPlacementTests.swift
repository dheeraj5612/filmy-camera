import XCTest
@testable import FilmyCamera

final class HistogramPlacementTests: XCTestCase {
    func testDefaultAndOppositeCornerRespectCameraChrome() {
        let placement = HistogramPlacement(viewport: CGSize(width: 390, height: 520),
                                           topClearance: 62, bottomClearance: 110)
        let first = cardFrame(placement, at: .zero)
        let last = cardFrame(placement, at: CGPoint(x: 1, y: 1))
        XCTAssertEqual(first.minX, 8)
        XCTAssertEqual(first.minY, 62)
        XCTAssertEqual(last.maxX, 382)
        XCTAssertEqual(last.maxY, 410)
    }

    func testHugeDragsClampToEveryEdge() {
        let placement = HistogramPlacement(viewport: CGSize(width: 390, height: 520))
        for x: CGFloat in [-10_000, 10_000] {
            for y: CGFloat in [-10_000, 10_000] {
                let center = placement.center(normalizedPosition: CGPoint(x: 0.5, y: 0.5),
                                              translation: CGSize(width: x, height: y))
                let position = placement.normalizedPosition(for: center)
                XCTAssertEqual(position.x, x < 0 ? 0 : 1)
                XCTAssertEqual(position.y, y < 0 ? 0 : 1)
            }
        }
    }

    func testDragCommitsItsVisiblePositionWithoutJumping() {
        let placement = HistogramPlacement(viewport: CGSize(width: 390, height: 520))
        let saved = CGPoint(x: 0.2, y: 0.3)
        let visible = placement.center(normalizedPosition: saved, translation: CGSize(width: 45, height: 70))
        let committed = placement.normalizedPosition(for: visible, fallback: saved)
        let restored = placement.center(normalizedPosition: committed)
        XCTAssertEqual(restored.x, visible.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, visible.y, accuracy: 0.001)
    }

    func testRotationAndAspectChangesPreserveRelativePositionWithinFrame() {
        let saved = CGPoint(x: 0.87, y: 0.63)
        for viewport in [CGSize(width: 390, height: 520), CGSize(width: 520, height: 390),
                         CGSize(width: 390, height: 390), CGSize(width: 640, height: 360),
                         CGSize(width: 768, height: 1024)] {
            let placement = HistogramPlacement(viewport: viewport, topClearance: 62, bottomClearance: 110)
            let frame = cardFrame(placement, at: saved)
            XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(frame), "\(viewport): \(frame)")
            let restored = placement.normalizedPosition(for: placement.center(normalizedPosition: saved))
            XCTAssertEqual(restored.x, saved.x, accuracy: 0.001)
            XCTAssertEqual(restored.y, saved.y, accuracy: 0.001)
        }
    }

    func testTinyViewportsAndOversizedChromeNeverPushCardOutsideFrame() {
        for viewport in [CGSize(width: 90, height: 70), CGSize(width: 390, height: 150),
                         CGSize(width: 8, height: 8)] {
            let placement = HistogramPlacement(viewport: viewport, topClearance: 200, bottomClearance: 200)
            for position in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)] {
                let frame = cardFrame(placement, at: position)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertGreaterThanOrEqual(frame.minY, 0)
                XCTAssertLessThanOrEqual(frame.maxX, viewport.width)
                XCTAssertLessThanOrEqual(frame.maxY, viewport.height)
            }
        }
    }

    func testAxisWithNoTravelRetainsPreferenceUntilRoomReturns() {
        let placement = HistogramPlacement(viewport: CGSize(width: 118, height: 98))
        let saved = CGPoint(x: 0.8, y: 0.7)
        let position = placement.normalizedPosition(for: placement.center(normalizedPosition: saved), fallback: saved)
        XCTAssertEqual(position.x, saved.x)
        XCTAssertEqual(position.y, saved.y)
    }

    func testMeasuredTwoRowHeaderAndFullToolFooterLeaveClearance() {
        let viewport = CGSize(width: 520, height: 390)
        let placement = HistogramPlacement(viewport: viewport, topClearance: 100 + 8,
                                           bottomClearance: 124 + 8)
        let top = cardFrame(placement, at: .zero)
        let bottom = cardFrame(placement, at: CGPoint(x: 1, y: 1))
        XCTAssertEqual(top.minY, 108)
        XCTAssertEqual(bottom.maxY, viewport.height - 132)
        XCTAssertGreaterThanOrEqual(top.minY - 100, 8)
        XCTAssertGreaterThanOrEqual(viewport.height - 124 - bottom.maxY, 8)
    }

    func testShortLandscapeCompactsChartWithoutCoveringMeasuredControls() {
        let placement = HistogramPlacement(viewport: CGSize(width: 520, height: 300),
                                           topClearance: 108, bottomClearance: 132)
        let saved = CGPoint(x: 0.7, y: 0.8)
        let frame = cardFrame(placement, at: saved)
        XCTAssertEqual(placement.cardSize.height, 60)
        XCTAssertEqual(frame.minY, 108)
        XCTAssertEqual(frame.maxY, 168)
        XCTAssertEqual(placement.normalizedPosition(for: placement.center(normalizedPosition: saved),
                                                    fallback: saved).y, saved.y)
    }

    func testShowingToolsChangesPhysicalBoundsWithoutChangingStoredPosition() {
        let saved = CGPoint(x: 0.9, y: 1)
        let hidden = HistogramPlacement(viewport: CGSize(width: 390, height: 520), bottomClearance: 68)
        let shown = HistogramPlacement(viewport: CGSize(width: 390, height: 520), bottomClearance: 132)
        XCTAssertEqual(cardFrame(hidden, at: saved).maxY - cardFrame(shown, at: saved).maxY, 64)
        let restored = shown.normalizedPosition(for: shown.center(normalizedPosition: saved))
        XCTAssertEqual(restored.x, saved.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, saved.y, accuracy: 0.001)
    }

    func testInvalidStoredPositionAndTranslationAreFiniteAndBounded() {
        let placement = HistogramPlacement(viewport: CGSize(width: 390, height: 520))
        let center = placement.center(normalizedPosition: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
                                      translation: CGSize(width: CGFloat.nan, height: -CGFloat.infinity))
        XCTAssertEqual(center, placement.center(normalizedPosition: .zero))
        XCTAssertEqual(HistogramPlacement.sanitized(CGPoint(x: -5, y: 8)), CGPoint(x: 0, y: 1))
    }

    func testInvalidViewportProducesFiniteEmptyGeometry() {
        let placement = HistogramPlacement(viewport: CGSize(width: CGFloat.nan, height: -1))
        XCTAssertEqual(placement.cardSize, .zero)
        XCTAssertEqual(placement.center(normalizedPosition: CGPoint(x: 1, y: 1)), .zero)
    }

    private func cardFrame(_ placement: HistogramPlacement, at position: CGPoint) -> CGRect {
        let center = placement.center(normalizedPosition: position)
        return CGRect(x: center.x - placement.cardSize.width / 2,
                      y: center.y - placement.cardSize.height / 2,
                      width: placement.cardSize.width, height: placement.cardSize.height)
    }
}
