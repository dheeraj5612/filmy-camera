import XCTest

/// Camera discovery stays deterministic and never touches the user's Photos.
/// Split comparison uses the separate, existing seeded Photos lane.
@MainActor
final class SignalFrameUITests: XCTestCase {
    func testCameraFavoriteAndQuickRailSharePersistentLibraryState() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        let look = app.buttons["recipe-menu"]
        XCTAssertTrue(look.waitForExistence(timeout: 15))
        let initialLook = look.label
        let favorite = app.buttons["camera-favorite-look"]
        assertReachable(favorite, in: app)
        XCTAssertEqual(favorite.value as? String, "Not favorite")
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, "Favorite")
        XCTAssertEqual(look.label, initialLook)
        look.tap()
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.buttons["recipe-g7x-compact"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-classic-chrome"].exists)
        snapshot("signal-frame-quick-favorites")
        app.buttons["recipe-drawer-close"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(favorite.waitForExistence(timeout: 15))
        XCTAssertEqual(favorite.value as? String, "Favorite")
        favorite.tap()
        look.tap()
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.staticTexts["camera-favorites-empty"].waitForExistence(timeout: 5))
        assertReachable(app.buttons["camera-looks-all"], in: app)
        tapWhenStable(app.buttons["camera-looks-all"], in: app)
        XCTAssertTrue(app.buttons["recipe-g7x-compact"].waitForExistence(timeout: 5))
        app.buttons["recipe-drawer-close"].tap()
        XCTAssertEqual(look.label, initialLook)
    }

    func testCameraPrimaryControlsRemainReachableAtLargestAccessibilityText() {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 15))
        for id in ["recipe-menu", "camera-favorite-look", "import-photo", "camera-chrome-toggle"] {
            assertReachable(app.buttons[id], in: app)
        }
        snapshot("signal-frame-camera-largest-text")
        app.buttons["recipe-menu"].tap()
        for id in ["recipe-drawer-close", "camera-looks-favorites", "camera-looks-all"] {
            assertReachable(app.buttons[id], in: app)
        }
        snapshot("signal-frame-drawer-largest-text")
        app.buttons["recipe-drawer-close"].tap()

        // Secondary destinations must honor the full text size, rather than
        // inheriting the camera shell's intentionally bounded chrome scale.
        app.buttons["settings-tab"].tap()
        assertReachable(app.buttons["settings-back-to-camera"], in: app)
        let clearCache = app.buttons["clear-local-cache"]
        revealInPage(clearCache, in: app)
        XCTAssertGreaterThan(clearCache.frame.width, 180)
        XCTAssertFalse(app.staticTexts["250 MB"].exists, "Do not present the cache budget as measured usage")
        snapshot("signal-frame-settings-storage-largest-text")
        app.buttons["settings-back-to-camera"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments += ["-ui-testing-onboarding"]
        app.launch()
        assertReachable(app.buttons["onboarding-continue"], in: app)
        let recipe = app.buttons["onboarding-recipe-classic-chrome"]
        revealInPage(recipe, in: app)
        assertReachable(recipe, in: app)
        XCTAssertGreaterThan(recipe.frame.width, 180, "Accessibility choices should be readable rows, not narrow tiles")
        recipe.tap()
        XCTAssertEqual(recipe.value as? String, "Selected")
        snapshot("signal-frame-onboarding-choices-largest-text")
        let compare = app.buttons["onboarding-compare"]
        revealInPage(compare, in: app)
        assertReachable(compare, in: app)
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Original")
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Look")
        snapshot("signal-frame-onboarding-compare-largest-text")
        app.buttons["onboarding-continue"].tap()
        let menu = app.buttons["recipe-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        let selectedLook = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            menu.label.contains("Muted Color")
        }, object: nil)
        let result = XCTWaiter.wait(for: [selectedLook], timeout: 5)
        if result != .completed { failureEvidence("onboarding-look-not-applied", app: app) }
        XCTAssertEqual(result, .completed, "Onboarding must apply Muted Color; found: \(menu.label)")
    }

    private func revealInPage(_ control: XCUIElement, in app: XCUIApplication) {
        let settingsScroll = app.scrollViews["settings-scroll"]
        let scroll = settingsScroll.exists ? settingsScroll : app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<24 {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 8)
            if control.exists && viewport.contains(control.frame) { return }
            let downward = control.exists && control.frame.midY < viewport.midY
            // Use the middle of the view rather than its bottom edge, which is
            // covered by the tab bar at the largest accessibility text size.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.30 : 0.72))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.72 : 0.30))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        snapshot("signal-frame-unreachable-page-control")
        XCTFail("Could not fully reveal \(control.identifier)")
    }


    func testSelectedLookSurvivesColdLaunchWithoutARecipeLaunchOverride() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        waitForCamera(app)
        let initial = app.buttons["recipe-menu"].label
        selectLook("provia-standard", app: app)
        let selected = app.buttons["recipe-menu"].label
        XCTAssertNotEqual(selected, initial, "Selecting a different row must change the actual camera look")
        relaunchPreservingPreferences(app)
        XCTAssertEqual(app.buttons["recipe-menu"].label, selected)
        waitForValue("Not favorite", of: app.buttons["camera-favorite-look"], app: app)
    }

    func testFavoritesBelongToIndividualLooksAndRemovalDoesNotAffectOtherLooks() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        waitForCamera(app)
        toggleFavorite(app, expected: "Favorite")
        selectLook("provia-standard", app: app)
        waitForValue("Not favorite", of: app.buttons["camera-favorite-look"], app: app)
        toggleFavorite(app, expected: "Favorite")
        selectLook("g7x-compact", app: app)
        waitForValue("Favorite", of: app.buttons["camera-favorite-look"], app: app)
        toggleFavorite(app, expected: "Not favorite")
        tapWhenStable(app.buttons["recipe-menu"], in: app)
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.buttons["recipe-provia-standard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-g7x-compact"].exists)
        tapWhenStable(app.buttons["recipe-provia-standard"], in: app)
        waitForValue("Selected", of: app.buttons["recipe-provia-standard"], app: app)
        tapWhenStable(app.buttons["recipe-drawer-close"], in: app)
        waitForCamera(app)
        waitForValue("Favorite", of: app.buttons["camera-favorite-look"], app: app)
    }

    func testUnfavoritingTheLastLookPersistsAnEmptyLibraryAfterRelaunch() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        waitForCamera(app)
        toggleFavorite(app, expected: "Favorite")
        relaunchPreservingPreferences(app)
        waitForValue("Favorite", of: app.buttons["camera-favorite-look"], app: app)
        toggleFavorite(app, expected: "Not favorite")
        relaunchPreservingPreferences(app)
        waitForValue("Not favorite", of: app.buttons["camera-favorite-look"], app: app)
        tapWhenStable(app.buttons["recipe-menu"], in: app)
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.staticTexts["camera-favorites-empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-g7x-compact"].exists)
        tapWhenStable(app.buttons["camera-looks-all"], in: app)
        XCTAssertTrue(app.buttons["recipe-g7x-compact"].waitForExistence(timeout: 5))
        tapWhenStable(app.buttons["recipe-drawer-close"], in: app)
        waitForCamera(app)
    }

    func testIsolatedPreferenceSuitesCannotLeakLookSelectionOrFavorites() {
        continueAfterFailure = false
        let first = makeApp()
        let second = makeApp()
        XCTAssertNotEqual(first.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"], second.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"])
        first.launch()
        defer { first.terminate(); second.terminate() }
        waitForCamera(first)
        selectLook("provia-standard", app: first)
        let firstLook = first.buttons["recipe-menu"].label
        toggleFavorite(first, expected: "Favorite")
        first.terminate()
        second.launch()
        waitForCamera(second)
        XCTAssertNotEqual(second.buttons["recipe-menu"].label, firstLook)
        waitForValue("Not favorite", of: second.buttons["camera-favorite-look"], app: second)
        tapWhenStable(second.buttons["recipe-menu"], in: second)
        tapWhenStable(second.buttons["camera-looks-favorites"], in: second)
        XCTAssertTrue(second.staticTexts["camera-favorites-empty"].waitForExistence(timeout: 5))
        second.terminate()
        relaunchPreservingPreferences(first)
        XCTAssertEqual(first.buttons["recipe-menu"].label, firstLook)
        waitForValue("Favorite", of: first.buttons["camera-favorite-look"], app: first)
    }

    func testBackgroundForegroundCyclePreservesLookAndFavoriteState() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        waitForCamera(app)
        selectLook("provia-standard", app: app)
        toggleFavorite(app, expected: "Favorite")
        let selected = app.buttons["recipe-menu"].label
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForCamera(app)
        XCTAssertEqual(app.buttons["recipe-menu"].label, selected)
        waitForValue("Favorite", of: app.buttons["camera-favorite-look"], app: app)
        tapWhenStable(app.buttons["recipe-menu"], in: app)
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.buttons["recipe-provia-standard"].waitForExistence(timeout: 5))
    }

    func testRepeatedFilterAndDismissCyclesNeverCommitADifferentLook() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        waitForCamera(app)
        toggleFavorite(app, expected: "Favorite")
        let selected = app.buttons["recipe-menu"].label
        for cycle in 0..<3 {
            tapWhenStable(app.buttons["recipe-menu"], in: app)
            tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
            XCTAssertTrue(app.buttons["recipe-g7x-compact"].waitForExistence(timeout: 5))
            tapWhenStable(app.buttons["camera-looks-all"], in: app)
            tapWhenStable(app.buttons["recipe-drawer-close"], in: app)
            waitForCamera(app)
            XCTAssertEqual(app.buttons["recipe-menu"].label, selected, "cycle=\(cycle)")
            waitForValue("Favorite", of: app.buttons["camera-favorite-look"], app: app)
        }
    }

    func testLargestAccessibilityTextSupportsTheCompleteFavoriteSelectionFlow() {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        waitForCamera(app)
        assertReachable(app.buttons["camera-favorite-look"], in: app)
        toggleFavorite(app, expected: "Favorite")
        let selected = app.buttons["recipe-menu"].label
        tapWhenStable(app.buttons["recipe-menu"], in: app)
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        assertReachable(app.buttons["recipe-g7x-compact"], in: app)
        tapWhenStable(app.buttons["recipe-g7x-compact"], in: app)
        waitForValue("Selected", of: app.buttons["recipe-g7x-compact"], app: app)
        tapWhenStable(app.buttons["recipe-drawer-close"], in: app)
        waitForCamera(app)
        XCTAssertEqual(app.buttons["recipe-menu"].label, selected)
        waitForValue("Favorite", of: app.buttons["camera-favorite-look"], app: app)
        snapshot("signal-frame-accessible-favorite-roundtrip")
    }

    func testRepeatedFavoriteTogglesDoNotLeaveDuplicateOrStaleEntries() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        waitForCamera(app)
        for _ in 0..<3 {
            toggleFavorite(app, expected: "Favorite")
            toggleFavorite(app, expected: "Not favorite")
        }
        toggleFavorite(app, expected: "Favorite")
        relaunchPreservingPreferences(app)
        tapWhenStable(app.buttons["recipe-menu"], in: app)
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.buttons["recipe-g7x-compact"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "recipe-g7x-compact").count, 1)
        XCTAssertFalse(app.buttons["recipe-provia-standard"].exists)
        tapWhenStable(app.buttons["recipe-drawer-close"], in: app)
        waitForCamera(app)
        toggleFavorite(app, expected: "Not favorite")
    }

    private func waitForCamera(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningForeground && app.buttons["recipe-menu"].exists
                && app.buttons["recipe-menu"].isHittable && !app.buttons["recipe-drawer-close"].exists
        }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 15)
        if result != .completed { failureEvidence("camera-not-ready", app: app) }
        XCTAssertEqual(result, .completed, "Camera must be usable and the drawer dismissed", file: file, line: line)
    }

    private func waitForValue(_ value: String, of control: XCUIElement, app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            control.exists && control.value as? String == value
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 5)
        if result != .completed { failureEvidence("value-not-\(value)", app: app) }
        XCTAssertEqual(result, .completed, "Expected \(control.identifier) value: \(value)", file: file, line: line)
    }

    private func toggleFavorite(_ app: XCUIApplication, expected: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        tapWhenStable(app.buttons["camera-favorite-look"], in: app, file: file, line: line)
        waitForValue(expected, of: app.buttons["camera-favorite-look"], app: app, file: file, line: line)
    }

    private func selectLook(_ id: String, app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        tapWhenStable(app.buttons["recipe-menu"], in: app, file: file, line: line)
        tapWhenStable(app.buttons["camera-looks-all"], in: app, file: file, line: line)
        let recipe = app.buttons["recipe-\(id)"]
        let picker = app.descendants(matching: .any).matching(identifier: "recipe-picker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), file: file, line: line)
        // All looks is vertically grouped. Reach the Film row from Digital,
        // or return to Digital from Film, without scrolling the camera shell.
        for _ in 0..<6 {
            if recipe.exists && recipe.isHittable && picker.frame.contains(recipe.frame) { break }
            if id == "g7x-compact" { picker.swipeDown() } else { picker.swipeUp() }
        }
        tapWhenStable(recipe, in: app, file: file, line: line)
        waitForValue("Selected", of: recipe, app: app, file: file, line: line)
        // The quick picker stays open while comparing looks; the user closes it.
        tapWhenStable(app.buttons["recipe-drawer-close"], in: app, file: file, line: line)
        waitForCamera(app, file: file, line: line)
    }

    private func relaunchPreservingPreferences(_ app: XCUIApplication) {
        app.terminate()
        // A repeated seed would mask a broken persistence implementation.
        if let index = app.launchArguments.firstIndex(of: "-selectedRecipeID"), index + 1 < app.launchArguments.count {
            app.launchArguments.removeSubrange(index...(index + 1))
        }
        app.launch()
        waitForCamera(app)
    }

    private func failureEvidence(_ name: String, app: XCUIApplication) {
        snapshot(name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-accessibility-tree"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func makeApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.SignalFrame.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-viewfinder-chrome", "-selectedRecipeID", "g7x-compact"]
        return app
    }

    private func tapWhenStable(_ control: XCUIElement, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        var previousFrame: CGRect?
        var stableSamples = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard control.exists, control.isHittable else {
                previousFrame = nil
                stableSamples = 0
                return false
            }
            let frame = control.frame
            stableSamples = frame == previousFrame ? stableSamples + 1 : 0
            previousFrame = frame
            return stableSamples >= 2 && app.frame.contains(frame)
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 8)
        if result != .completed { failureEvidence("control-not-settled", app: app) }
        XCTAssertEqual(result, .completed, "Control must settle before tapping", file: file, line: line)
        guard result == .completed else { return }
        control.tap()
    }

    private func assertReachable(_ control: XCUIElement, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        // XCTest can deserialize an exact 44pt SwiftUI frame as
        // 43.99999999999997. Keep the accessibility contract exact while
        // allowing only sub-pixel floating-point noise.
        XCTAssertGreaterThanOrEqual(control.frame.width, 43.99, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.height, 43.99, file: file, line: line)
        XCTAssertTrue(app.frame.contains(control.frame), "Control must not be partially clipped", file: file, line: line)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
