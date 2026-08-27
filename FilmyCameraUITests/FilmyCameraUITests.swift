import XCTest

@MainActor
final class FilmyCameraUITests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Filmy Camera permissions") { alert in
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
        app.tap()
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

        let recipeMenu = app.descendants(matching: .any)["landscape-recipe-picker"]
        XCTAssertTrue(recipeMenu.waitForExistence(timeout: 8), "Landscape recipe menu should exist")
        assertMinimumAccessibilityFrame(recipeMenu, named: "Landscape recipe menu")

        let tune = app.buttons["Tune Muted Color"]
        assertMinimumHitTarget(tune, named: "Landscape tune recipe")
        attachScreenshot(named: "camera-landscape")
    }

    #if !targetEnvironment(simulator)
    func testPhysicalImportAppliesCurrentRecipeAndSaves() throws {
        let importPhoto = app.buttons["import-photo"]
        assertMinimumHitTarget(importPhoto, named: "Import photo")
        importPhoto.tap()

        let firstPhoto = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        ).firstMatch
        XCTAssertTrue(
            firstPhoto.waitForExistence(timeout: 10),
            "The system photo picker should expose at least one image"
        )
        let photoFrame = firstPhoto.frame
        let appFrame = app.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: (photoFrame.midX - appFrame.minX) / appFrame.width,
                dy: (photoFrame.midY - appFrame.minY) / appFrame.height
            )
        ).tap()

        XCTAssertTrue(
            app.staticTexts["Imported photo"].waitForExistence(timeout: 30),
            "The imported image should reach filtered review"
        )
        XCTAssertTrue(app.staticTexts["Filter applied"].exists)
        XCTAssertTrue(app.staticTexts["Full resolution"].exists)
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
    #endif

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

        let captureNotice = accessibilityApp.staticTexts[
            "Capture is available on a physical device"
        ]
        XCTAssertTrue(captureNotice.waitForExistence(timeout: 5))
        attachScreenshot(named: "accessibility-camera-shell-bounded")
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

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
