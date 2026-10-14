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
        // XCUITest taps a corner of the frame when it judges the centre
        // covered, which it does once Settings content has scrolled under the
        // bar. Tap that corner on purpose: the whole frame has to respond,
        // not only the capsule drawn inside it.
        let backToCamera = app.buttons["settings-back-to-camera"]
        backToCamera.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
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
        waitForCamera(app)
        XCTAssertTrue(app.buttons["recipe-menu"].label.contains("Natural Standard"))
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
        waitForCamera(app)
        XCTAssertTrue(app.buttons["recipe-menu"].label.contains("G7 X Compact"))
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

    func testCaptureModesOpensWithoutACameraAndPicksAFilm() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: checks Capture modes with no camera.")
        #else
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        guard openCaptureModesWithoutACamera(app) else { return }

        // Queries the device lane relies on, checked here on a simulator.
        let finder = app.otherElements["capture-modes-viewfinder"]
        XCTAssertTrue(finder.exists)
        XCTAssertGreaterThanOrEqual(finder.frame.height, 200, "The preview, not the chip, carries the viewfinder identifier")
        for mode in ["photo", "burst", "macro", "portrait", "filmVideo", "night", "panorama", "spatialVideo"] {
            XCTAssertTrue(app.buttons["capture-mode-\(mode)"].exists, mode)
        }
        XCTAssertTrue(app.buttons["open-mode-captures"].exists)
        XCTAssertTrue(app.buttons["Back"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture-modes-shutter"].exists)
        assertReachable(app.buttons["capture-mode-photo"], in: app)

        // The film look is said to arrive after the shot.
        let chip = filmChip(in: app)
        XCTAssertEqual(chip.label, "Film: G7 X Compact")
        XCTAssertEqual(app.staticTexts["capture-modes-film-note"].label,
                       "Film look is added after you shoot. Originals are kept.")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Optical preview'")).firstMatch.exists)

        // A simulator supports every mode, so nothing is dimmed or explained.
        XCTAssertFalse(app.descendants(matching: .any)["capture-modes-unavailable-note"].exists)

        assertReachable(app.buttons["capture-modes-reopen-mode"], in: app)
        snapshot("capture-modes-no-camera")

        // The film list is searchable and marks the current film.
        let open = openFilmPicker(app)
        XCTAssertTrue(open.label.contains("Film: G7 X Compact"))
        open.tap()
        XCTAssertTrue(app.navigationBars["Choose film"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Used for shots taken here."].exists)
        let current = app.buttons["capture-film-g7x-compact"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(current.isSelected)
        XCTAssertTrue(current.label.contains("Current"))
        assertReachable(current, in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Muted Color")
        let muted = app.buttons["capture-film-classic-chrome"]
        XCTAssertTrue(muted.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["capture-film-g7x-compact"].exists, "The current film is not listed when it does not match")
        snapshot("capture-modes-film-picker-search")
        muted.tap()
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.navigationBars["Choose film"].exists && chip.label == "Film: Muted Color"
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [picked], timeout: 8), .completed)
        snapshot("capture-modes-film-picked")

        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        guard openCaptureModesWithoutACamera(app) else { return }
        assertReachable(app.buttons["capture-modes-reopen-mode"], in: app)
        XCTAssertTrue(app.frame.contains(app.descendants(matching: .any)["capture-modes-shutter"].frame),
                      "The shutter must stay on screen at the largest text size")
        XCTAssertTrue(filmChip(in: app).exists)
        snapshot("capture-modes-no-camera-largest-text")
        openFilmPicker(app).tap()
        XCTAssertTrue(app.navigationBars["Choose film"].waitForExistence(timeout: 5))
        let done = app.buttons["capture-film-picker-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        snapshot("capture-modes-film-picker-largest-text")
        done.tap()
        #endif
    }

    /// Returns the reachable film list button of the essentials row.
    private func openFilmPicker(_ app: XCUIApplication) -> XCUIElement {
        let open = app.buttons["capture-modes-film-picker-open"]
        revealInPage(open, in: app)
        assertReachable(open, in: app)
        return open
    }

    /// The container's `capture-modes-viewfinder` identifier wins over the chip's own, so find the chip by its text.
    private func filmChip(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Film: '")).firstMatch
    }

    /// Opens Capture modes on a simulator, allows the system camera prompt, dismisses the no-camera alert and
    /// waits for the settled screen. "Reopen mode" alone is no signal: it shows from the first frame.
    private func openCaptureModesWithoutACamera(_ app: XCUIApplication) -> Bool {
        waitForCamera(app)
        tapWhenStable(app.buttons["open-capture-modes"], in: app)
        var sawFailureAlert = false
        var settledSamples = 0
        let deadline = Date(timeIntervalSinceNow: 40)
        while Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
            let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if prompt.exists {
                if prompt.buttons["Allow"].exists { prompt.buttons["Allow"].tap() }
                else if prompt.buttons["OK"].exists { prompt.buttons["OK"].tap() }
                settledSamples = 0
                continue
            }
            let failure = app.alerts["Capture modes"]
            if failure.exists {
                if failure.buttons["OK"].exists { failure.buttons["OK"].tap() }
                sawFailureAlert = true
                settledSamples = 0
                continue
            }
            if app.buttons["capture-modes-open-settings"].exists {
                failureEvidence("capture-modes-camera-denied", app: app)
                XCTFail("Camera access is denied on this simulator. Reset the camera permission for Filmy Camera and run again.")
                return false
            }
            let chip = filmChip(in: app)
            let reopen = app.buttons["capture-modes-reopen-mode"]
            let settled = sawFailureAlert
                && !app.alerts.firstMatch.exists
                && app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'needs camera hardware'")).firstMatch.exists
                && chip.exists && chip.label.hasPrefix("Film: ")
                && !app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Preparing camera'")).firstMatch.exists
                && reopen.exists && reopen.isHittable
            settledSamples = settled ? settledSamples + 1 : 0
            if settledSamples >= 2 { return true }
        }
        failureEvidence("capture-modes-not-settled", app: app)
        XCTFail("Capture modes did not settle without a camera within 40 s")
        return false
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
        let expectedName = recipe.label.components(separatedBy: ",").first ?? id
        tapWhenStable(recipe, in: app, file: file, line: line)
        waitForCamera(app, file: file, line: line)
        XCTAssertTrue(
            app.buttons["recipe-menu"].label.localizedCaseInsensitiveContains(expectedName),
            "Selecting a look must update the current menu",
            file: file,
            line: line
        )
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
        // Each sample costs three queries; a loaded CI simulator fits only ~3 in 8 s.
        let result = XCTWaiter.wait(for: [settled], timeout: 20)
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
