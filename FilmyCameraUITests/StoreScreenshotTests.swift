import XCTest

@MainActor
final class StoreScreenshotTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        #if targetEnvironment(simulator)
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_STORE_MEDIA"] == "1",
            "Set FILMY_RUN_STORE_MEDIA=1 and seed one public-safe photo to capture store media"
        )
        #else
        throw XCTSkip("Store screenshot capture runs only on a seeded simulator")
        #endif

        addUIInterruptionMonitor(withDescription: "Filmy Camera permissions") { alert in
            MainActor.assumeIsolated {
                for title in ["Allow", "Allow Full Access", "Allow Access to All Photos", "OK"] {
                    let button = alert.buttons[title]
                    if button.exists {
                        button.tap()
                        return true
                    }
                }
                return false
            }
        }
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            launchedApp?.terminate()
        }
    }

    func testCaptureCurrentStoreScreens() throws {
        try importSeededPhoto(
            recipeID: "g7x-compact",
            recipeName: "G7 X Compact",
            minimumPhotoCount: 1,
            screenshotName: "01-g7x-import"
        )
        try importSeededPhoto(
            recipeID: "classic-chrome",
            recipeName: "Muted Color",
            minimumPhotoCount: 2,
            screenshotName: "02-film-import"
        )
        try importSeededPhoto(
            recipeID: "acros-monochrome",
            recipeName: "Fine Monochrome",
            minimumPhotoCount: 3,
            screenshotName: "03-monochrome-import",
            instantPrint: true
        )

        let openRoll = app.buttons["Open roll"]
        XCTAssertTrue(openRoll.waitForExistence(timeout: 10))
        openRoll.tap()
        XCTAssertTrue(app.staticTexts["Roll"].waitForExistence(timeout: 10))

        for recipeName in ["G7 X Compact", "Muted Color", "Fine Monochrome"] {
            let savedFrame = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", recipeName)
            ).firstMatch
            XCTAssertTrue(
                savedFrame.waitForExistence(timeout: 30),
                "Roll must contain the saved \(recipeName) treatment"
            )
        }
        attachScreenshot(named: "04-roll")

        let monochromeFrame = app.buttons.matching(
            NSPredicate(format: "label == 'Photo in your gallery, Fine Monochrome'")
        ).firstMatch
        monochromeFrame.tap()
        let photo = app.images["Photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 30))
        XCTAssertEqual(photo.value as? String, "Fit to screen")
        attachScreenshot(named: "05-photo-detail")
    }

    private func importSeededPhoto(
        recipeID: String,
        recipeName: String,
        minimumPhotoCount: Int,
        screenshotName: String,
        instantPrint: Bool = false
    ) throws {
        launchNormalApp(recipeID: recipeID)

        let currentLook = app.buttons["recipe-menu"]
        XCTAssertTrue(currentLook.waitForExistence(timeout: 15))
        XCTAssertTrue(currentLook.label.contains(recipeName))

        let importPhoto = app.buttons["import-photo"]
        XCTAssertTrue(importPhoto.waitForExistence(timeout: 10))
        importPhoto.tap()

        let photos = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        )
        let priorSaves = Int(ProcessInfo.processInfo.environment["FILMY_STORE_PRIOR_SAVES"] ?? "0") ?? 0
        XCTAssertGreaterThanOrEqual(priorSaves, 0)
        let expectedPhotoCount = minimumPhotoCount + priorSaves
        XCTAssertTrue(
            waitUntil(timeout: 30) { photos.count >= expectedPhotoCount },
            "Seed exactly one public-safe source before running; prior saves should remain visible"
        )

        // PhotosPicker is newest-first. The freshly seeded original starts at
        // index zero and moves one place after each save. Fresh simulators may
        // also show older system sample placeholders; never select those.
        // A partial run can be resumed with its exact prior save count while
        // retaining the same original; never feed a filtered output back in.
        let originalPhoto = photos.element(boundBy: expectedPhotoCount - 1)
        let photoFrame = originalPhoto.frame
        let appFrame = app.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: (photoFrame.midX - appFrame.minX) / appFrame.width,
                dy: (photoFrame.midY - appFrame.minY) / appFrame.height
            )
        ).tap()

        XCTAssertTrue(app.staticTexts["IMPORTED PHOTO"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts[recipeName].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Filter applied'")
            ).firstMatch.exists
        )
        let review = app.descendants(matching: .any)["review-screen"]
        let photo = app.descendants(matching: .any)["review-image"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let save = app.buttons["Save filtered photo"]
        if instantPrint {
            let finish = app.buttons["review-finish-instantPrint"]
            XCTAssertTrue(finish.waitForExistence(timeout: 5))
            finish.tap()
            XCTAssertTrue(waitUntil(timeout: 30) {
                photo.label.contains("Instant Print") && save.isEnabled
            }, "Store media must show the rendered Instant Print output")
        }
        let heading = app.staticTexts["IMPORTED PHOTO"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // These seeded media devices have a visible status bar and bottom
        // gesture area. PhotosPicker dismissal must settle before review is
        // accepted; existence alone can capture a full-screen transition.
        let topClearance: CGFloat = app.frame.width < 600 ? 44 : 20
        XCTAssertTrue(waitUntil(timeout: 10) {
            heading.frame.minY >= app.frame.minY + topClearance
                && save.frame.maxY <= app.frame.maxY - 20
        }, "Review controls must clear the status bar and bottom gesture area")
        XCTAssertGreaterThanOrEqual(review.frame.width, app.frame.width * 0.95)
        // The portrait photo shares the screen with Look, Compare and Finish.
        // Keep it substantial and entirely visible without cropping its source.
        XCTAssertTrue(app.frame.contains(photo.frame), "The whole photo must remain visible")
        XCTAssertGreaterThan(photo.frame.width, app.frame.width * 0.60)
        XCTAssertGreaterThan(photo.frame.height, app.frame.height * 0.40)
        // The public fixture is 1086x1448; its Instant Print output is 1164x1618.
        let expectedAspectRatio: CGFloat = instantPrint ? 1164.0 / 1618.0 : 3.0 / 4.0
        XCTAssertEqual(photo.frame.width / photo.frame.height, expectedAspectRatio, accuracy: 0.01,
                       "Review must preserve the complete photo or Instant Print aspect ratio")
        for identifier in ["review-look-picker", "review-compare-original",
                           "review-finish-photo", "review-finish-instantPrint"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(app.frame.contains(control.frame), "\(identifier) must remain fully visible")
            XCTAssertTrue(control.isHittable, "\(identifier) must remain reachable")
        }
        XCTAssertTrue(save.isHittable, "Save must remain reachable")
        let coveredLookControl = app.buttons["recipe-menu"]
        XCTAssertFalse(coveredLookControl.isHittable,
                       "Review must block interaction with the covered camera")
        if coveredLookControl.exists {
            XCTAssertFalse(coveredLookControl.isEnabled,
                           "Covered camera actions must remain disabled for assistive input")
        }
        XCTAssertFalse(photo.frame.intersects(app.buttons["Save filtered photo"].frame))
        attachScreenshot(named: screenshotName)

        save.tap()
        app.tap()
        let savedToast = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 40) {
                if savedToast.exists { return true }
                // The first Photos prompt can arrive after the initial tap,
                // so keep handling it while waiting for the save callback.
                // A passive wait alone never invokes an interruption monitor.
                let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
                if alert.exists,
                   alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Filmy Camera'")).firstMatch.exists {
                    let allow = alert.buttons["Allow"]
                    if allow.exists { allow.tap() }
                }
                return false
            },
            "The \(recipeName) output must save before the next treatment"
        )
    }

    private func launchNormalApp(recipeID: String) {
        app?.terminate()
        app = XCUIApplication()
        // -ui-testing is intentionally absent because it denies Photos reads.
        app.launchArguments = ["-selectedRecipeID", recipeID]
        app.launch()

        // A generic app-center tap selects a look in the interactive chooser.
        // Dismiss onboarding explicitly so the requested recipe stays active.
        let onboarding = app.descendants(matching: .any)["onboarding-screen"]
        if onboarding.waitForExistence(timeout: 3) {
            let skip = app.buttons["onboarding-skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return condition()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// Routine first-use acceptance uses an isolated preferences suite and never
// saves photos. It is deliberately separate from the opt-in media fixture.
@MainActor
final class LaunchOnboardingTests: XCTestCase {
    func testOnboardingControlsKeepSeparateIdentifiersAndFullHitTargets() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Launch.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-onboarding"]
        app.launch()
        defer { app.terminate() }

        let screen = app.otherElements["onboarding-screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "onboarding-screen").count, 0,
                       "The screen identifier must never replace a button identifier")
        for identifier in ["onboarding-skip", "onboarding-skip-for-now", "onboarding-continue"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(button.isHittable, identifier)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, identifier)
        }
        let firstUse = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        firstUse.name = "launch-interactive-recipe-selection"
        firstUse.lifetime = .keepAlways
        add(firstUse)
        app.buttons["onboarding-continue"].tap()
        let back = app.buttons["onboarding-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        XCTAssertGreaterThanOrEqual(back.frame.width, 44)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
    }

    func testChosenLookReachesCameraAndSurvivesRelaunch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Launch.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-onboarding"]
        app.launch()
        defer { app.terminate() }

        let muted = app.buttons["onboarding-recipe-classic-chrome"]
        XCTAssertTrue(muted.waitForExistence(timeout: 15))
        muted.tap()
        XCTAssertEqual(muted.value as? String, "Selected")
        app.buttons["onboarding-skip"].tap()
        let currentLook = app.buttons["recipe-menu"]
        XCTAssertTrue(currentLook.waitForExistence(timeout: 15))
        XCTAssertTrue(currentLook.label.contains("Muted Color"))

        app.terminate()
        // Drop only the forced-onboarding seed, retaining this test's suite.
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(currentLook.waitForExistence(timeout: 15))
        XCTAssertTrue(currentLook.label.contains("Muted Color"))
    }

    func testBackNavigationKeepsChosenLookThroughCompletion() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Launch.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-onboarding"]
        app.launch()
        defer { app.terminate() }

        let muted = app.buttons["onboarding-recipe-classic-chrome"]
        XCTAssertTrue(muted.waitForExistence(timeout: 15))
        muted.tap()
        let next = app.buttons["onboarding-continue"]
        next.tap()
        XCTAssertTrue(app.staticTexts["See the mood as you compose."].waitForExistence(timeout: 5))
        app.buttons["onboarding-back"].tap()
        XCTAssertTrue(muted.waitForExistence(timeout: 5))
        XCTAssertEqual(muted.value as? String, "Selected")
        XCTAssertEqual(app.buttons["onboarding-recipe-g7x-compact"].value as? String, "Not selected")

        next.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["Save the finished photo."].waitForExistence(timeout: 5))
        next.tap()
        let currentLook = app.buttons["recipe-menu"]
        XCTAssertTrue(currentLook.waitForExistence(timeout: 15))
        XCTAssertTrue(currentLook.label.contains("Muted Color"))
    }
}

/// Non-destructive discovery coverage. Every test owns its preferences and
/// never imports, saves, deletes, or requests Photos access.
@MainActor
final class LookLibraryUITests: XCTestCase {
    func testSearchFavoriteAndSelectionPersistWithoutAccidentalApply() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        openLibrary(app)
        let search = app.textFields["look-library-search"]
        search.tap()
        search.typeText("Muted Color\n")
        let muted = app.buttons["library-recipe-classic-chrome"]
        XCTAssertTrue(muted.waitForExistence(timeout: 10))
        XCTAssertEqual(muted.value as? String, "Not selected")
        let favorite = app.buttons["look-favorite-classic-chrome"]
        assertControl(favorite, in: app)
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, "Favorite")
        XCTAssertEqual(muted.value as? String, "Not selected", "Favoriting must not apply the look")
        XCTAssertTrue(app.buttons["look-library-close"].exists, "Favoriting must not dismiss the library")
        snapshot(app, "looks-search-favorite")
        app.buttons["look-library-close"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].label.contains("G7 X Compact"))

        app.terminate()
        app.launch()
        openLibrary(app)
        app.buttons["look-filter-favorites"].tap()
        XCTAssertTrue(muted.waitForExistence(timeout: 5), "Favorites must survive a real relaunch")
        XCTAssertFalse(app.buttons["library-recipe-g7x-compact"].exists)
        snapshot(app, "looks-favorites")
        muted.tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recipe-menu"].label.contains("Muted Color"))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["recipe-menu"].label.contains("Muted Color"))
    }

    func testEmptySearchAndFavoritesHaveRecoveryWithoutChangingTheLook() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        openLibrary(app)
        snapshot(app, "looks-library")
        app.buttons["look-filter-favorites"].tap()
        XCTAssertTrue(app.staticTexts["look-library-empty"].waitForExistence(timeout: 5))
        assertControl(app.buttons["look-library-reset"], in: app)
        app.buttons["look-library-reset"].tap()
        XCTAssertTrue(app.buttons["library-recipe-g7x-compact"].waitForExistence(timeout: 5))
        let search = app.textFields["look-library-search"]
        search.tap()
        search.typeText("no-such-look-987\n")
        XCTAssertTrue(app.staticTexts["look-library-empty"].waitForExistence(timeout: 5))
        snapshot(app, "looks-empty-search")
        app.buttons["look-library-reset"].tap()
        XCTAssertTrue(app.buttons["library-recipe-g7x-compact"].waitForExistence(timeout: 5),
                      "Clearing search must restore the unfiltered look cards")
        XCTAssertFalse(app.buttons["look-library-clear-search"].exists,
                       "The clear action must disappear when the query is empty")
        XCTAssertEqual(app.buttons["look-filter-all"].value as? String, "Selected")
        app.buttons["look-library-close"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].label.contains("G7 X Compact"))
    }

    func testLibraryLandscapeAndLargeTextKeepDismissalSearchAndFiltersReachable() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        openLibrary(app)
        assertControl(app.buttons["look-library-close"], in: app)
        assertControl(app.buttons["look-filter-all"], in: app)
        XCTAssertTrue(app.textFields["look-library-search"].isHittable)
        snapshot(app, "looks-landscape")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openLibrary(app)
        assertControl(app.buttons["look-library-close"], in: app)
        assertControl(app.buttons["look-filter-all"], in: app)
        XCTAssertTrue(app.textFields["look-library-search"].isHittable)
        let favorite = app.buttons["look-favorite-g7x-compact"]
        assertControl(favorite, in: app)
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, "Favorite")
        XCTAssertTrue(app.textFields["look-library-search"].exists, "Favoriting must not apply or dismiss")
        snapshot(app, "looks-accessibility-large-text")
    }

    func testEmptyRollOffersADirectReturnToShooting() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        let roll = app.buttons["roll-tab"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15))
        roll.tap()
        let start = app.buttons["roll-start-shooting"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        if !start.isHittable { app.scrollViews.firstMatch.swipeUp() }
        assertControl(start, in: app)
        snapshot(app, "roll-empty-recovery")
        start.tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
    }

    private func makeApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Library.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing"]
        return app
    }

    private func openLibrary(_ app: XCUIApplication) {
        let look = app.buttons["recipe-menu"]
        XCTAssertTrue(look.waitForExistence(timeout: 15))
        look.tap()
        let browse = app.buttons["look-library-open"]
        XCTAssertTrue(waitForStationaryControl(browse, in: app),
                      "Explore looks must finish moving before it is tapped")
        assertControl(browse, in: app)
        browse.tap()
        XCTAssertTrue(app.textFields["look-library-search"].waitForExistence(timeout: 5))
        assertControl(app.buttons["look-library-close"], in: app)
    }

    private func assertControl(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(element.frame))
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


@MainActor
final class CaptureSetupUITests: XCTestCase {
    func testCaptureSetupOpensAndKeepsAidsAcrossRelaunch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Setup.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing"]
        app.launch()
        defer { app.terminate() }
        openCaptureSetup(in: app)
        let aidIdentifiers = [
            "capture-level-toggle",
            "capture-histogram-toggle",
            "capture-zebras-toggle",
            "capture-peaking-toggle"
        ]
        for identifier in aidIdentifiers {
            let aid = captureAid(identifier, in: app)
            XCTAssertEqual(aid.value as? String, "0", "A fresh preferences suite starts with aids off")
            tapCaptureAid(aid, expecting: "1")
        }
        attachCaptureSetup(named: "capture-setup-aids-enabled")
        app.buttons["capture-setup-done"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        openCaptureSetup(in: app)
        for identifier in aidIdentifiers {
            XCTAssertEqual(captureAid(identifier, in: app).value as? String, "1", "\(identifier) must persist")
        }
        attachCaptureSetup(named: "capture-setup-aids-restored")

        // Cover the reverse transition too: an aid must not become sticky
        // after its persisted value changes from enabled back to disabled.
        tapCaptureAid(captureAid("capture-zebras-toggle", in: app), expecting: "0")
        app.buttons["capture-setup-done"].tap()
        app.terminate()
        app.launch()
        openCaptureSetup(in: app)
        XCTAssertEqual(captureAid("capture-zebras-toggle", in: app).value as? String, "0")
        XCTAssertEqual(captureAid("capture-peaking-toggle", in: app).value as? String, "1",
                       "Disabling zebras must leave the other aids enabled")
    }

    func testNewDigitalStyleCanBeSearchedSelectedAndPersisted() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Catalog.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing"]
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["recipe-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        let browse = app.buttons["look-library-open"]
        XCTAssertTrue(waitForStationaryControl(browse, in: app),
                      "Explore looks must finish moving before it is tapped")
        browse.tap()
        let search = app.textFields["look-library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("CCD Daylight\n")
        let style = app.buttons["library-recipe-digital-ccd-daylight"]
        XCTAssertTrue(style.waitForExistence(timeout: 5)); style.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); XCTAssertTrue(menu.label.contains("CCD Daylight"))
        app.terminate(); app.launch()
        XCTAssertTrue(menu.waitForExistence(timeout: 15)); XCTAssertTrue(menu.label.contains("CCD Daylight"))
    }

    private func openCaptureSetup(in app: XCUIApplication) {
        let setup = app.buttons["capture-setup-open"]
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        setup.tap()
        XCTAssertTrue(app.buttons["capture-setup-done"].waitForExistence(timeout: 5))
    }

    private func captureAid(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let aid = app.switches[identifier]
        let form = app.descendants(matching: .any)["capture-setup-form"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if aid.exists && aid.isHittable && form.frame.contains(aid.frame) { break }
            form.swipeUp()
        }
        XCTAssertTrue(aid.waitForExistence(timeout: 5))
        XCTAssertTrue(aid.isHittable, "\(identifier) must be reachable in Capture setup")
        XCTAssertTrue(form.frame.contains(aid.frame), "\(identifier) must be fully visible before tapping")
        XCTAssertTrue(aid.isEnabled)
        return aid
    }

    private func tapCaptureAid(_ aid: XCUIElement, expecting value: String) {
        // The identified SwiftUI Form row contains the native switch. Target
        // that control directly instead of assuming an inset from the row.
        XCTAssertEqual(aid.switches.count, 1, "The aid row must contain one native switch")
        let control = aid.switches.firstMatch
        XCTAssertTrue(control.isEnabled)
        XCTAssertTrue(control.isHittable)
        XCTAssertTrue(aid.frame.contains(control.frame), "The native switch must fit inside its visible row")
        control.tap()
        let updatedValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: aid
        )
        XCTAssertEqual(XCTWaiter.wait(for: [updatedValue], timeout: 5), .completed,
                       "Tapping \(aid.identifier) must change its value to \(value)")
    }

    private func attachCaptureSetup(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private func waitForStationaryControl(_ control: XCUIElement, in app: XCUIApplication) -> Bool {
    // Accessibility queries on a loaded hosted iPad can take several seconds
    // per observation. Allow enough time to compare two complete samples.
    let deadline = Date(timeIntervalSinceNow: 15)
    let frameTolerance: CGFloat = 1.0
    var previousFrame: CGRect?
    var stationarySince: Date?
    // A drawer's accessibility frame can appear before its spring transition
    // finishes. Wait for stable hit geometry; never retry the navigation tap,
    // which could instead close the drawer through the control underneath it.
    repeat {
        if control.exists && control.isEnabled && control.isHittable {
            let frame = control.frame
            if frame.width >= 44 && frame.height >= 44 && app.frame.contains(frame) {
                if let previousFrame,
                   abs(frame.minX - previousFrame.minX) <= frameTolerance,
                   abs(frame.minY - previousFrame.minY) <= frameTolerance,
                   abs(frame.width - previousFrame.width) <= frameTolerance,
                   abs(frame.height - previousFrame.height) <= frameTolerance {
                    if let stationarySince, Date().timeIntervalSince(stationarySince) >= 0.3 {
                        return true
                    }
                } else {
                    stationarySince = Date()
                }
                previousFrame = frame
            } else {
                previousFrame = nil
                stationarySince = nil
            }
        } else {
            previousFrame = nil
            stationarySince = nil
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    } while Date() < deadline
    return false
}
