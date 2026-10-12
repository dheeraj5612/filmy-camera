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

    // MARK: Sectioning, filtering, selection, removal

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, in calendar: Calendar) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    func testDaySectionsSplitAtMidnightInTheInjectedTimeZone() {
        let calendar = utcCalendar()
        let items = [
            GalleryItem(id: "a", date: date(2026, 10, 12, 23, 59, in: calendar), lookName: nil),
            GalleryItem(id: "b", date: date(2026, 10, 12, 0, 0, in: calendar), lookName: nil),
            GalleryItem(id: "c", date: date(2026, 10, 11, 23, 59, in: calendar), lookName: nil),
            GalleryItem(id: "d", date: nil, lookName: nil)
        ]
        let model = GalleryLayoutModel(items: items, lookFilter: nil, calendar: calendar)
        XCTAssertEqual(model.sections.map(\.ids), [["a", "b"], ["c"], ["d"]])
        XCTAssertNil(model.sections.last?.day)

        var tokyo = calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        let shifted = GalleryLayoutModel(items: items, lookFilter: nil, calendar: tokyo)
        // 23:59 UTC is 08:59 next day in Tokyo, so "a" and "b" no longer share a day with each other.
        XCTAssertEqual(shifted.sections.map(\.ids), [["a"], ["b", "c"], ["d"]])
    }

    func testSectionTitlesAreTodayYesterdayThenMediumDate() {
        let calendar = utcCalendar()
        let now = date(2026, 10, 12, 9, in: calendar)
        let locale = Locale(identifier: "en_US")
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.startOfDay(for: date(2026, 10, 11, 18, in: calendar))
        let older = calendar.startOfDay(for: date(2026, 10, 1, 8, in: calendar))
        XCTAssertEqual(GallerySectionTitle.title(for: today, now: now, calendar: calendar, locale: locale), "Today")
        XCTAssertEqual(GallerySectionTitle.title(for: yesterday, now: now, calendar: calendar, locale: locale), "Yesterday")
        XCTAssertEqual(GallerySectionTitle.title(for: older, now: now, calendar: calendar, locale: locale), "Oct 1, 2026")
        XCTAssertEqual(GallerySectionTitle.title(for: nil, now: now, calendar: calendar, locale: locale), "Earlier")
    }

    func testLookCountsAndFilterNarrowTheVisibleFrames() {
        let calendar = utcCalendar()
        let day = date(2026, 10, 12, 10, in: calendar)
        let items = [
            GalleryItem(id: "1", date: day, lookName: "Gold"),
            GalleryItem(id: "2", date: day, lookName: "Mono"),
            GalleryItem(id: "3", date: day, lookName: "Gold"),
            GalleryItem(id: "4", date: day, lookName: nil)
        ]
        let all = GalleryLayoutModel(items: items, lookFilter: nil, calendar: calendar)
        XCTAssertEqual(all.looks, [GalleryLookCount(name: "Gold", count: 2), GalleryLookCount(name: "Mono", count: 1)])
        XCTAssertEqual(all.totalCount, 4)
        XCTAssertEqual(all.visibleIDs, ["1", "2", "3", "4"])

        let gold = GalleryLayoutModel(items: items, lookFilter: "Gold", calendar: calendar)
        XCTAssertEqual(gold.visibleIDs, ["1", "3"])
        XCTAssertEqual(gold.looks.count, 2, "Chips keep counting the whole roll while filtered")
        XCTAssertEqual(gold.totalCount, 4)

        let none = GalleryLayoutModel(items: items, lookFilter: "Missing", calendar: calendar)
        XCTAssertTrue(none.sections.isEmpty)
    }

    func testSelectionTogglesSelectsAllPrunesAndKeepsRollOrder() {
        var selection = GallerySelection()
        selection.toggle("b")
        selection.toggle("a")
        XCTAssertEqual(selection.count, 2)
        XCTAssertEqual(selection.ordered(in: ["a", "b", "c"]), ["a", "b"])
        selection.toggle("b")
        XCTAssertFalse(selection.contains("b"))

        selection.selectAll(["a", "b", "c"])
        XCTAssertTrue(selection.isAllSelected(in: ["a", "b", "c"]))
        selection.remove(["a"])
        XCTAssertFalse(selection.isAllSelected(in: ["a", "b", "c"]))
        selection.prune(keeping: ["b"])
        XCTAssertEqual(selection.ids, ["b"])
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
        XCTAssertFalse(selection.isAllSelected(in: []))
    }

    func testRemovalPrefersNextThenPreviousAndDismissesWhenEmpty() {
        let before = ["a", "b", "c"]
        XCTAssertEqual(GalleryRemovalPolicy.replacementID(removedID: "b", previousIDs: before, currentIDs: ["a", "c"]), "c")
        XCTAssertEqual(GalleryRemovalPolicy.replacementID(removedID: "c", previousIDs: before, currentIDs: ["a", "b"]), "b")
        XCTAssertEqual(GalleryRemovalPolicy.replacementID(removedID: "a", previousIDs: before, currentIDs: ["b", "c"]), "b")
        XCTAssertEqual(GalleryRemovalPolicy.replacementID(removedID: "b", previousIDs: before, currentIDs: ["a"]), "a")
        XCTAssertNil(GalleryRemovalPolicy.replacementID(removedID: "a", previousIDs: ["a"], currentIDs: []))
        XCTAssertNil(GalleryRemovalPolicy.replacementID(removedID: "x", previousIDs: before, currentIDs: before))
    }

    func testInfoRowsListOnlyDataThatExists() {
        let calendar = utcCalendar()
        let locale = Locale(identifier: "en_US")
        let full = GalleryInfo.rows(
            capturedAt: date(2026, 10, 12, 14, 5, in: calendar), lookName: "Gold",
            pixelWidth: 4032, pixelHeight: 3024, calendar: calendar, locale: locale
        )
        XCTAssertEqual(full.map(\.title), ["Captured", "Look", "Dimensions"])
        XCTAssertEqual(full.last?.value, "4032 × 3024 px")
        let bare = GalleryInfo.rows(
            capturedAt: nil, lookName: nil, pixelWidth: 0, pixelHeight: 0, calendar: calendar, locale: locale
        )
        XCTAssertTrue(bare.isEmpty)
    }

    private func direction(x: CGFloat, y: CGFloat, width: CGFloat) -> GalleryPagingDirection? {
        GalleryPagingPolicy.swipeDirection(translation: CGSize(width: x, height: y), viewportWidth: width, zoomScale: 1)
    }
}
