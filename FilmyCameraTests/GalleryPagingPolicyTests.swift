import XCTest
@testable import FilmyCamera

final class GalleryPagingPolicyTests: XCTestCase {
    func testNavigationVisitsEveryFrameInBothDirectionsWithoutWrapping() {
        let identifiers = (0..<137).map { "frame-\($0)" }
        for (index, identifier) in identifiers.enumerated() {
            XCTAssertEqual(
                GalleryPagingPolicy.targetIdentifier(in: identifiers, selectedIdentifier: identifier, direction: .next),
                index + 1 < identifiers.count ? identifiers[index + 1] : nil
            )
            XCTAssertEqual(
                GalleryPagingPolicy.targetIdentifier(in: identifiers, selectedIdentifier: identifier, direction: .previous),
                index > 0 ? identifiers[index - 1] : nil
            )
        }
    }

    func testEmptySingleAndRemovedSelectionsDoNotNavigate() {
        for direction in [GalleryPagingDirection.next, .previous] {
            XCTAssertNil(GalleryPagingPolicy.targetIdentifier(in: [], selectedIdentifier: "frame", direction: direction))
            XCTAssertNil(GalleryPagingPolicy.targetIdentifier(in: ["frame"], selectedIdentifier: "frame", direction: direction))
            XCTAssertNil(GalleryPagingPolicy.targetIdentifier(in: ["a", "b"], selectedIdentifier: "removed", direction: direction))
        }
    }

    func testNavigationResolvesCurrentIdentityAfterRollRefresh() {
        let refreshed = ["new-capture", "third", "second", "first"]
        XCTAssertEqual(
            GalleryPagingPolicy.targetIdentifier(in: refreshed, selectedIdentifier: "second", direction: .previous),
            "third"
        )
        XCTAssertEqual(
            GalleryPagingPolicy.targetIdentifier(in: refreshed, selectedIdentifier: "second", direction: .next),
            "first"
        )
        // Photos permission changes can replace a Photos source with its
        // local fallback. Paging remains anchored to its stable identifier.
        XCTAssertEqual(
            GalleryPagingPolicy.targetIdentifier(in: ["photos-frame", "cached-frame", "older"], selectedIdentifier: "cached-frame", direction: .next),
            "older"
        )
    }

    func testSwipesFollowRollOrderAtPhoneAndTabletWidths() {
        for viewportWidth: CGFloat in [320, 393, 852, 1024, 1366] {
            XCTAssertEqual(direction(x: -120, y: 8, width: viewportWidth), .next)
            XCTAssertEqual(direction(x: 120, y: -8, width: viewportWidth), .previous)
        }
    }

    func testShortVerticalAndDiagonalDragsDoNotPage() {
        for translation in [CGSize.zero, CGSize(width: 43, height: 0), CGSize(width: -43, height: 0),
                            CGSize(width: 100, height: 200), CGSize(width: -100, height: -100),
                            CGSize(width: 100, height: 80)] {
            XCTAssertNil(GalleryPagingPolicy.swipeDirection(translation: translation, viewportWidth: 393, zoomScale: 1))
        }
        XCTAssertNil(direction(x: 60, y: 0, width: 393))
        XCTAssertEqual(direction(x: 64, y: 0, width: 393), .previous)
        XCTAssertNil(direction(x: 89, y: 0, width: 1366))
        XCTAssertEqual(direction(x: 90, y: 0, width: 1366), .previous)
    }

    func testZoomedPanningAndInvalidGestureValuesNeverPage() {
        for zoom: CGFloat in [1.01, 2, 4, 0, -1, .infinity, .nan] {
            XCTAssertNil(GalleryPagingPolicy.swipeDirection(translation: CGSize(width: -300, height: 0), viewportWidth: 393, zoomScale: zoom))
        }
        for width: CGFloat in [0, -1, .infinity, .nan] {
            XCTAssertNil(direction(x: -300, y: 0, width: width))
        }
        for translation in [CGSize(width: CGFloat.infinity, height: 0), CGSize(width: CGFloat.nan, height: 0),
                            CGSize(width: -300, height: CGFloat.infinity), CGSize(width: -300, height: CGFloat.nan)] {
            XCTAssertNil(GalleryPagingPolicy.swipeDirection(translation: translation, viewportWidth: 393, zoomScale: 1))
        }
    }

    private func direction(x: CGFloat, y: CGFloat, width: CGFloat) -> GalleryPagingDirection? {
        GalleryPagingPolicy.swipeDirection(translation: CGSize(width: x, height: y), viewportWidth: width, zoomScale: 1)
    }
}
