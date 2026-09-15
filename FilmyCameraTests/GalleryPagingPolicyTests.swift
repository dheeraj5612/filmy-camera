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


    func testNeighborRejectsInvalidIndicesCountsAndOffsets() {
        for count in [Int.min, -1, 0] {
            for index in [Int.min, -1, 0, 1, Int.max] {
                for offset in [-1, 1] {
                    XCTAssertNil(GalleryPagingPolicy.neighbor(of: index, offset: offset, count: count))
                }
            }
        }
        for index in [Int.min, -1, 3, Int.max] {
            for offset in [-1, 1] {
                XCTAssertNil(GalleryPagingPolicy.neighbor(of: index, offset: offset, count: 3))
            }
        }
        for offset in [Int.min, -2, 0, 2, Int.max] {
            XCTAssertNil(GalleryPagingPolicy.neighbor(of: 1, offset: offset, count: 3))
        }
    }

    func testNeighborArithmeticDoesNotOverflowAtIntMax() {
        XCTAssertNil(GalleryPagingPolicy.neighbor(of: 0, offset: -1, count: Int.max))
        XCTAssertEqual(GalleryPagingPolicy.neighbor(of: 0, offset: 1, count: Int.max), 1)
        XCTAssertEqual(GalleryPagingPolicy.neighbor(of: Int.max - 2, offset: 1, count: Int.max), Int.max - 1)
        XCTAssertEqual(GalleryPagingPolicy.neighbor(of: Int.max - 1, offset: -1, count: Int.max), Int.max - 2)
        XCTAssertNil(GalleryPagingPolicy.neighbor(of: Int.max - 1, offset: 1, count: Int.max))
    }

    func testNeighborAndIdentityNavigationAgreeForEverySmallRoll() {
        for count in 1...64 {
            let ids = (0..<count).map { "owned-frame-\($0)" }
            for index in ids.indices {
                for offset in [-1, 1] {
                    let neighbor = GalleryPagingPolicy.neighbor(of: index, offset: offset, count: count)
                    let expectedIndex = index + offset
                    let expected = ids.indices.contains(expectedIndex) ? ids[expectedIndex] : nil
                    XCTAssertEqual(neighbor.map { ids[$0] }, expected, "count=\(count), index=\(index), offset=\(offset)")
                    XCTAssertEqual(GalleryPagingPolicy.targetIdentifier(
                        in: ids, selectedIdentifier: ids[index], direction: offset == 1 ? .next : .previous), expected)
                }
            }
        }
    }

    func testRetainedWindowIsEmptyForInvalidSelections() {
        for count in [Int.min, -1, 0, 1, 17, Int.max] {
            for index in [Int.min, -1, count, Int.max] {
                XCTAssertTrue(GalleryPagingPolicy.retainedIndices(around: index, count: count).isEmpty,
                              "count=\(count), index=\(index)")
            }
        }
    }

    func testRetainedWindowIncludesOnlySelectedAndImmediateNeighbors() {
        // Independent oracle: filter the roll, rather than repeating the production range arithmetic.
        for count in 1...128 {
            for index in 0..<count {
                let actual = Array(GalleryPagingPolicy.retainedIndices(around: index, count: count))
                let expected = (0..<count).filter { abs($0 - index) <= 1 }
                XCTAssertEqual(actual, expected, "count=\(count), index=\(index)")
                XCTAssertLessThanOrEqual(actual.count, 3, "Decoded-image retention must not grow with the Roll")
            }
        }
    }

    func testRetainedWindowHandlesIntMaxWithoutAllocatingTheRoll() {
        XCTAssertEqual(GalleryPagingPolicy.retainedIndices(around: 0, count: Int.max), 0..<2)
        XCTAssertEqual(GalleryPagingPolicy.retainedIndices(around: Int.max - 2, count: Int.max),
                       (Int.max - 3)..<Int.max)
        XCTAssertEqual(GalleryPagingPolicy.retainedIndices(around: Int.max - 1, count: Int.max),
                       (Int.max - 2)..<Int.max)
    }

    func testPagingAnEntireRollEvictsOldFramesInsteadOfAccumulatingThem() {
        let count = 512
        var retained = Set<Int>()
        for selected in 0..<count {
            let desired = Set(GalleryPagingPolicy.retainedIndices(around: selected, count: count))
            let evicted = retained.subtracting(desired)
            XCTAssertTrue(evicted.allSatisfy { $0 < selected - 1 })
            XCTAssertLessThanOrEqual(desired.subtracting(retained).count, selected == 0 ? 2 : 1)
            XCTAssertTrue(desired.contains(selected))
            retained = desired
        }
        XCTAssertEqual(retained, [count - 2, count - 1])
    }

    func testRefreshReorderingAndDeletionAlwaysResolveByIdentity() {
        let original = ["local/one", "photos/two", "写真/three", "four", "five"]
        for shift in original.indices {
            let refreshed = Array(original[shift...]) + Array(original[..<shift])
            for index in refreshed.indices {
                let selected = refreshed[index]
                XCTAssertEqual(GalleryPagingPolicy.targetIdentifier(in: refreshed, selectedIdentifier: selected, direction: .next),
                               index == refreshed.count - 1 ? nil : refreshed[index + 1])
                let deleted = refreshed.filter { $0 != selected }
                for direction in [GalleryPagingDirection.previous, .next] {
                    XCTAssertNil(GalleryPagingPolicy.targetIdentifier(in: deleted, selectedIdentifier: selected, direction: direction))
                }
            }
        }
    }

    func testSwipeThresholdUsesMinimumProportionalAndMaximumRegions() {
        let cases: [(CGFloat, CGFloat)] = [(1, 44), (275, 44), (400, 64), (562.5, 90), (1366, 90)]
        for (width, threshold) in cases {
            for sign: CGFloat in [-1, 1] {
                XCTAssertNil(direction(x: sign * (threshold - 0.0001), y: 0, width: width))
                XCTAssertEqual(direction(x: sign * threshold, y: 0, width: width), sign < 0 ? .next : .previous)
                XCTAssertEqual(direction(x: sign * (threshold + 0.0001), y: 0, width: width), sign < 0 ? .next : .previous)
            }
        }
    }

    func testDiagonalDominanceBoundaryIsStrictInEveryQuadrant() {
        for xSign: CGFloat in [-1, 1] {
            for ySign: CGFloat in [-1, 1] {
                XCTAssertNil(direction(x: xSign * 100, y: ySign * 80, width: 320))
                XCTAssertNil(direction(x: xSign * 100, y: ySign * 80.0001, width: 320))
                XCTAssertEqual(direction(x: xSign * 100, y: ySign * 79.9999, width: 320),
                               xSign < 0 ? .next : .previous)
            }
        }
    }

    func testEvenTheSmallestZoomDeviationPreventsPaging() {
        for zoom in [CGFloat(1).nextDown, CGFloat(1).nextUp] {
            XCTAssertNil(GalleryPagingPolicy.swipeDirection(
                translation: CGSize(width: 1000, height: 0), viewportWidth: 320, zoomScale: zoom))
        }
        XCTAssertEqual(GalleryPagingPolicy.swipeDirection(
            translation: CGSize(width: 1000, height: 0), viewportWidth: 320, zoomScale: 1), .previous)
    }

    func testMirroredGestureSamplesPreserveAcceptanceAndReverseDirection() {
        // Fixed arithmetic sequence is reproducible and covers both phone and tablet widths.
        for sample in 1...1024 {
            let x = CGFloat((sample * 73) % 401 - 200)
            let y = CGFloat((sample * 37) % 301 - 150)
            let width = CGFloat(240 + (sample * 29) % 1400)
            let forward = direction(x: x, y: y, width: width)
            let mirrored = direction(x: -x, y: -y, width: width)
            if let forward {
                XCTAssertEqual(mirrored, forward == .next ? .previous : .next, "sample=\(sample)")
            } else {
                XCTAssertNil(mirrored, "sample=\(sample)")
            }
        }
    }

    private func direction(x: CGFloat, y: CGFloat, width: CGFloat) -> GalleryPagingDirection? {
        GalleryPagingPolicy.swipeDirection(translation: CGSize(width: x, height: y), viewportWidth: width, zoomScale: 1)
    }
}
