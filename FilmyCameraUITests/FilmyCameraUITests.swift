import XCTest

@MainActor
final class FilmyCameraUITests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!
    private nonisolated(unsafe) var defaultsSuiteName = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        let suiteName = "FilmyCameraUITests.\(UUID().uuidString)"
        defaultsSuiteName = suiteName
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
            launchedApp.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = suiteName
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

    func testProControlsAdaptAndReturnToCamera() throws {
        let pro = app.buttons["pro-controls-button"]
        let showControls = app.buttons["Show camera controls"]
        if showControls.waitForExistence(timeout: 2) { showControls.tap() }
        let rail = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["camera-utility-rail", "g7x-capture-controls"]
        )).firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 8))
        for _ in 0..<4 where !pro.exists || !pro.isHittable { rail.swipeLeft() }
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        assertMinimumHitTarget(pro, named: "Pro controls")
        pro.tap()
        let done = app.buttons["manual-controls-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        assertMinimumHitTarget(done, named: "Done with Pro controls")

        #if targetEnvironment(simulator)
        XCTAssertTrue(app.descendants(matching: .any)["manual-controls-unavailable"].exists)
        XCTAssertFalse(app.sliders["manual-iso-slider"].exists,
                       "Simulator must not pretend to expose real sensor control")
        XCTAssertFalse(app.buttons["manual-controls-reset"].isEnabled)
        #else
        let exposure = app.buttons["manual-exposure-manual"]
        if !exposure.isEnabled {
            let lenses = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'manual-lens-'"))
            for lens in lenses.allElementsBoundByIndex {
                scrollToHittable(lens, in: app)
                lens.tap()
                if waitUntil(timeout: 3, condition: { exposure.exists && exposure.isEnabled }) { break }
            }
        }
        XCTAssertTrue(exposure.isEnabled, "A supported physical lens must expose manual exposure")
        scrollToHittable(exposure, in: app)
        exposure.tap()
        let iso = app.sliders["manual-iso-slider"]
        XCTAssertTrue(iso.waitForExistence(timeout: 8))
        scrollToHittable(iso, in: app)
        XCTAssertTrue(waitUntil(timeout: 5, condition: { iso.isEnabled }))
        iso.adjust(toNormalizedSliderPosition: 0.25)
        XCTAssertTrue(waitUntil(timeout: 5, condition: { iso.isEnabled }))
        let whiteBalance = app.buttons["manual-white-balance-manual"]
        if whiteBalance.isEnabled {
            scrollToHittable(whiteBalance, in: app)
            whiteBalance.tap()
            XCTAssertTrue(app.sliders["manual-kelvin-slider"].waitForExistence(timeout: 8))
        }
        #endif

        attachScreenshot(named: "pro-controls-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable, "Pro controls must remain dismissible in landscape")
        attachScreenshot(named: "pro-controls-landscape")
        #if !targetEnvironment(simulator)
        let reset = app.buttons["manual-controls-reset"]
        scrollToHittable(reset, in: app)
        XCTAssertTrue(waitUntil(timeout: 5, condition: { reset.isEnabled }))
        reset.tap()
        XCTAssertTrue(waitUntil(timeout: 8, condition: {
            app.buttons["manual-exposure-auto"].value as? String == "Selected"
                && app.buttons["manual-white-balance-auto"].value as? String == "Selected"
                && app.buttons["manual-focus-auto"].value as? String == "Selected"
        }))
        #endif
        done.tap()
        XCTAssertFalse(app.buttons["manual-controls-done"].exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
        #if !targetEnvironment(simulator)
        XCTAssertTrue(waitForLiveShutter(in: app), "Closing Pro controls must return to fresh preview frames")
        #endif
    }

    func testCameraShellAndRecipeDetails() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(waitForLiveShutter(in: app), "The portrait preview must render fresh frames")
        attachScreenshot(named: "camera-portrait-live")
        #endif
        assertMinimumHitTarget(app.buttons["recipe-menu"], named: "Current look")
        assertMinimumHitTarget(app.buttons["import-photo"], named: "Import photo")
        XCTAssertTrue(app.buttons["Open roll"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["camera-tab"].exists, "The camera should have one control area")
        XCTAssertFalse(app.descendants(matching: .any)["recipe-picker"].exists)
        openRecipeDrawer(in: app)
        attachScreenshot(named: "camera-look-drawer")

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

        let information = app.buttons["recipe-info-toggle"]
        scrollToHittable(information, in: app)
        information.tap()
        XCTAssertEqual(
            information.value as? String,
            "Expanded",
            "About this look must expand before reference content is inspected"
        )
        attachScreenshot(named: "recipe-details-info-expanded")
        let referenceCard = app.descendants(matching: .any)["public-reference-settings"]
        scrollToHittable(app.staticTexts["PUBLIC REFERENCE"], in: app)
        XCTAssertTrue(referenceCard.exists)
        XCTAssertTrue(
            app.staticTexts["PUBLIC REFERENCE"].waitForExistence(timeout: 5),
            "Recipe details should expose the public reference settings"
        )
        XCTAssertTrue(app.staticTexts["DR200"].exists)
        attachScreenshot(named: "recipe-details")
    }

    func testExpandedRecipeCanLaunchSelected() throws {
        app.terminate()

        let expandedApp = makeApplication()
        expandedApp.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "nostalgic-summer"
        ]
        expandedApp.launch()

        openRecipeDrawer(in: expandedApp)
        XCTAssertTrue(expandedApp.buttons["Tune Nostalgic Summer"].waitForExistence(timeout: 5))

        let selectedRecipe = expandedApp.buttons["recipe-nostalgic-summer"]
        XCTAssertTrue(selectedRecipe.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedRecipe.value as? String, "Selected")
    }

    func testG7XModeExposesDedicatedCompactProfile() throws {
        app.terminate()

        let compactApp = makeApplication()
        compactApp.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "g7x-compact"
        ]
        compactApp.launch()
        defer { compactApp.terminate() }

        openRecipeDrawer(in: compactApp)
        XCTAssertTrue(compactApp.staticTexts["CAMERA PROFILE"].waitForExistence(timeout: 8))

        let selectedRecipe = compactApp.buttons["recipe-g7x-compact"]
        assertMinimumAccessibilityFrame(selectedRecipe, named: "G7 X recipe")
        assertContained(selectedRecipe, in: compactApp, named: "G7 X recipe")
        let film = compactApp.buttons["recipe-classic-chrome"]
        assertMinimumHitTarget(film, named: "Muted Color recipe")
        film.tap()
        XCTAssertTrue(compactApp.buttons["Tune Muted Color"].waitForExistence(timeout: 5))
        #if targetEnvironment(simulator)
        // iPadOS 26 Simulator can report the first tile of a nested row as
        // non-hittable despite correct visible bounds and working taps.
        // Exercise its real selection action instead of trusting that flag.
        let screen = compactApp.frame
        let tile = selectedRecipe.frame
        compactApp.coordinate(withNormalizedOffset: CGVector(
            dx: (tile.midX - screen.minX) / screen.width,
            dy: (tile.midY - screen.minY) / screen.height
        )).tap()
        #else
        assertMinimumHitTarget(selectedRecipe, named: "G7 X recipe")
        selectedRecipe.tap()
        #endif
        XCTAssertTrue(compactApp.buttons["Tune G7 X Compact"].waitForExistence(timeout: 5),
                      "Tapping the visible G7 X tile must select its camera profile")
        XCTAssertEqual(selectedRecipe.value as? String, "Selected")

        let tune = compactApp.buttons["Tune G7 X Compact"]
        assertMinimumHitTarget(tune, named: "Tune G7 X profile")
        tune.tap()

        let reset = compactApp.buttons["Reset recipe controls"]
        scrollToHittable(reset, in: compactApp)
        reset.tap()

        let information = compactApp.buttons["recipe-info-toggle"]
        scrollToHittable(information, in: compactApp)
        information.tap()
        XCTAssertEqual(information.value as? String, "Expanded")
        attachScreenshot(named: "g7x-details-info-expanded")
        let profile = compactApp.descendants(matching: .any)["g7x-profile-details"]
        scrollToHittable(compactApp.staticTexts["G7 X PROFILE"], in: compactApp)
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(compactApp.staticTexts["G7 X PROFILE"].exists)
        XCTAssertTrue(compactApp.staticTexts["Dedicated compact-digital pipeline"].exists)
        attachScreenshot(named: "g7x-profile-details")

        let done = compactApp.buttons.matching(NSPredicate(
            format: "label == 'Done editing G7 X Compact' OR label == 'Apply changes to G7 X Compact'"
        )).firstMatch
        assertMinimumHitTarget(done, named: "G7 X editor dismissal")
        done.tap()
        XCTAssertTrue(
            waitForDisappearance(done, timeout: 5),
            "Reset G7 X controls should commit the built-in preset before test exit"
        )
    }

    func testG7XModeKeepsCompactCaptureControlsOneTapAway() throws {
        app.terminate()

        let compactApp = makeApplication()
        compactApp.launchArguments = [
            "-ui-testing",
            "-ui-testing-viewfinder-chrome",
            "-selectedRecipeID",
            "g7x-compact"
        ]
        compactApp.launch()
        defer { compactApp.terminate() }

        assertMinimumHitTarget(compactApp.buttons["recipe-menu"], named: "G7 X current look")
        XCTAssertFalse(compactApp.descendants(matching: .any)["recipe-picker"].exists)
        let tools = compactApp.buttons["camera-chrome-toggle"]
        assertMinimumHitTarget(tools, named: "Camera controls")
        tools.tap()

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

        XCTAssertFalse(compactApp.descendants(matching: .any)["recipe-picker"].exists)
        attachScreenshot(named: "g7x-quick-capture-controls")
    }

    func testRecipeEditorBackDiscardsDraftChanges() throws {
        openRecipeDetail(for: "classic-chrome", in: app, tuneLabel: "Tune Muted Color")

        let exposure = app.sliders["Exposure"]
        // Native UISlider reports a 31pt accessibility node inside its larger
        // row. Verify reachability and actual adjustment; the 44pt button
        // geometry helper does not describe a native slider's touch behavior.
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        XCTAssertTrue(exposure.isEnabled && exposure.isHittable)
        let originalValue = try XCTUnwrap(exposure.value as? String)
        exposure.adjust(toNormalizedSliderPosition: originalValue.contains("-") ? 0.9 : 0.1)
        XCTAssertNotEqual(
            exposure.value as? String,
            originalValue,
            "Changing a recipe control should create a distinct draft"
        )

        let back = app.buttons["recipe-back-to-camera"]
        assertMinimumHitTarget(back, named: "Cancel recipe editing")
        back.tap()
        XCTAssertTrue(waitForDisappearance(back, timeout: 5))

        openRecipeDetail(for: "classic-chrome", in: app, tuneLabel: "Tune Muted Color")
        XCTAssertEqual(
            app.sliders["Exposure"].value as? String,
            originalValue,
            "Leaving recipe details with Back must discard the draft"
        )
        app.buttons["recipe-back-to-camera"].tap()
    }

    func testRecipeEditorResetAndApplyPersistsBuiltInValues() throws {
        openRecipeDetail(for: "classic-chrome", in: app, tuneLabel: "Tune Muted Color")

        let exposure = app.sliders["Exposure"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        XCTAssertTrue(exposure.isEnabled && exposure.isHittable)
        let originalValue = try XCTUnwrap(exposure.value as? String)
        exposure.adjust(toNormalizedSliderPosition: 0.9)
        let apply = app.buttons["Apply changes to Muted Color"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5), "A changed recipe should offer Apply")
        let customizedValue = try XCTUnwrap(exposure.value as? String)
        XCTAssertNotEqual(customizedValue, originalValue, "The edited value should differ from the built-in baseline")
        apply.tap()
        XCTAssertTrue(waitForDisappearance(apply, timeout: 5))

        app.terminate()
        let relaunchedAfterApply = makeApplication()
        relaunchedAfterApply.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "classic-chrome"
        ]
        relaunchedAfterApply.launch()
        app = relaunchedAfterApply
        app.tap()
        XCTAssertTrue(app.buttons["Open roll"].waitForExistence(timeout: 10))

        openRecipeDetail(for: "classic-chrome", in: app, tuneLabel: "Tune Muted Color")
        XCTAssertEqual(
            app.sliders["Exposure"].value as? String,
            customizedValue,
            "Applying a changed recipe must persist its controls across relaunch"
        )

        let reset = app.buttons["Reset recipe controls"]
        scrollToHittable(reset, in: app)
        reset.tap()
        let resetValue = try XCTUnwrap(app.sliders["Exposure"].value as? String)
        XCTAssertEqual(resetValue, originalValue, "Reset should restore the built-in control value")
        let resetApply = app.buttons["Apply changes to Muted Color"]
        assertMinimumHitTarget(resetApply, named: "Apply reset recipe")
        resetApply.tap()
        XCTAssertTrue(waitForDisappearance(resetApply, timeout: 5))

        app.terminate()
        let relaunchedAfterReset = makeApplication()
        relaunchedAfterReset.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "classic-chrome"
        ]
        relaunchedAfterReset.launch()
        app = relaunchedAfterReset
        app.tap()
        XCTAssertTrue(app.buttons["Open roll"].waitForExistence(timeout: 10))

        openRecipeDetail(for: "classic-chrome", in: app, tuneLabel: "Tune Muted Color")
        XCTAssertEqual(
            app.sliders["Exposure"].value as? String,
            originalValue,
            "Applying Reset must persist built-in controls across relaunch"
        )
        assertMinimumHitTarget(app.buttons["Done editing Muted Color"], named: "Done recipe editing")
        app.buttons["Done editing Muted Color"].tap()
    }

    func testOnboardingSkipReachesCameraWithCompactLookDiscoverable() throws {
        app.terminate()

        let onboardingApp = makeApplication()
        onboardingApp.launchArguments = ["-ui-testing-onboarding", "-selectedRecipeID", "g7x-compact"]
        onboardingApp.launch()
        defer { onboardingApp.terminate() }

        // The visible label is more stable than the SwiftUI identifier here;
        // on some OS versions an ancestor replaces the descendant ID.
        let skip = onboardingApp.buttons["Skip"]
        assertMinimumHitTarget(skip, named: "Onboarding skip")
        skip.tap()

        XCTAssertTrue(onboardingApp.buttons["Open roll"].waitForExistence(timeout: 8))
        assertMinimumHitTarget(onboardingApp.buttons["recipe-menu"], named: "Current look after onboarding")
        openRecipeDrawer(in: onboardingApp)
        XCTAssertTrue(onboardingApp.staticTexts["CAMERA PROFILE"].waitForExistence(timeout: 5))
        XCTAssertTrue(onboardingApp.descendants(matching: .any)["recipe-group-compact"].exists)
        let g7x = onboardingApp.buttons["recipe-g7x-compact"]
        assertMinimumAccessibilityFrame(g7x, named: "G7 X recipe after onboarding")
        XCTAssertTrue(g7x.exists, "G7 X Compact should be discoverable from the first look drawer")
    }

    func testLandscapeCameraShell() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        #if !targetEnvironment(simulator)
        XCTAssertTrue(waitForLiveShutter(in: app), "The landscape preview must render fresh frames")
        #endif

        let currentLook = app.buttons["recipe-menu"]
        let roll = app.buttons["Open roll"]
        let importPhoto = app.buttons["import-photo"]
        for (element, name) in [(currentLook, "Current look"), (roll, "Roll"), (importPhoto, "Import")] {
            assertMinimumHitTarget(element, named: "Landscape " + name)
            assertContained(element, in: app, named: name)
        }
        XCTAssertFalse(app.buttons["camera-tab"].exists)
        attachScreenshot(named: "camera-landscape")
        openRecipeDrawer(in: app)
        let tune = app.buttons["Tune Muted Color"]
        let close = app.buttons["recipe-drawer-close"]
        assertMinimumHitTarget(tune, named: "Landscape Tune")
        assertMinimumHitTarget(close, named: "Landscape close picker")
        assertContained(tune, in: app, named: "Tune")
        assertContained(close, in: app, named: "Close picker")
        XCTAssertFalse(tune.frame.intersects(close.frame))
        attachScreenshot(named: "camera-landscape-look-drawer")
        close.tap()
        XCTAssertFalse(app.descendants(matching: .any)["recipe-picker"].exists)
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
            "A capture should reach the review screen"
        )
        XCTAssertTrue(app.buttons["Retake"].exists)
        attachScreenshot(named: "device-capture-review")

        let compare = app.buttons["review-compare-original"]
        let lookPicker = app.buttons["review-look-picker"]
        assertMinimumHitTarget(compare, named: "Original comparison")
        assertMinimumHitTarget(lookPicker, named: "Review look picker")
        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { compare.value as? String == "Original" })
        lookPicker.tap()
        let monochrome = app.buttons["review-look-acros-monochrome"]
        XCTAssertTrue(monochrome.waitForExistence(timeout: 5))
        monochrome.tap()
        let photo = app.descendants(matching: .any)["review-image"]
        XCTAssertTrue(waitUntil(timeout: 30) {
            photo.label.contains("Fine Monochrome") && keepFrame.isEnabled
        }, "A new look must finish rendering on the captured source before Save")
        XCTAssertEqual(compare.value as? String, "Look")

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(waitUntil(timeout: 10) { app.frame.width > app.frame.height })
        for control in [compare, lookPicker, keepFrame] {
            assertMinimumHitTarget(control, named: "Landscape review control")
            XCTAssertTrue(app.frame.contains(control.frame), "Review controls must fit inside the screen")
        }
        attachScreenshot(named: "device-review-monochrome-landscape")
        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { compare.value as? String == "Original" })

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
        XCTAssertTrue(savedToast.label.contains("Fine Monochrome"), "Save must keep the chosen look while Original is visible")
        XCTAssertTrue(
            waitForDisappearance(keepFrame, timeout: 5),
            "Keeping a frame should dismiss the review screen"
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

    /// Exercises the add-only fallback through a normal save and relaunch.
    /// Configure this app in Settings for Add Photos Only first.
    func testPhysicalAddOnlySaveAndRelaunchShowsLocalRoll() throws {
        try skipUnlessPhotosWritesAreAllowed()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_ADD_ONLY_CACHE_QA"] == "1",
            "Set FILMY_RUN_ADD_ONLY_CACHE_QA=1 after configuring Add Photos Only access"
        )

        app.terminate()
        let cacheApp = makeApplication()
        cacheApp.launchArguments = ["-selectedRecipeID", "g7x-compact"]
        cacheApp.launch()
        app = cacheApp
        defer { cacheApp.terminate() }

        let onboarding = cacheApp.descendants(matching: .any)["onboarding-screen"]
        if onboarding.waitForExistence(timeout: 3) {
            let skip = cacheApp.buttons["Skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
        }
        cacheApp.tap()

        let openRoll = cacheApp.buttons["Open roll"]
        XCTAssertTrue(openRoll.waitForExistence(timeout: 10))
        openRoll.tap()
        XCTAssertTrue(cacheApp.staticTexts["Roll"].waitForExistence(timeout: 10))
        let countBeforeSave = try XCTUnwrap(rollFrameCount(in: cacheApp))
        cacheApp.buttons["roll-back-to-camera"].tap()

        let shutter = cacheApp.buttons["Capture photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20) && shutter.isEnabled)
        shutter.tap()
        let keepFrame = cacheApp.buttons["Keep frame"]
        XCTAssertTrue(keepFrame.waitForExistence(timeout: 40))
        keepFrame.tap()
        cacheApp.tap()

        let savedToast = cacheApp.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(savedToast.waitForExistence(timeout: 20))

        openRoll.tap()
        XCTAssertTrue(cacheApp.staticTexts["Roll"].waitForExistence(timeout: 10))
        let sourceSummary = cacheApp.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Newest first. Source: Local cache'")
        ).firstMatch
        XCTAssertTrue(
            sourceSummary.exists,
            "Add Photos Only must expose the committed local cache; configure Photos access to Add Photos Only"
        )
        XCTAssertEqual(try XCTUnwrap(rollFrameCount(in: cacheApp)), countBeforeSave + 1)

        let savedFrame = cacheApp.buttons.matching(
            NSPredicate(format: "label == 'Photo in your gallery, G7 X Compact'")
        ).firstMatch
        XCTAssertTrue(savedFrame.exists, "The newly committed cache entry must be listed")
        savedFrame.tap()
        XCTAssertTrue(
            cacheApp.descendants(matching: .any).matching(
                NSPredicate(format: "label == 'Photo'")
            ).firstMatch.waitForExistence(timeout: 5),
            "The committed local JPEG must be readable"
        )

        cacheApp.terminate()
        cacheApp.launch()
        XCTAssertTrue(cacheApp.buttons["Open roll"].waitForExistence(timeout: 10))
        cacheApp.buttons["Open roll"].tap()
        XCTAssertTrue(cacheApp.staticTexts["Roll"].waitForExistence(timeout: 10))
        XCTAssertTrue(sourceSummary.exists, "The cache index must survive service recreation")
        XCTAssertEqual(try XCTUnwrap(rollFrameCount(in: cacheApp)), countBeforeSave + 1)
        XCTAssertTrue(savedFrame.exists, "The saved local frame must survive app relaunch")
        savedFrame.tap()
        XCTAssertTrue(
            cacheApp.descendants(matching: .any).matching(
                NSPredicate(format: "label == 'Photo'")
            ).firstMatch.waitForExistence(timeout: 5),
            "The relaunched service must still read the cached JPEG"
        )
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
            let recipeApp = makeApplication()
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

        let compactApp = makeApplication()
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
        XCTAssertTrue(compactApp.buttons["recipe-menu"].waitForExistence(timeout: 5))

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
            "A G7 X flash capture should reach the review screen"
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

    /// Opt-in, non-destructive Roll acceptance on a provisioned physical iPhone or iPad.
    /// The saved frame is intentionally retained in Photos and the local cache.
    func testPhysicalG7XSaveRollDetailAndShareAcceptance() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Roll capture and share acceptance requires a physical iPhone or iPad")
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
        let rollApp = makeApplication()
        // Deliberately omit -ui-testing: this exercises normal Photos access,
        // the real local fallback cache, and the real share controller.
        rollApp.launchArguments = ["-ui-testing-preview-status", "-selectedRecipeID", "g7x-compact"]
        rollApp.launch()
        app = rollApp
        defer { rollApp.terminate() }
        defer { XCUIDevice.shared.orientation = .portrait }

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
            waitForLiveShutter(in: rollApp),
            "Normal app launch must reach a live physical camera"
        )
        XCTAssertTrue(rollApp.buttons["recipe-menu"].waitForExistence(timeout: 5))
        attachScreenshot(named: "roll-qa-g7x-viewfinder")

        shutter.tap()
        let keepFrame = rollApp.buttons["Keep frame"]
        XCTAssertTrue(
            keepFrame.waitForExistence(timeout: 40),
            "G7 X capture must reach full-resolution review"
        )
        attachScreenshot(named: "roll-qa-g7x-review")

        let reviewImage = rollApp.descendants(matching: .any)["review-image"]
        let printFinish = rollApp.buttons["review-finish-instantPrint"]
        let photoFinish = rollApp.buttons["review-finish-photo"]
        assertMinimumHitTarget(printFinish, named: "Instant Print finish")
        assertMinimumHitTarget(photoFinish, named: "Photo finish")

        printFinish.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                reviewImage.label.contains("Instant Print") && keepFrame.isEnabled
            },
            "Instant Print must finish rendering before Save is enabled"
        )
        photoFinish.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                !reviewImage.label.contains("Instant Print") && keepFrame.isEnabled
            },
            "Photo must remove the border and settle before Save is enabled"
        )
        printFinish.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                reviewImage.label.contains("Instant Print") && keepFrame.isEnabled
            },
            "Returning to Instant Print must restore the finished border"
        )
        attachScreenshot(named: "roll-qa-instant-print-portrait")

        let compare = rollApp.buttons["review-compare-original"]
        assertMinimumHitTarget(compare, named: "Original comparison")
        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 30) { compare.value as? String == "Original" })
        XCTAssertEqual(
            printFinish.value as? String,
            "Selected",
            "Original comparison must not change the selected export finish"
        )
        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 15) {
            compare.value as? String == "Look" && reviewImage.label.contains("Instant Print")
        })

        let lookPicker = rollApp.buttons["review-look-picker"]
        lookPicker.tap()
        let monochrome = revealReviewLook(
            "review-look-acros-monochrome",
            in: rollApp,
            scrollingTowardLowerOptions: true
        )
        monochrome.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                reviewImage.label.contains("Fine Monochrome")
                    && reviewImage.label.contains("Instant Print")
                    && keepFrame.isEnabled
            },
            "Changing the look must retain Instant Print and finish rendering before Save"
        )

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(
            waitUntil(timeout: 10) { rollApp.frame.width > rollApp.frame.height },
            "Instant Print review must settle into landscape"
        )
        XCTAssertEqual(printFinish.value as? String, "Selected")
        attachScreenshot(named: "roll-qa-instant-print-landscape")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            waitUntil(timeout: 10) { rollApp.frame.height > rollApp.frame.width },
            "Instant Print review must return to portrait before saving"
        )
        lookPicker.tap()
        let g7x = revealReviewLook(
            "review-look-g7x-compact",
            in: rollApp,
            scrollingTowardLowerOptions: false
        )
        g7x.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                reviewImage.label.contains("G7 X Compact")
                    && reviewImage.label.contains("Instant Print")
                    && keepFrame.isEnabled
            },
            "Returning to G7 X must retain Instant Print before saving"
        )

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

        share.tap()
        let copyAction = rollApp.descendants(matching: .any)["Copy"]
        XCTAssertTrue(
            copyAction.waitForExistence(timeout: 30),
            "Share frame must present the activity sheet with system actions"
        )
        let closeShare = rollApp.descendants(matching: .any)["Close"]
        let activitySheet = rollApp.sheets.firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 10) { closeShare.exists || activitySheet.exists },
            "Share frame must expose a dismissible activity sheet or Close control. Accessibility tree:\n\(rollApp.debugDescription)"
        )
        attachScreenshot(named: "roll-qa-share-sheet")
        if closeShare.exists {
            XCTAssertTrue(closeShare.isHittable, "The activity sheet Close control must be tappable")
            closeShare.tap()
        } else {
            XCTAssertTrue(activitySheet.exists, "Activity sheet must remain observable before dismissal")
            activitySheet.swipeDown()
        }
        XCTAssertTrue(
            waitForDisappearance(copyAction, timeout: 10),
            "Cancelling the activity sheet must return to frame detail on phone and iPad"
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
    #endif

    func testAccessibilitySizeCameraShellKeepsRecipeControlsReachable() throws {
        let accessibilityApp = MainActor.assumeIsolated {
            let accessibilityApp = makeApplication()
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

        let roll = accessibilityApp.buttons["Open roll"]
        let currentLook = accessibilityApp.buttons["recipe-menu"]
        let importPhoto = accessibilityApp.buttons["import-photo"]
        for (element, name) in [(roll, "Roll"), (currentLook, "Current look"), (importPhoto, "Import")] {
            assertMinimumHitTarget(element, named: "Accessibility-size " + name)
            assertContained(element, in: accessibilityApp, named: name)
        }
        XCTAssertFalse(roll.frame.intersects(currentLook.frame))
        XCTAssertFalse(currentLook.frame.intersects(importPhoto.frame))
        XCTAssertFalse(accessibilityApp.descendants(matching: .any)["recipe-picker"].exists)
        openRecipeDrawer(in: accessibilityApp)
        let tune = accessibilityApp.buttons["Tune Muted Color"]
        assertMinimumHitTarget(tune, named: "Accessibility-size Tune")
        assertMinimumHitTarget(accessibilityApp.buttons["recipe-drawer-close"], named: "Close picker")
        attachScreenshot(named: "accessibility-camera-look-drawer")
        tune.tap()
        XCTAssertTrue(accessibilityApp.staticTexts["Recipe controls"].waitForExistence(timeout: 5))
        assertMinimumHitTarget(accessibilityApp.buttons["Done editing Muted Color"], named: "Done editing")
        attachScreenshot(named: "accessibility-large-text-editor")
    }

    func testMonochromeEditorHidesNoOpColorControls() throws {
        app.terminate()

        let monochromeApp = makeApplication()
        monochromeApp.launchArguments = [
            "-ui-testing",
            "-selectedRecipeID",
            "acros-neutral-filter"
        ]
        monochromeApp.launch()
        defer { monochromeApp.terminate() }

        openRecipeDrawer(in: monochromeApp)
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

    #if targetEnvironment(simulator)
    func testViewfinderFirstChromePreviewKeepsCameraQuiet() throws {
        let previewApp = MainActor.assumeIsolated {
            let previewApp = makeApplication()
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

        assertMinimumHitTarget(previewApp.buttons["recipe-menu"], named: "Current look")
        XCTAssertFalse(previewApp.descendants(matching: .any)["recipe-picker"].exists)
        XCTAssertFalse(previewApp.descendants(matching: .any)["camera-tool-strip"].exists)

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

        returnToMainCamera(using: app.buttons["roll-back-to-camera"], named: "Roll back to camera")
        let settings = app.buttons["settings-tab"]
        assertMinimumHitTarget(settings, named: "Settings")
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
        // The return action stays pinned even after scrolling deep into Settings.
        returnToMainCamera(using: app.buttons["settings-back-to-camera"], named: "Scrolled Settings back to camera")
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

        openRecipeDrawer(in: app)

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
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
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

    private func rollFrameCount(in target: XCUIApplication) -> Int? {
        for label in target.staticTexts.allElementsBoundByIndex.map(\.label)
            where label.hasSuffix(" frames") {
            if let count = Int(label.dropLast(" frames".count)) {
                return count
            }
        }
        return target.staticTexts["Roll"].exists ? 0 : nil
    }

    func testRecipeFirstOnboardingFlow() throws {
        let onboardingApp = MainActor.assumeIsolated {
            let onboardingApp = makeApplication()
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

    private func openRecipeDetail(
        for recipeID: String,
        in target: XCUIApplication,
        tuneLabel: String
    ) {
        openRecipeDrawer(in: target)
        let recipe = target.buttons["recipe-\(recipeID)"]
        assertMinimumHitTarget(recipe, named: recipeID + " recipe")
        recipe.tap()

        let tune = target.buttons[tuneLabel]
        assertMinimumHitTarget(tune, named: tuneLabel)
        tune.tap()
        XCTAssertTrue(target.staticTexts["Recipe controls"].waitForExistence(timeout: 5))
    }

    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = defaultsSuiteName
        return application
    }

    private func openRecipeDrawer(in target: XCUIApplication) {
        let drawer = target.descendants(matching: .any)["recipe-drawer"]
        if !drawer.exists {
            let currentLook = target.buttons["recipe-menu"]
            assertMinimumHitTarget(currentLook, named: "Current look")
            if target.frame.width >= 700 {
                // AssistiveTouch can overlap the center of this edge-column
                // control on a physical iPad. Tap the leading quarter while
                // staying inside the button's actual accessibility frame.
                let targetFrame = target.frame
                let buttonFrame = currentLook.frame
                let point = CGPoint(
                    x: buttonFrame.minX + buttonFrame.width * 0.25,
                    y: buttonFrame.midY
                )
                target.coordinate(withNormalizedOffset: CGVector(
                    dx: (point.x - targetFrame.minX) / targetFrame.width,
                    dy: (point.y - targetFrame.minY) / targetFrame.height
                )).tap()
            } else {
                currentLook.tap()
            }
        }
        let appeared = drawer.waitForExistence(timeout: 5)
        if !appeared {
            attachScreenshot(named: "look-picker-did-not-open")
        }
        XCTAssertTrue(appeared, "Tapping the current look must open the look picker")
        assertMinimumHitTarget(target.buttons["recipe-drawer-close"], named: "Close look picker")
    }

    private func assertContained(_ element: XCUIElement, in target: XCUIApplication, named: String) {
        let tolerance = target.frame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(tolerance.contains(element.frame), named + " must remain inside the visible screen")
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
        scrollIntoView(element, in: app, downward: false)
    }

    private func scrollBackToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        scrollIntoView(element, in: app, downward: true)
    }

    /// SwiftUI's review Menu can bridge its options as Button, PopUpButton, or
    /// another accessibility type depending on the OS. Use the stable
    /// identifier and mounted, hittable option rows instead of a type-sensitive
    /// query or a guessed screen coordinate.
    private func revealReviewLook(
        _ identifier: String,
        in app: XCUIApplication,
        scrollingTowardLowerOptions: Bool
    ) -> XCUIElement {
        let option = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(
            waitUntil(timeout: 5) { self.visibleReviewLookRows(in: app).count >= 1 },
            "Review look menu must open"
        )

        for _ in 0..<6 {
            if option.exists, option.isHittable {
                return option
            }

            let visibleRows = visibleReviewLookRows(in: app)
            XCTAssertGreaterThanOrEqual(
                visibleRows.count,
                2,
                "Review look menu must expose two rows for a bounded scroll gesture"
            )
            guard !visibleRows.isEmpty else {
                continue
            }

            // Keep both endpoints comfortably inside the native popup when
            // several rows are visible. With only two or three mounted rows,
            // the outer rows are the reliable scroll targets.
            let upperIndex = visibleRows.count >= 4 ? 1 : 0
            let lowerIndex = visibleRows.count >= 4 ? visibleRows.count - 2 : visibleRows.count - 1
            let upperRow = visibleRows[upperIndex]
            let lowerRow = visibleRows[lowerIndex]

            let targetIsAbove = option.exists && !option.frame.isEmpty
                && option.frame.maxY < upperRow.frame.minY
            let scrollDown = targetIsAbove || (!option.exists && !scrollingTowardLowerOptions)
            // Start and end on mounted, hittable menu rows. The collection
            // accessibility node reports the whole app frame on iOS 26, and
            // gestures based on it dismiss the popup instead of scrolling it.
            let startRow = scrollDown ? upperRow : lowerRow
            let endRow = scrollDown ? lowerRow : upperRow
            let start = startRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = endRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        XCTAssertTrue(
            option.exists && option.isHittable,
            "Review menu must expose \(identifier) after bounded scrolling"
        )
        return option
    }

    private func visibleReviewLookRows(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .allElementsBoundByIndex
            .filter {
                $0.identifier.hasPrefix("review-look-")
                    && $0.identifier != "review-look-picker"
                    && $0.exists
                    && !$0.frame.isEmpty
                    && $0.isHittable
            }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, downward: Bool) {
        let recipeDetailScroll = app.descendants(matching: .any)["recipe-detail-scroll"]
        if recipeDetailScroll.exists {
            scrollRecipeDetailIntoView(element, in: app, scrollView: recipeDetailScroll, downward: downward)
            return
        }

        // A presented sheet can leave the camera's horizontal utility rail in
        // the accessibility tree. Scroll the active Pro sheet explicitly.
        let manualControlsScroll = app.scrollViews["manual-controls-scroll"]
        let scrollView = manualControlsScroll.exists ? manualControlsScroll : app.scrollViews.firstMatch
        for _ in 0..<20 {
            if element.exists, element.isHittable {
                let viewport = scrollView.exists ? scrollView.frame.intersection(app.frame) : app.frame
                // A partly exposed button can report hittable while its center
                // lies underneath the pinned action bar. Fully reveal small
                // controls before tapping; large information cards may scroll.
                if element.frame.height > viewport.height || viewport.contains(element.frame) {
                    return
                }
            }
            let viewport = scrollView.exists ? scrollView.frame.intersection(app.frame) : app.frame
            let shouldScrollDown = element.exists
                ? element.frame.midY < viewport.midY
                : downward
            if shouldScrollDown {
                (scrollView.exists ? scrollView : app).swipeDown(velocity: .slow)
            } else {
                (scrollView.exists ? scrollView : app).swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "The requested control must scroll into view")
    }

    private func scrollRecipeDetailIntoView(
        _ element: XCUIElement,
        in app: XCUIApplication,
        scrollView: XCUIElement,
        downward: Bool
    ) {
        for _ in 0..<20 {
            guard scrollView.exists else {
                attachScreenshot(named: "recipe-detail-scroll-disappeared")
                XCTFail("Recipe detail editor disappeared while scrolling")
                return
            }

            let screenFrame = app.frame
            var viewport = scrollView.frame.intersection(screenFrame)
            let actionButton = app.buttons.matching(
                NSPredicate(
                    format: "label BEGINSWITH 'Done editing ' OR label BEGINSWITH 'Apply changes to ' OR label BEGINSWITH 'Use '"
                )
            ).firstMatch
            if actionButton.exists {
                viewport.size.height = min(
                    viewport.height,
                    max(0, actionButton.frame.minY - viewport.minY - 10)
                )
            }

            guard viewport.width > 20, viewport.height > 20 else {
                attachScreenshot(named: "recipe-detail-scroll-invalid-viewport")
                XCTFail("Recipe detail scroll viewport is not usable")
                return
            }

            if element.exists, element.isHittable,
               viewport.contains(element.frame) {
                return
            }

            let shouldScrollDown: Bool
            if !element.exists || element.frame.isEmpty {
                shouldScrollDown = downward
            } else {
                shouldScrollDown = element.frame.midY < viewport.midY
            }

            let leadingX = viewport.minX + 10
            let startY = shouldScrollDown ? viewport.minY + 10 : viewport.maxY - 10
            let endY = shouldScrollDown ? viewport.maxY - 10 : viewport.minY + 10
            let start = app.coordinate(withNormalizedOffset: CGVector(
                dx: (leadingX - screenFrame.minX) / screenFrame.width,
                dy: (startY - screenFrame.minY) / screenFrame.height
            ))
            let end = app.coordinate(withNormalizedOffset: CGVector(
                dx: (leadingX - screenFrame.minX) / screenFrame.width,
                dy: (endY - screenFrame.minY) / screenFrame.height
            ))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        guard scrollView.exists else {
            attachScreenshot(named: "recipe-detail-scroll-disappeared")
            XCTFail("Recipe detail editor disappeared while scrolling")
            return
        }
        XCTAssertTrue(
            element.exists && element.isHittable,
            "The requested recipe detail control must scroll into view"
        )
    }

    // MARK: - Lifecycle and resilience

    /// Require two successful GPU completions, not just session startup or
    /// an enabled shutter. A stale preview token cannot pass this check.
    private func waitForLiveShutter(in target: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let shutter = target.buttons["Capture photo"]
        let preview = target.descendants(matching: .any)["camera-preview-render-status"]
        var firstRenderedToken: String?
        let ready = waitUntil(timeout: timeout) {
            guard shutter.exists, shutter.isEnabled, preview.exists,
                  let token = preview.value as? String,
                  token.hasPrefix("state=rendered;") else { return false }
            if let firstRenderedToken {
                return token != firstRenderedToken
            }
            firstRenderedToken = token
            return false
        }
        if !ready {
            let status = preview.exists ? String(describing: preview.value) : "Preview absent"
            let attachment = XCTAttachment(string: status)
            attachment.name = "preview-render-status"
            attachment.lifetime = .keepAlways
            add(attachment)
            attachScreenshot(named: "preview-did-not-render-fresh-frames")
        }
        return ready
    }

    private func requiresLiveCamera(in target: XCUIApplication) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        XCTAssertTrue(waitForLiveShutter(in: target, timeout: 15),
                      "A physical-device acceptance test must start with a live camera")
        return true
        #endif
    }

    private func waitForCameraShell(in target: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        // The Roll thumbnail sits in the capture row of every camera layout,
        // on hardware and in Simulator preview mode alike.
        target.buttons["Open roll"].waitForExistence(timeout: timeout)
    }

    func testBackgroundingAndForegroundingRestoresTheViewfinder() throws {
        XCTAssertTrue(waitForCameraShell(in: app), "The camera shell should be up before backgrounding")
        let isPhysical = requiresLiveCamera(in: app)

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
        let isPhysical = requiresLiveCamera(in: app)

        for tab in ["roll-tab", "settings-tab"] {
            let destination = app.buttons[tab]
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "\(tab) should be reachable from the camera")
            destination.tap()
            let backID = tab == "roll-tab" ? "roll-back-to-camera" : "settings-back-to-camera"
            let back = app.buttons[backID]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
            back.tap()
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
        let isPhysical = requiresLiveCamera(in: app)
        openRecipeDrawer(in: app)
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
        XCTAssertGreaterThanOrEqual(taps, 6, "The look drawer should expose several recipes to switch between")
        app.buttons["recipe-drawer-close"].tap()
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
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires camera hardware")
        #else
        XCTAssertTrue(waitForLiveShutter(in: app, timeout: 20),
                      "Physical Retake acceptance requires a live camera")
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
        #endif
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
            let launched = makeApplication()
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
