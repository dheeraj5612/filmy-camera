import XCTest

@MainActor
final class FilmyCameraUITests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The monitor handler is not actor-isolated in the Xcode 16 SDK, but
        // XCTest invokes it on the main thread; hop explicitly so XCUIElement
        // calls compile under Swift 6 on every supported toolchain.
        addUIInterruptionMonitor(withDescription: "Filmy Camera permissions") { alert in
            MainActor.assumeIsolated {
                let allowedButtons = [
                    "Allow",
                    "Allow Full Access",
                    "Allow Access to All Photos",
                    "OK"
                ]

                for title in allowedButtons {
                    let button = alert.buttons[title]
                    if button.exists {
                        button.tap()
                        return true
                    }
                }
                return false
            }
        }
        let launchedApp = MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
            let launchedApp = XCUIApplication()
            launchedApp.launchArguments = [
                "-ui-testing",
                "-selectedRecipeID",
                "classic-chrome"
            ]
            launchedApp.launch()
            return launchedApp
        }
        app = launchedApp
        // A no-op tap gives XCTest an interaction with which to invoke the
        // interruption monitor when a first-launch permission alert is present.
        MainActor.assumeIsolated {
            launchedApp.tap()
        }
    }

    func testCameraShellAndRecipeDetails() throws {
        let cameraTab = app.buttons["camera-tab"]
        assertMinimumHitTarget(cameraTab, named: "Camera tab")
        let importPhoto = app.buttons["import-photo"]
        assertMinimumHitTarget(importPhoto, named: "Import photo")
        XCTAssertTrue(app.buttons["Open roll"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["RECIPE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Natural Standard"].waitForExistence(timeout: 5))

        let recipePicker = app.descendants(matching: .any)["recipe-picker"]
        XCTAssertTrue(recipePicker.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            recipePicker.frame.height,
            150,
            "The standard recipe picker should remain content-sized"
        )
        attachScreenshot(named: "camera-shell-expanded")

        let controlsToggle = app.buttons["camera-chrome-toggle"]
        if controlsToggle.exists, controlsToggle.label == "Show camera controls" {
            controlsToggle.tap()
        }

        let classicChrome = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Muted Color'")
        ).firstMatch
        assertMinimumHitTarget(classicChrome, named: "Muted Color recipe")
        classicChrome.tap()

        let details = app.buttons["Tune Muted Color"]
        assertMinimumHitTarget(details, named: "Tune recipe")
        details.tap()

        XCTAssertTrue(app.staticTexts["Recipe controls"].waitForExistence(timeout: 5))
        let done = app.buttons["Done editing Muted Color"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable, "Selected recipe details need an explicit dismissal control")

        let reset = app.buttons["Reset recipe controls"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        scrollToHittable(reset, in: app)
        XCTAssertTrue(reset.isHittable, "Reset recipe controls should be reachable")

        let exposure = app.descendants(matching: .any)["exposure-control"]
        assertMinimumAccessibilityFrame(exposure, named: "Exposure control")
        let fxBlue = app.descendants(matching: .any)["fx-blue-control"]
        XCTAssertTrue(fxBlue.waitForExistence(timeout: 5), "FX Blue control should be discoverable")
        let colorChrome = app.descendants(matching: .any)["recipe-choice-Color Chrome"]
        XCTAssertTrue(colorChrome.waitForExistence(timeout: 5), "Color Chrome control should be discoverable")
        let dRangePriority = app.descendants(matching: .any)["recipe-choice-D Range Priority"]
        XCTAssertTrue(dRangePriority.waitForExistence(timeout: 5), "D Range Priority should be discoverable")
        let whiteBalance = app.descendants(matching: .any)["recipe-choice-White balance"]
        XCTAssertTrue(whiteBalance.waitForExistence(timeout: 5), "White balance mode should be discoverable")
        XCTAssertFalse(app.buttons["Decrease exposure compensation"].exists)
        XCTAssertFalse(app.buttons["Increase exposure compensation"].exists)

        let referenceCard = app.descendants(matching: .any)["public-reference-settings"]
        scrollToHittable(referenceCard, in: app)
        XCTAssertTrue(
            app.staticTexts["PUBLIC REFERENCE"].waitForExistence(timeout: 5),
            "Recipe details should expose the public reference settings"
        )
        XCTAssertTrue(app.staticTexts["DR200"].exists)
        attachScreenshot(named: "recipe-details")
    }

    func testExpandedRecipeCanLaunchSelected() throws {
        app.terminate()

        let expandedApp = XCUIApplication()
        expandedApp.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "nostalgic-summer"
        ]
        expandedApp.launch()

        XCTAssertTrue(expandedApp.staticTexts["Nostalgic Summer"].waitForExistence(timeout: 8))
        XCTAssertTrue(expandedApp.buttons["Tune Nostalgic Summer"].waitForExistence(timeout: 5))

        let selectedRecipe = expandedApp.buttons["recipe-nostalgic-summer"]
        XCTAssertTrue(selectedRecipe.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedRecipe.value as? String, "Selected")
    }

    func testG7XModeExposesDedicatedCompactProfile() throws {
        app.terminate()

        let compactApp = XCUIApplication()
        compactApp.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "g7x-compact"
        ]
        compactApp.launch()
        defer { compactApp.terminate() }

        XCTAssertTrue(compactApp.staticTexts["CAMERA PROFILE"].waitForExistence(timeout: 8))
        XCTAssertTrue(compactApp.staticTexts["G7 X Compact"].waitForExistence(timeout: 5))

        let selectedRecipe = compactApp.buttons["recipe-g7x-compact"]
        assertMinimumHitTarget(selectedRecipe, named: "G7 X recipe")
        XCTAssertEqual(selectedRecipe.value as? String, "Selected")

        let tune = compactApp.buttons["Tune G7 X Compact"]
        assertMinimumHitTarget(tune, named: "Tune G7 X profile")
        tune.tap()

        let profile = compactApp.descendants(matching: .any)["g7x-profile-details"]
        scrollToHittable(profile, in: compactApp)
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(compactApp.staticTexts["G7 X PROFILE"].exists)
        XCTAssertTrue(compactApp.staticTexts["Dedicated compact-digital pipeline"].exists)
        attachScreenshot(named: "g7x-profile-details")
    }

    func testG7XModeKeepsCompactCaptureControlsOneTapAway() throws {
        app.terminate()

        let compactApp = XCUIApplication()
        compactApp.launchArguments = [
            "-ui-testing",
            "-ui-testing-viewfinder-chrome",
            "-selectedRecipeID",
            "g7x-compact"
        ]
        compactApp.launch()
        defer { compactApp.terminate() }

        XCTAssertTrue(compactApp.staticTexts["CAMERA PROFILE"].waitForExistence(timeout: 8))

        let captureControls = compactApp.descendants(matching: .any)["g7x-capture-controls"]
        XCTAssertTrue(captureControls.waitForExistence(timeout: 5))
        XCTAssertTrue(compactApp.descendants(matching: .any)["zoom-control"].exists)
        XCTAssertTrue(compactApp.descendants(matching: .any)["exposure-control"].exists)

        let grid = compactApp.buttons["g7x-grid-control"]
        assertMinimumHitTarget(grid, named: "G7 X grid control")
        let initialGridValue = grid.value as? String
        XCTAssertTrue(initialGridValue == "On" || initialGridValue == "Off")
        grid.tap()
        XCTAssertNotEqual(grid.value as? String, initialGridValue)

        XCTAssertTrue(compactApp.descendants(matching: .any)["recipe-picker"].exists)
        attachScreenshot(named: "g7x-quick-capture-controls")
    }

    func testLandscapeCameraShell() throws {
        XCUIDevice.shared.orientation = .landscapeLeft

        let cameraTab = app.buttons["camera-tab"]
        assertMinimumHitTarget(cameraTab, named: "Landscape camera tab")
        let importPhoto = app.buttons["import-photo"]
        assertMinimumHitTarget(importPhoto, named: "Landscape import photo")

        let controlsToggle = app.buttons["camera-chrome-toggle"]
        if controlsToggle.waitForExistence(timeout: 2), controlsToggle.label == "Show camera controls" {
            controlsToggle.tap()
        }

        let recipeMenu = app.descendants(matching: .any)["recipe-menu"]
        XCTAssertTrue(recipeMenu.waitForExistence(timeout: 8), "Landscape recipe menu should exist")
        assertMinimumAccessibilityFrame(recipeMenu, named: "Landscape recipe menu")

        let tune = app.buttons["Tune Muted Color"]
        assertMinimumHitTarget(tune, named: "Landscape tune recipe")

        // The side column keeps the recipe menu above the capture controls,
        // with Roll and Tune sharing one row so the column fits an iPhone's
        // landscape height above the dock.
        let roll = app.buttons["Open roll"]
        assertMinimumHitTarget(roll, named: "Landscape Roll")
        XCTAssertLessThan(
            recipeMenu.frame.maxY,
            tune.frame.minY,
            "The recipe menu should sit above the capture controls in the side column"
        )
        XCTAssertEqual(roll.frame.midY, tune.frame.midY, accuracy: 1, "Roll and Tune share a row")
        XCTAssertLessThan(
            roll.frame.maxY,
            cameraTab.frame.minY,
            "Landscape capture controls must stay clear of the dock"
        )
        attachScreenshot(named: "camera-landscape")
    }

    #if !targetEnvironment(simulator)
    /// Writes a filtered copy into the device's real Photos library, so it
    /// runs only against an explicitly provisioned library.
    func testPhysicalImportAppliesCurrentRecipeAndSaves() throws {
        try skipUnlessPhotosWritesAreAllowed()
        let importPhoto = app.buttons["import-photo"]
        assertMinimumHitTarget(importPhoto, named: "Import photo")
        importPhoto.tap()

        let firstPhoto = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        ).firstMatch
        guard firstPhoto.waitForExistence(timeout: 10) else {
            app.buttons["Cancel"].firstMatch.tap()
            throw XCTSkip("The Photos library on this device has no image to import")
        }
        let photoFrame = firstPhoto.frame
        let appFrame = app.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: (photoFrame.midX - appFrame.minX) / appFrame.width,
                dy: (photoFrame.midY - appFrame.minY) / appFrame.height
            )
        ).tap()

        XCTAssertTrue(
            app.staticTexts["IMPORTED PHOTO"].waitForExistence(timeout: 30),
            "The imported image should reach filtered review"
        )
        // Whichever library photo the picker lists first, the caption must
        // say what happened: full resolution, or resized past the budget.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Filter applied'")).firstMatch.exists,
            "The import review must state the applied resolution"
        )
        XCTAssertTrue(app.buttons["Cancel"].exists, "An import review offers Cancel instead of Retake")
        attachScreenshot(named: "imported-photo-review")

        let save = app.buttons["Save filtered photo"]
        assertMinimumHitTarget(save, named: "Save filtered photo")
        save.tap()
        app.tap()

        let savedToast = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            savedToast.waitForExistence(timeout: 20),
            "The filtered photo should be committed to Photos"
        )
        attachScreenshot(named: "imported-photo-saved")
    }

    /// Every default device run must leave the Photos library untouched. The
    /// save paths run only when a provisioned test library is declared, e.g.
    /// TEST_RUNNER_FILMY_RUN_PHOTOS_WRITE=1 xcodebuild ... ; the app cannot
    /// delete what it saved under `-ui-testing`, which forces Photos read
    /// access to denied.
    private func skipUnlessPhotosWritesAreAllowed() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
            "Set FILMY_RUN_PHOTOS_WRITE=1 to run tests that write to the device's Photos library"
        )
    }

    /// Presses the real shutter, reaches review, and keeps the frame to
    /// Photos. Only meaningful on hardware with a camera, and only against a
    /// provisioned Photos library because the frame is committed for real.
    func testPhysicalCaptureKeepsFrameToPhotos() throws {
        try skipUnlessPhotosWritesAreAllowed()
        let shutter = app.buttons["Capture photo"]
        XCTAssertTrue(
            shutter.waitForExistence(timeout: 20),
            "The live camera should expose an enabled shutter on hardware"
        )
        assertMinimumHitTarget(shutter, named: "Shutter")
        attachScreenshot(named: "device-live-viewfinder")
        shutter.tap()

        let keepFrame = app.buttons["Keep frame"]
        XCTAssertTrue(
            keepFrame.waitForExistence(timeout: 30),
            "A capture should reach the review sheet"
        )
        XCTAssertTrue(app.buttons["Retake"].exists)
        attachScreenshot(named: "device-capture-review")

        assertMinimumHitTarget(keepFrame, named: "Keep frame")
        keepFrame.tap()
        app.tap()

        let savedToast = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            savedToast.waitForExistence(timeout: 20),
            "The kept frame should be committed to Photos"
        )
        XCTAssertTrue(
            waitForDisappearance(keepFrame, timeout: 5),
            "Keeping a frame should dismiss the review sheet"
        )

        // `-ui-testing` deliberately forces Photos read access to denied so the
        // Roll stays deterministic on simulators, so the kept frame cannot be
        // listed here. Confirm the viewfinder is live again instead.
        XCTAssertTrue(
            app.buttons["Capture photo"].waitForExistence(timeout: 10),
            "Keeping a frame should return to the live viewfinder"
        )
        attachScreenshot(named: "device-after-keep")
    }

    /// Captures the same scene through every color recipe, flash off and
    /// flash on, and attaches each review so the rendered stills can be
    /// compared against reference looks. Frames are discarded, not saved.
    func testPhysicalRecipeCaptureSheet() throws {
        // Thirteen launches and twenty-six captures for a manually inspected
        // contact sheet: opt in explicitly, e.g.
        // TEST_RUNNER_FILMY_RUN_CAPTURE_SHEET=1 xcodebuild ... -only-testing:FilmyCameraUITests/FilmyCameraUITests/testPhysicalRecipeCaptureSheet
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_CAPTURE_SHEET"] == "1",
            "Set FILMY_RUN_CAPTURE_SHEET=1 to capture the on-device recipe contact sheet"
        )
        app.terminate()
        let recipeIDs = [
            "provia-standard", "classic-chrome", "velvia-vivid", "astia-soft",
            "pro-neg-high", "pro-neg-standard", "eterna-cinema", "eterna-bleach-bypass",
            "classic-negative", "nostalgic-negative", "reala-ace", "acros-monochrome",
            "g7x-compact"
        ]

        for recipeID in recipeIDs {
            let recipeApp = XCUIApplication()
            recipeApp.launchArguments = ["-ui-testing", "-selectedRecipeID", recipeID]
            recipeApp.launch()
            recipeApp.tap()

            let shutter = recipeApp.buttons["Capture photo"]
            XCTAssertTrue(shutter.waitForExistence(timeout: 20), "\(recipeID): shutter")
            let flash = recipeApp.buttons["flash-control"]
            let hasFlash = flash.waitForExistence(timeout: 3)

            for wantsFlash in [false, true] {
                if hasFlash {
                    let target = wantsFlash ? "On" : "Off"
                    for _ in 0..<3 where (flash.value as? String) != target {
                        flash.tap()
                    }
                } else if wantsFlash {
                    continue
                }
                // Let exposure settle after a flash-mode change.
                _ = shutter.waitForExistence(timeout: 1)
                shutter.tap()
                let keepFrame = recipeApp.buttons["Keep frame"]
                XCTAssertTrue(keepFrame.waitForExistence(timeout: 40), "\(recipeID) flash=\(wantsFlash): review")
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "capture-\(recipeID)-flash-\(wantsFlash ? "on" : "off")"
                shot.lifetime = .keepAlways
                add(shot)
                recipeApp.buttons["Retake"].tap()
                XCTAssertTrue(shutter.waitForExistence(timeout: 15), "\(recipeID): back to viewfinder")
            }

            if hasFlash {
                for _ in 0..<3 where (flash.value as? String) != "Off" {
                    flash.tap()
                }
            }
            recipeApp.terminate()
        }
    }

    /// The G7 X profile renders flash captures differently. Turn the flash
    /// on, capture, and make sure the still reaches review, then discard it.
    func testPhysicalG7XFlashCaptureReachesReview() throws {
        app.terminate()

        let compactApp = XCUIApplication()
        compactApp.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "g7x-compact"
        ]
        compactApp.launch()
        defer { compactApp.terminate() }
        compactApp.tap()

        let shutter = compactApp.buttons["Capture photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20))
        XCTAssertTrue(compactApp.staticTexts["CAMERA PROFILE"].waitForExistence(timeout: 5))

        // The app only offers the control when the active camera has a flash,
        // so its absence means this hardware cannot exercise the flash path.
        let flash = compactApp.buttons["flash-control"]
        guard flash.waitForExistence(timeout: 5) else {
            throw XCTSkip("The active camera exposes no flash control on this device")
        }
        XCTAssertTrue(flash.isEnabled, "The flash control should be enabled on flash hardware")
        for _ in 0..<3 where (flash.value as? String) != "On" {
            flash.tap()
        }
        XCTAssertEqual(flash.value as? String, "On", "Flash must be On before the flash-aware capture")
        attachScreenshot(named: "device-g7x-flash-viewfinder")

        shutter.tap()
        let keepFrame = compactApp.buttons["Keep frame"]
        XCTAssertTrue(
            keepFrame.waitForExistence(timeout: 40),
            "A G7 X flash capture should reach the review sheet"
        )
        attachScreenshot(named: "device-g7x-flash-review")
        // A review that reached the sheet is not enough: the resolved capture
        // settings must confirm the flash fired, or the flash-aware G7 X
        // treatment never ran.
        XCTAssertTrue(
            compactApp.staticTexts["Full resolution · Flash fired"].waitForExistence(timeout: 5),
            "The review caption must confirm the flash fired: \(compactApp.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.contains("resolution") })"
        )

        let retake = compactApp.buttons["Retake"]
        assertMinimumHitTarget(retake, named: "Retake")
        retake.tap()
        XCTAssertTrue(
            compactApp.buttons["Capture photo"].waitForExistence(timeout: 10),
            "Retake should return to the live viewfinder"
        )

        if flash.exists, flash.isEnabled {
            for _ in 0..<3 where (flash.value as? String) != "Off" {
                flash.tap()
            }
        }
    }
    #endif

    /// Opt-in, non-destructive Roll acceptance on a provisioned physical iPad.
    /// The saved frame is intentionally retained in Photos and the local cache.
    func testPhysicalG7XSaveRollDetailAndShareAcceptance() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Roll capture and share acceptance requires a physical iPad")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
            "Set FILMY_RUN_PHOTOS_WRITE=1 to allow the test to keep a real photo"
        )
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_ROLL_QA"] == "1",
            "Set FILMY_RUN_ROLL_QA=1 to run the physical Roll acceptance flow"
        )

        app.terminate()
        let rollApp = XCUIApplication()
        // Deliberately omit -ui-testing: this exercises normal Photos access,
        // the real local fallback cache, and the real share controller.
        rollApp.launchArguments = ["-selectedRecipeID", "g7x-compact"]
        rollApp.launch()
        app = rollApp
        defer { rollApp.terminate() }

        try XCTSkipUnless(
            rollApp.frame.width >= 700,
            "The share-popover acceptance path requires a full-screen physical iPad"
        )

        let onboarding = rollApp.descendants(matching: .any)["onboarding-screen"]
        if onboarding.waitForExistence(timeout: 3) {
            let skip = rollApp.buttons["onboarding-skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
        }

        // Give the interruption monitor an interaction for a first-launch
        // camera prompt before requiring the live hardware shutter.
        rollApp.tap()
        let shutter = rollApp.buttons["Capture photo"]
        XCTAssertTrue(
            shutter.waitForExistence(timeout: 20) && shutter.isEnabled,
            "Normal app launch must reach a live physical camera"
        )
        XCTAssertTrue(rollApp.staticTexts["G7 X Compact"].waitForExistence(timeout: 5))
        attachScreenshot(named: "roll-qa-g7x-viewfinder")

        shutter.tap()
        let keepFrame = rollApp.buttons["Keep frame"]
        XCTAssertTrue(
            keepFrame.waitForExistence(timeout: 40),
            "G7 X capture must reach full-resolution review"
        )
        attachScreenshot(named: "roll-qa-g7x-review")
        keepFrame.tap()
        // Invokes the permission monitor if add-only Photos access is being
        // requested for this normal-app save.
        rollApp.tap()

        let savedToast = rollApp.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            savedToast.waitForExistence(timeout: 20),
            "The G7 X frame must be accepted by Photos before Roll QA continues"
        )

        let openRoll = rollApp.buttons["Open roll"]
        XCTAssertTrue(openRoll.waitForExistence(timeout: 10))
        openRoll.tap()
        XCTAssertTrue(rollApp.staticTexts["Roll"].waitForExistence(timeout: 10))

        let sourceSummary = rollApp.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Newest first. Source:'")
        ).firstMatch
        XCTAssertTrue(
            sourceSummary.waitForExistence(timeout: 30),
            "The Roll must publish whether the saved frame came from Photos or local cache"
        )
        let savedFrame = rollApp.buttons.matching(
            NSPredicate(format: "label == 'Photo in your gallery, G7 X Compact'")
        ).firstMatch
        XCTAssertTrue(
            savedFrame.waitForExistence(timeout: 30),
            "The newly saved G7 X frame must populate the Roll"
        )
        attachScreenshot(named: "roll-qa-populated-roll")
        savedFrame.tap()

        let photo = rollApp.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Photo'")
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "Saved frame detail must load")
        let share = rollApp.buttons["Share frame"]
        XCTAssertTrue(
            waitUntil(timeout: 20) { share.exists && share.isEnabled },
            "The loaded saved frame must be shareable"
        )
        XCTAssertEqual(photo.value as? String, "Fit to screen")
        attachScreenshot(named: "roll-qa-detail-fit")

        photo.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (photo.value as? String)?.hasPrefix("Zoomed ") == true
            },
            "Pinching must zoom the Roll detail image"
        )
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55)).press(
            forDuration: 0.1,
            thenDragTo: photo.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.35))
        )
        XCTAssertTrue(
            (photo.value as? String)?.hasPrefix("Zoomed ") == true,
            "Panning must keep the detail image zoomed"
        )
        attachScreenshot(named: "roll-qa-detail-zoomed-panned")

        photo.doubleTap()
        XCTAssertTrue(
            waitUntil(timeout: 5) { (photo.value as? String) == "Fit to screen" },
            "Double tap must reset zoom and pan"
        )
        attachScreenshot(named: "roll-qa-detail-reset")

        let existingSheetCount = rollApp.sheets.count
        share.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) { rollApp.sheets.count > existingSheetCount },
            "Share frame must present the iPad activity sheet"
        )
        let shareSheet = try XCTUnwrap(
            rollApp.sheets.allElementsBoundByIndex.first {
                !$0.buttons["Share frame"].exists
            },
            "Could not identify the presented activity sheet"
        )
        attachScreenshot(named: "roll-qa-ipad-share-sheet")
        shareSheet.swipeDown(velocity: .fast)
        XCTAssertTrue(
            waitForDisappearance(shareSheet, timeout: 10),
            "Cancelling the activity sheet must return to frame detail"
        )
        XCTAssertTrue(share.exists, "Frame detail must remain open after cancelling share")
        #endif
    }

    #if targetEnvironment(simulator)
    func testSimulatorFallbackExposesReadableStateWithoutPreviewAction() throws {
        XCTAssertTrue(app.staticTexts["Preview mode"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["Shoot this look on an iPhone or iPad."].waitForExistence(timeout: 5)
        )

        let cameraPreview = app.descendants(matching: .any)["camera-preview"]
        XCTAssertFalse(
            cameraPreview.isHittable,
            "The unavailable camera preview must not remain an actionable target"
        )
    }

    func testAccessibilitySizeCameraShellKeepsRecipeControlsReachable() throws {
        let accessibilityApp = MainActor.assumeIsolated {
            let accessibilityApp = XCUIApplication()
            accessibilityApp.launchArguments = [
                "-ui-testing",
                "-selectedRecipeID",
                "classic-chrome",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            accessibilityApp.launch()
            return accessibilityApp
        }
        defer { accessibilityApp.terminate() }

        XCTAssertTrue(accessibilityApp.staticTexts["RECIPE"].waitForExistence(timeout: 8))

        let roll = accessibilityApp.buttons["Open roll"]
        assertMinimumHitTarget(roll, named: "Accessibility-size Roll")

        let cameraTab = accessibilityApp.buttons["camera-tab"]
        assertMinimumHitTarget(cameraTab, named: "Accessibility-size Camera tab")
        XCTAssertLessThan(
            roll.frame.maxY,
            cameraTab.frame.minY,
            "Accessibility-size camera actions must remain above the tab bar"
        )

        let tune = accessibilityApp.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Tune '")
        ).firstMatch
        assertMinimumHitTarget(tune, named: "Accessibility-size Tune")

        let recipePicker = accessibilityApp.descendants(matching: .any)["recipe-picker"]
        XCTAssertTrue(recipePicker.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            recipePicker.frame.height,
            96,
            "Compact recipe rail should not expand into an empty panel"
        )
        XCTAssertLessThan(
            recipePicker.frame.maxY,
            roll.frame.minY,
            "Compact recipe rail must remain above the camera actions"
        )
        XCTAssertLessThanOrEqual(
            roll.frame.minY - recipePicker.frame.maxY,
            32,
            "The compact recipe rail should remain visually connected to its actions"
        )

        let captureNotice = accessibilityApp.staticTexts["Capture on iPhone or iPad"]
        XCTAssertTrue(captureNotice.waitForExistence(timeout: 5))
        attachScreenshot(named: "accessibility-camera-shell-bounded")
    }

    func testMonochromeEditorHidesNoOpColorControls() throws {
        app.terminate()

        let monochromeApp = XCUIApplication()
        monochromeApp.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "acros-neutral-filter"
        ]
        monochromeApp.launch()
        defer { monochromeApp.terminate() }

        let tune = monochromeApp.buttons["Tune Neutral Monochrome"]
        XCTAssertTrue(tune.waitForExistence(timeout: 8))
        tune.tap()

        XCTAssertTrue(monochromeApp.staticTexts["Monochrome recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            monochromeApp.sliders["Color"].exists,
            "Monochrome recipes should not expose a saturation slider that cannot affect the render"
        )
        XCTAssertFalse(monochromeApp.descendants(matching: .any)["recipe-choice-Color Chrome"].exists)
        XCTAssertFalse(monochromeApp.descendants(matching: .any)["fx-blue-control"].exists)
    }

    func testViewfinderFirstChromePreviewKeepsCameraQuiet() throws {
        let previewApp = MainActor.assumeIsolated {
            let previewApp = XCUIApplication()
            previewApp.launchArguments = [
                "-ui-testing",
                "-ui-testing-viewfinder-chrome",
                "-selectedRecipeID",
                "classic-chrome"
            ]
            previewApp.launch()
            return previewApp
        }
        defer { previewApp.terminate() }

        XCTAssertTrue(previewApp.staticTexts["RECIPE"].waitForExistence(timeout: 8))

        let roll = previewApp.buttons["Open roll"]
        assertMinimumHitTarget(roll, named: "Viewfinder preview Roll")

        let controlsToggle = previewApp.buttons["Show camera controls"]
        assertMinimumHitTarget(controlsToggle, named: "Viewfinder preview controls toggle")

        let capture = previewApp.buttons["Capture unavailable in Preview mode"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        XCTAssertFalse(capture.isEnabled, "Simulator preview must not expose a fake capture action")
        XCTAssertGreaterThanOrEqual(capture.frame.width, 44)
        XCTAssertGreaterThanOrEqual(capture.frame.height, 44)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "viewfinder-first-chrome-preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    #endif

    func testGalleryAndSettingsNavigation() throws {
        let gallery = app.buttons["roll-tab"]
        assertMinimumHitTarget(gallery, named: "Roll")
        gallery.tap()

        XCTAssertTrue(app.staticTexts["Photo access is off"].waitForExistence(timeout: 5))
        attachScreenshot(named: "gallery-empty-state")

        let settings = app.buttons["settings-tab"]
        assertMinimumHitTarget(settings, named: "Settings tab")
        settings.tap()

        let settingsHeading = app.staticTexts["Settings"]
        XCTAssertTrue(settingsHeading.waitForExistence(timeout: 5))

        let hapticFeedback = app.switches["Haptic feedback"]
        XCTAssertTrue(hapticFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(hapticFeedback.isEnabled)

        XCTAssertFalse(
            app.buttons["camera-permission-request"].exists,
            "Simulator-safe mode must not expose a direct camera permission prompt"
        )

        let privacyPolicy = app.descendants(matching: .any)["privacy-policy-link"]
        scrollToHittable(privacyPolicy, in: app)
        assertMinimumHitTarget(privacyPolicy, named: "Privacy Policy")

        let support = app.descendants(matching: .any)["support-link"]
        scrollToHittable(support, in: app)
        assertMinimumHitTarget(support, named: "Contact Support")

        let photosPermission = app.buttons["photos-permission-settings"]
        scrollBackToHittable(photosPermission, in: app)
        assertMinimumHitTarget(photosPermission, named: "Photos permission settings")

        let photosSavePermission = app.buttons["photos-save-permission-settings"]
        scrollBackToHittable(photosSavePermission, in: app)
        assertMinimumHitTarget(photosSavePermission, named: "Photos save permission settings")

        let clearCache = app.buttons["clear-local-cache"]
        XCTAssertTrue(clearCache.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(clearCache.frame.width, 44, "Clear local cache needs a 44pt width")
        XCTAssertGreaterThanOrEqual(clearCache.frame.height, 44, "Clear local cache needs a 44pt height")
        attachScreenshot(named: "settings")
    }

    func testEveryTopLevelPageCanReturnToCamera() throws {
        let gallery = app.buttons["roll-tab"]
        gallery.tap()

        let galleryBack = app.buttons["roll-back-to-camera"]
        returnToMainCamera(using: galleryBack, named: "Roll back to camera")

        let settings = app.buttons["settings-tab"]
        settings.tap()

        let settingsBack = app.buttons["settings-back-to-camera"]
        returnToMainCamera(using: settingsBack, named: "Settings back to camera")

        let controlsToggle = app.buttons["camera-chrome-toggle"]
        if controlsToggle.waitForExistence(timeout: 2), controlsToggle.label == "Show camera controls" {
            controlsToggle.tap()
        }

        let mutedColor = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Muted Color'")
        ).firstMatch
        assertMinimumHitTarget(mutedColor, named: "Muted Color recipe")
        mutedColor.tap()

        let tune = app.buttons["Tune Muted Color"]
        assertMinimumHitTarget(tune, named: "Open recipe detail")
        tune.tap()

        let recipeBack = app.buttons["recipe-back-to-camera"]
        returnToMainCamera(using: recipeBack, named: "Recipe detail back to camera")
    }

    private func returnToMainCamera(using backButton: XCUIElement, named: String) {
        assertMinimumHitTarget(backButton, named: named)
        backButton.tap()

        if !waitForDisappearance(backButton, timeout: 2), backButton.exists, backButton.isHittable {
            backButton.tap()
        }

        XCTAssertTrue(
            waitForDisappearance(backButton, timeout: 5),
            named + " should leave its source page"
        )
        XCTAssertTrue(app.buttons["camera-tab"].waitForExistence(timeout: 5))
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return condition()
    }

    func testRecipeFirstOnboardingFlow() throws {
        let onboardingApp = MainActor.assumeIsolated {
            let onboardingApp = XCUIApplication()
            onboardingApp.launchArguments = ["-ui-testing-onboarding"]
            onboardingApp.launch()
            return onboardingApp
        }

        XCTAssertTrue(onboardingApp.staticTexts["Start with a feeling."].waitForExistence(timeout: 8))
        let firstContinue = onboardingApp.buttons["Continue"]
        assertMinimumHitTarget(firstContinue, named: "Onboarding continue")

        firstContinue.tap()
        XCTAssertTrue(onboardingApp.staticTexts["See the mood as you compose."].waitForExistence(timeout: 5))
        let secondContinue = onboardingApp.buttons["Continue"]
        assertMinimumHitTarget(secondContinue, named: "Onboarding continue on page two")
        secondContinue.tap()
        XCTAssertTrue(onboardingApp.staticTexts["Save the finished photo."].waitForExistence(timeout: 5))
        let openCamera = onboardingApp.buttons["Open camera"]
        assertMinimumHitTarget(openCamera, named: "Onboarding open camera")
        openCamera.tap()

        XCTAssertTrue(onboardingApp.buttons["Open roll"].waitForExistence(timeout: 8))
    }

    private func assertMinimumHitTarget(_ element: XCUIElement, named: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), named + " should exist")
        XCTAssertTrue(element.isHittable, named + " should be hittable")
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, named + " needs a 44pt width")
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, named + " needs a 44pt height")
    }

    private func assertMinimumAccessibilityFrame(_ element: XCUIElement, named: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), named + " should exist")
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, named + " needs a 44pt width")
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, named + " needs a 44pt height")
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let recipeDetailScroll = app.scrollViews["recipe-detail-scroll"]
        let scrollView = recipeDetailScroll.exists ? recipeDetailScroll : app.scrollViews.firstMatch
        for _ in 0..<16 where !element.isHittable {
            if scrollView.exists {
                scrollView.swipeUp(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
    }

    private func scrollBackToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let recipeDetailScroll = app.scrollViews["recipe-detail-scroll"]
        let scrollView = recipeDetailScroll.exists ? recipeDetailScroll : app.scrollViews.firstMatch
        for _ in 0..<16 where !element.isHittable {
            if scrollView.exists {
                scrollView.swipeDown(velocity: .slow)
            } else {
                app.swipeDown(velocity: .slow)
            }
        }
    }

    // MARK: - Lifecycle and resilience

    /// True when the shutter is live on camera hardware; false on Simulator,
    /// where the viewfinder shows the preview-mode placeholder instead.
    private func waitForLiveShutter(in target: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let shutter = target.buttons["Capture photo"]
        guard shutter.waitForExistence(timeout: timeout) else { return false }
        return shutter.isEnabled
    }

    private func waitForCameraShell(in target: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        // The Roll thumbnail sits in the capture row of every camera layout,
        // on hardware and in Simulator preview mode alike.
        target.buttons["Open roll"].waitForExistence(timeout: timeout)
    }

    func testBackgroundingAndForegroundingRestoresTheViewfinder() throws {
        XCTAssertTrue(waitForCameraShell(in: app), "The camera shell should be up before backgrounding")
        let isPhysical = waitForLiveShutter(in: app, timeout: 15)

        for round in 1...2 {
            XCUIDevice.shared.press(.home)
            // Let the scene reach the background so the session really stops.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
            app.activate()
            XCTAssertTrue(
                waitForCameraShell(in: app),
                "Round \(round): the camera shell must come back after foregrounding"
            )
            if isPhysical {
                XCTAssertTrue(
                    waitForLiveShutter(in: app, timeout: 10),
                    "Round \(round): the viewfinder must be live again within 10 s of foregrounding"
                )
            }
        }
        attachScreenshot(named: "lifecycle-after-foreground")
    }

    func testTabRoundTripReturnsToTheViewfinderQuickly() throws {
        XCTAssertTrue(waitForCameraShell(in: app))
        let isPhysical = waitForLiveShutter(in: app, timeout: 15)

        for tab in ["roll-tab", "settings-tab"] {
            let destination = app.buttons[tab]
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "\(tab) should be in the dock")
            destination.tap()
            let cameraTab = app.buttons["camera-tab"]
            XCTAssertTrue(cameraTab.waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
            cameraTab.tap()
            XCTAssertTrue(waitForCameraShell(in: app), "Returning from \(tab) must show the camera shell")
            if isPhysical {
                let start = Date()
                XCTAssertTrue(
                    waitForLiveShutter(in: app, timeout: 8),
                    "The viewfinder must be live again after \(tab)"
                )
                let elapsed = Date().timeIntervalSince(start)
                XCTAssertLessThan(elapsed, 4, "A quick return from \(tab) should reuse the warm session (took \(elapsed) s)")
            }
        }
    }

    func testRapidRecipeSwitchingKeepsTheViewfinderResponsive() throws {
        XCTAssertTrue(waitForCameraShell(in: app))
        let isPhysical = waitForLiveShutter(in: app, timeout: 15)
        let candidates = [
            "recipe-provia-standard", "recipe-velvia-vivid", "recipe-astia-soft",
            "recipe-classic-chrome", "recipe-classic-negative", "recipe-g7x-compact",
            "recipe-nostalgic-negative", "recipe-eterna-cinema", "recipe-acros-monochrome"
        ]
        var taps = 0
        for _ in 0..<3 {
            for identifier in candidates {
                let swatch = app.buttons[identifier]
                guard swatch.exists, swatch.isHittable else { continue }
                swatch.tap()
                taps += 1
            }
        }
        XCTAssertGreaterThanOrEqual(taps, 6, "The rail should expose several recipes to switch between")
        XCTAssertTrue(waitForCameraShell(in: app, timeout: 5), "The shell must survive rapid recipe switching")
        if isPhysical {
            XCTAssertTrue(waitForLiveShutter(in: app, timeout: 5), "The viewfinder must stay live while switching recipes")
            app.buttons["Capture photo"].tap()
            let retake = app.buttons["Retake"]
            XCTAssertTrue(retake.waitForExistence(timeout: 30), "A capture after rapid switching must still reach review")
            retake.tap()
            XCTAssertTrue(waitForLiveShutter(in: app, timeout: 8))
        }
        attachScreenshot(named: "lifecycle-after-rapid-switching")
    }

    func testPhysicalRetakeReturnsToALiveViewfinderInstantly() throws {
        guard waitForLiveShutter(in: app, timeout: 20) else {
            throw XCTSkip("Requires camera hardware")
        }
        for round in 1...3 {
            app.buttons["Capture photo"].tap()
            let retake = app.buttons["Retake"]
            XCTAssertTrue(retake.waitForExistence(timeout: 30), "Round \(round): capture should reach review")
            retake.tap()
            let start = Date()
            XCTAssertTrue(waitForLiveShutter(in: app, timeout: 8), "Round \(round): the viewfinder must return after Retake")
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 3, "Round \(round): Retake should reuse the warm session (took \(elapsed) s)")
        }
    }

    /// Cold-launch benchmark on hardware. The number lands in the result
    /// bundle; the assertion only guards against a launch that never settles.
    func testPhysicalLaunchPerformance() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Launch timing is only meaningful on camera hardware")
        #else
        // Five cold launches: opt in explicitly, e.g.
        // TEST_RUNNER_FILMY_RUN_PERF=1 xcodebuild ... -only-testing:FilmyCameraUITests/FilmyCameraUITests/testPhysicalLaunchPerformance
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1",
            "Set FILMY_RUN_PERF=1 to run the on-device launch benchmark"
        )
        guard waitForLiveShutter(in: app, timeout: 20) else {
            throw XCTSkip("Launch timing is only meaningful on camera hardware")
        }
        app.terminate()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let launched = XCUIApplication()
            launched.launchArguments = ["-ui-testing", "-selectedRecipeID", "classic-chrome"]
            launched.launch()
            XCTAssertTrue(launched.buttons["Open roll"].waitForExistence(timeout: 15))
            launched.terminate()
        }
        #endif
    }


    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
