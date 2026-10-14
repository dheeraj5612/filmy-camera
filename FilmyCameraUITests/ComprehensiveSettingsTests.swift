import XCTest

/// Real UI interactions with isolated preferences; editor screenshots are
/// retained for review.
@MainActor
final class ComprehensiveSettingsTests: XCTestCase {
    func testEveryRecipeEditorSettingChangesAndResetRestoresTheLook() {
        let app = openRecipeEditor(recipeID: "classic-chrome", tuneTitle: "Tune Muted Color")
        defer { app.terminate() }

        for label in ["Exposure", "Highlights", "Shadows", "Contrast"] { exerciseSlider(label, app) }
        for title in ["AUTO", "DR100", "DR200", "DR400"] {
            choose("recipe-choice-Dynamic range", title, app)
        }
        for title in ["AUTO", "Off", "Weak", "Strong"] {
            choose("recipe-choice-D Range Priority", title, app)
        }
        finishRecipeEditor(app, attachmentName: "tone-recipe-editor-settings-modified")
    }

    func testEveryRecipeEditorColorAndWhiteBalanceChangesAndResetRestoresTheLook() {
        let app = openRecipeEditor(recipeID: "classic-chrome", tuneTitle: "Tune Muted Color")
        defer { app.terminate() }

        exerciseSlider("Color", app)
        for (id, options) in [
            ("recipe-choice-Color Chrome", ["Off", "Weak", "Strong"]),
            ("fx-blue-control", ["Off", "Weak", "Strong"]),
            ("recipe-choice-White balance", ["AUTO", "White priority", "Ambience priority", "Daylight", "Shade",
                                            "Fluorescent 1", "Fluorescent 2", "Fluorescent 3", "Incandescent", "Underwater",
                                            "Custom 1", "Custom 2", "Custom 3", "Color temperature"])
        ] {
            for title in options { choose(id, title, app) }
        }
        for label in ["Color temperature", "Warmth", "Tint"] { exerciseSlider(label, app) }
        finishRecipeEditor(app, attachmentName: "color-recipe-editor-settings-modified")
    }

    func testEveryRecipeEditorTextureAndFinishChangesAndResetRestoresTheLook() {
        let app = openRecipeEditor(recipeID: "classic-chrome", tuneTitle: "Tune Muted Color")
        defer { app.terminate() }

        expandSection("Texture", app)
        for label in ["Sharpness", "Noise reduction", "Clarity"] { exerciseSlider(label, app) }
        expandSection("Finish", app)
        for title in ["Off", "Weak", "Strong"] { choose("recipe-choice-Grain Effect", title, app) }
        for title in ["Small", "Large"] { choose("recipe-choice-Grain Size", title, app) }
        for label in ["Vignette", "Halation"] { exerciseSlider(label, app) }
        finishRecipeEditor(app, attachmentName: "texture-finish-recipe-editor-settings-modified")
    }

    func testRecipeEditorResetClearsCombinedCrossSectionDraft() {
        let app = openRecipeEditor(recipeID: "classic-chrome", tuneTitle: "Tune Muted Color")
        defer { app.terminate() }

        exerciseSlider("Exposure", app)
        exerciseSlider("Color", app)
        expandSection("Texture", app)
        exerciseSlider("Sharpness", app)
        expandSection("Finish", app)
        exerciseSlider("Vignette", app)
        let hero = app.descendants(matching: .any)["recipe-detail-hero"]
        XCTAssertTrue(hero.exists)
        XCTAssertTrue((hero.value as? String ?? "").contains("Edited"), "Hero must report the edited draft")
        finishRecipeEditor(app, attachmentName: "combined-recipe-editor-settings-modified")
    }

    private func openRecipeEditor(recipeID: String, tuneTitle: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = makeApp()
        #if targetEnvironment(simulator)
        app.launchArguments = ["-ui-testing", "-selectedRecipeID", recipeID]
        #else
        app.launchArguments = ["-ui-testing-real-roll", "-selectedRecipeID", recipeID]
        #endif
        app.launch()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 20))
        app.buttons["recipe-menu"].tap()
        let tune = app.buttons[tuneTitle]
        XCTAssertTrue(tune.waitForExistence(timeout: 5))
        tune.tap()
        XCTAssertTrue(app.staticTexts["Recipe controls"].waitForExistence(timeout: 5))
        return app
    }

    private func finishRecipeEditor(_ app: XCUIApplication, attachmentName: String) {
        XCTAssertTrue(app.buttons["Apply changes to Muted Color"].isEnabled)
        attach(attachmentName)
        reveal(app.buttons["Reset recipe controls"], app).tap()
        XCTAssertTrue(app.buttons["Done editing Muted Color"].waitForExistence(timeout: 5),
                      "Reset must remove the entire draft, including all edited sections")
        app.buttons["Done editing Muted Color"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
    }

    func testEveryCaptureSetupOptionAndSettingsTogglePersists() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        openSetup(app)
        for title in ["3s", "5s", "10s", "Off"] {
            choose("capture-delay-picker", title, app)
        }
        for title in ["4:3", "1:1", "3:2", "16:9", "Fit screen"] {
            choose("capture-aspect-picker", title, app)
        }
        for title in ["Golden ratio", "Square guide", "Center crosshair", "Rule of thirds"] {
            choose("capture-guide-picker", title, app)
        }
        let toggles = ["capture-grid-toggle", "capture-level-toggle", "capture-histogram-toggle",
                       "capture-zebras-toggle", "capture-peaking-toggle"]
        for id in toggles {
            let control = reveal(app.switches[id], app)
            let original = control.value as? String
            setToggle(control, original == "1" ? "0" : "1")
            setToggle(control, original ?? "0")
            setToggle(control, "1")
        }
        choose("capture-delay-picker", "5s", app)
        choose("capture-aspect-picker", "3:2", app)
        choose("capture-guide-picker", "Golden ratio", app)
        closeSetup(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["capture-setup-open"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["capture-setup-open"].value as? String, "Timer 5s, 3:2")
        openSetup(app)
        assertChoice(reveal(app.descendants(matching: .any)["capture-delay-picker"], app), "5s")
        assertChoice(reveal(app.descendants(matching: .any)["capture-aspect-picker"], app), "3:2")
        assertChoice(reveal(app.descendants(matching: .any)["capture-guide-picker"], app), "Golden ratio")
        for id in toggles { XCTAssertEqual(reveal(app.switches[id], app).value as? String, "1", id) }
        attach("every-capture-option-restored")
        closeSetup(app)
        app.buttons["settings-tab"].tap()
        for label in ["Framing grid", "Haptic feedback"] {
            setToggle(reveal(app.switches[label], app), "0")
        }
        app.buttons["settings-back-to-camera"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 20))
        app.buttons["settings-tab"].tap()
        for label in ["Framing grid", "Haptic feedback"] {
            let toggle = reveal(app.switches[label], app)
            XCTAssertEqual(toggle.value as? String, "0", label)
            setToggle(toggle, "1")
        }
        // Clearing an existing personal cache is intentionally not a UI test.
        // Cache deletion and recovery are covered with owned fixture files.
        XCTAssertTrue(reveal(app.buttons["clear-local-cache"], app, requireHittable: false).exists)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["privacy-policy-link"], app).isHittable)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["support-link"], app).isHittable)
        attach("settings-links-storage-and-preferences")
        app.buttons["settings-back-to-camera"].tap()
        openSetup(app)
        XCTAssertEqual(reveal(app.switches["capture-grid-toggle"], app).value as? String, "1",
                       "Settings and Capture setup must share the grid preference")
    }

    func testResetCameraSettingsRestoresCaptureSetupAndSettingsToggles() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        openSetup(app)
        choose("capture-delay-picker", "5s", app)
        choose("capture-aspect-picker", "3:2", app)
        choose("capture-finish-picker", "Instant Print", app)
        setToggle(reveal(app.switches["capture-zebras-toggle"], app), "1")
        closeSetup(app)
        app.buttons["settings-tab"].tap()
        setToggle(reveal(app.switches["Framing grid"], app), "0")
        setToggle(reveal(app.switches["Haptic feedback"], app), "0")
        setToggle(reveal(app.switches["Mirror front camera"], app), "0")
        setToggle(reveal(app.switches["Date stamp"], app), "1")
        reveal(app.buttons["settings-reset-camera"], app).tap()
        let confirm = app.buttons["Reset"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Camera settings reset."].waitForExistence(timeout: 5))
        XCTAssertEqual(reveal(app.switches["Framing grid"], app).value as? String, "1")
        XCTAssertEqual(reveal(app.switches["Haptic feedback"], app).value as? String, "1")
        XCTAssertEqual(reveal(app.switches["Mirror front camera"], app).value as? String, "1")
        XCTAssertEqual(reveal(app.switches["Date stamp"], app).value as? String, "0")
        app.buttons["settings-back-to-camera"].tap()
        XCTAssertTrue(app.buttons["capture-setup-open"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["capture-setup-open"].value as? String, "Timer Off, Fit screen")
        openSetup(app)
        assertChoice(reveal(app.descendants(matching: .any)["capture-delay-picker"], app), "Off")
        assertChoice(reveal(app.descendants(matching: .any)["capture-aspect-picker"], app), "Fit screen")
        assertChoice(reveal(app.descendants(matching: .any)["capture-finish-picker"], app), "Photo")
        XCTAssertEqual(reveal(app.switches["capture-zebras-toggle"], app).value as? String, "0")
        closeSetup(app)
    }

    func testSettingsGroupsSavedPhotoSettingsAndReplaysGestureHint() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 20))
        app.buttons["settings-tab"].tap()
        let page = app.scrollViews["settings-scroll"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))

        // Sections appear in order in one downward pass.
        let names = ["CAMERA", "SAVED PHOTOS", "PERMISSIONS", "STORAGE", "ABOUT", "RESET"]
        let headers: [XCUIElement] = names.map { page.staticTexts[$0] }
        for index in 0..<headers.count {
            let header = reveal(headers[index], app, requireHittable: false, diagnosticName: names[index])
            XCTAssertTrue(header.exists, "\(names[index]) section header must exist")
            if index > 0 {
                let previous = headers[index - 1]
                XCTAssertTrue(!previous.exists || previous.frame.minY < header.frame.minY,
                              "\(names[index - 1]) must come before \(names[index])")
            }
        }
        XCTAssertFalse(page.staticTexts["CAPTURE"].exists)
        XCTAssertFalse(page.staticTexts["ACCESS"].exists)
        reveal(headers[0], app, requireHittable: false)
        attach("settings-grouped-sections")

        // Grouping: Camera controls above Saved photos, Saved photo settings above Permissions.
        let saved = headers[1]
        let perms = headers[2]
        let haptic = reveal(page.switches["Haptic feedback"], app, requireHittable: false)
        XCTAssertTrue(!saved.exists || haptic.frame.minY < saved.frame.minY)
        let replayRow = reveal(page.buttons["settings-replay-gestures"], app, requireHittable: false)
        XCTAssertTrue(!saved.exists || replayRow.frame.minY < saved.frame.minY)
        let date = reveal(page.switches["Date stamp"], app, requireHittable: false)
        XCTAssertTrue(!saved.exists || saved.frame.minY < date.frame.minY)
        XCTAssertTrue(!perms.exists || date.frame.minY < perms.frame.minY)
        let mirror = reveal(page.switches["Mirror front camera"], app, requireHittable: false)
        XCTAssertTrue(!saved.exists || saved.frame.minY < mirror.frame.minY)
        XCTAssertTrue(!perms.exists || mirror.frame.minY < perms.frame.minY)
        XCTAssertTrue(!date.exists || date.frame.minY < mirror.frame.minY)
        let location = page.switches["settings-location-tagging"]
        reveal(location, app, requireHittable: false)
        XCTAssertTrue(!saved.exists || saved.frame.minY < location.frame.minY)
        XCTAssertTrue(!perms.exists || location.frame.minY < perms.frame.minY)
        XCTAssertTrue(!mirror.exists || mirror.frame.minY < location.frame.minY)

        // One merged Location row.
        let access = page.descendants(matching: .any)["settings-location-access"]
        XCTAssertEqual(page.descendants(matching: .any).matching(identifier: "settings-location-access").count, 1)
        XCTAssertEqual(page.switches.matching(identifier: "settings-location-tagging").count, 1)
        XCTAssertEqual(page.switches.matching(NSPredicate(format: "label == 'Location tagging'")).count, 1)
        XCTAssertTrue(access.label.hasPrefix("Location tag"), "label=\(access.label)")
        XCTAssertEqual(page.staticTexts.matching(NSPredicate(format: "label == 'Location'")).count, 0)

        // The state line follows the toggle.
        setToggle(reveal(location, app), "1")
        let onLines = [
            "On. Filmy reads location only while the camera is open.",
            "On, but iPhone location is off for Filmy.",
            "On. iPhone asks the first time you open the camera."
        ]
        let offLine = "Off. Photos are not tagged with where you took them."
        XCTAssertTrue(wait { onLines.contains { access.label.contains($0) } }, "label=\(access.label)")
        attach("settings-saved-photos")
        let fix = page.buttons["location-permission-settings"]
        let denied = access.label.contains(onLines[1])
        if denied {
            reveal(fix, app)
            XCTAssertGreaterThanOrEqual(fix.frame.minY, location.frame.maxY)
            XCTAssertTrue(!perms.exists || fix.frame.minY < perms.frame.minY)
            XCTAssertTrue(fix.label.contains("Turn on location in Settings"), "label=\(fix.label)")
            attach("settings-location-denied-action")
            setToggle(reveal(location, app), "0")
            XCTAssertTrue(wait { access.label.contains(offLine) }, "label=\(access.label)")
            XCTAssertTrue(reveal(fix, app, requireHittable: false).exists)
            setToggle(reveal(location, app), "1")
        } else {
            XCTAssertFalse(fix.exists)
            setToggle(reveal(location, app), "0")
            XCTAssertTrue(wait { access.label.contains(offLine) }, "label=\(access.label)")
            XCTAssertFalse(fix.exists)
            setToggle(reveal(location, app), "1")
        }

        // Replay gestures row: before the tap the value reads "Hint not seen yet" or "Hint already seen" depending on launch arguments, never "Hint turned back on", so the wait after the tap proves the tap.
        let replay = reveal(page.buttons["settings-replay-gestures"], app)
        XCTAssertGreaterThanOrEqual(replay.frame.height, 44)
        XCTAssertEqual(replay.label, "Replay gestures")
        XCTAssertNotEqual(replay.value as? String, "Hint turned back on", "value before tap=\(String(describing: replay.value))")
        replay.tap()
        XCTAssertTrue(wait { replay.value as? String == "Hint turned back on" }, "value=\(String(describing: replay.value))")
        attach("settings-replay-gestures-confirmed")

        // Largest text keeps the Location row reachable.
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 20))
        app.buttons["settings-tab"].tap()
        let tag = reveal(page.switches["settings-location-tagging"], app)
        XCTAssertTrue(tag.isHittable)
        XCTAssertTrue(access.exists)
        XCTAssertGreaterThanOrEqual(access.frame.height, 44)
        attach("settings-saved-photos-largest-text")
    }

    func testGrainSizeIsDisabledWhileGrainEffectIsOff() {
        let app = openRecipeEditor(recipeID: "classic-chrome", tuneTitle: "Tune Muted Color")
        defer { app.terminate() }

        expandSection("Finish", app)
        choose("recipe-choice-Grain Effect", "Off", app)
        let size = reveal(app.descendants(matching: .any)["recipe-choice-Grain Size"], app,
                          requireHittable: false, diagnosticName: "recipe-choice-Grain Size")
        XCTAssertFalse(size.isEnabled, "Grain Size changes nothing while Grain Effect is Off")
        choose("recipe-choice-Grain Effect", "Weak", app)
        XCTAssertTrue(size.isEnabled)
    }

    func testMonochromeEditorAxesChangeAndReset() {
        continueAfterFailure = false
        let app = makeApp()
        #if targetEnvironment(simulator)
        app.launchArguments = ["-ui-testing", "-selectedRecipeID", "acros-neutral-filter"]
        #else
        app.launchArguments = ["-ui-testing-real-roll", "-selectedRecipeID", "acros-neutral-filter"]
        #endif
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 20))
        app.buttons["recipe-menu"].tap()
        let tune = app.buttons["Tune Neutral Monochrome"]
        XCTAssertTrue(tune.waitForExistence(timeout: 5))
        tune.tap()
        XCTAssertTrue(app.staticTexts["Monochrome recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["Color"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipe-choice-Color Chrome"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["fx-blue-control"].exists)
        for label in ["Monochromatic warm-cool", "Monochromatic green-magenta"] {
            exerciseSlider(label, app)
        }
        XCTAssertTrue(app.buttons["Apply changes to Neutral Monochrome"].isEnabled)
        attach("monochrome-editor-both-color-axes-modified")
        reveal(app.buttons["Reset recipe controls"], app).tap()
        XCTAssertTrue(app.buttons["Done editing Neutral Monochrome"].waitForExistence(timeout: 5))
        app.buttons["Done editing Neutral Monochrome"].tap()
    }

    func testSepiaEditorHidesNoOpColorControls() {
        continueAfterFailure = false
        let app = makeApp()
        #if targetEnvironment(simulator)
        app.launchArguments = ["-ui-testing", "-selectedRecipeID", "sepia-archive"]
        #else
        app.launchArguments = ["-ui-testing-real-roll", "-selectedRecipeID", "sepia-archive"]
        #endif
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 20))
        app.buttons["recipe-menu"].tap()
        let tune = app.buttons["Tune Sepia Archive"]
        XCTAssertTrue(tune.waitForExistence(timeout: 5))
        tune.tap()
        XCTAssertTrue(app.staticTexts["Monochrome recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["Color"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipe-choice-Color Chrome"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["fx-blue-control"].exists)
    }

    func testPhysicalEveryAspectAndTimerCapturesThenFrontCameraReturnsLive() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires a real iPhone camera")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
            "Set FILMY_RUN_PHOTOS_WRITE=1 because this flow saves six real Photos frames"
        )
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let cases: [(String, String, CGFloat?)] = [
            ("Fit screen", "Off", nil), ("4:3", "3s", 3.0 / 4.0),
            ("1:1", "5s", 1), ("3:2", "10s", 2.0 / 3.0), ("16:9", "Off", 9.0 / 16.0)
        ]
        for (aspect, delay, ratio) in cases {
            openSetup(app)
            choose("capture-delay-picker", delay, app)
            choose("capture-aspect-picker", aspect, app)
            closeSetup(app)
            requireLive(app)
            let preview = app.descendants(matching: .any)["camera-preview"]
            let expectedRatio = ratio ?? preview.frame.width / preview.frame.height
            XCTAssertEqual(preview.frame.width / preview.frame.height, expectedRatio, accuracy: 0.015)
            app.buttons["Capture photo"].tap()
            if delay != "Off" {
                XCTAssertTrue(app.buttons["capture-countdown-cancel"].waitForExistence(timeout: 2))
            }
            assertAutomaticSave(app, expectedRatio: expectedRatio)
            attach("physical-crop-\(aspect.replacingOccurrences(of: ":", with: "x"))-timer-\(delay)")
            requireLive(app)
        }
        let cameraSwitch = app.buttons["camera-switch-control"]
        let originalPosition = cameraSwitch.value as? String
        cameraSwitch.tap()
        XCTAssertTrue(wait { cameraSwitch.value as? String != originalPosition })
        requireLive(app)
        app.buttons["Capture photo"].tap()
        assertAutomaticSave(app)
        attach("physical-front-camera-auto-saved")
        requireLive(app)
        cameraSwitch.tap()
        XCTAssertTrue(wait { cameraSwitch.value as? String == originalPosition })
        requireLive(app)
        #endif
    }

    func testAccessSectionUsesPlainPermissionWords() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 20))
        app.buttons["settings-tab"].tap()

        let photos = reveal(app.buttons["photos-permission-settings"], app)
        XCTAssertTrue(photos.label.contains("Turn on Photos in Settings"), photos.label)
        let save = reveal(app.buttons["photos-save-permission-settings"], app)
        XCTAssertTrue(save.label.contains("Allow saving new photos"), save.label)
        for button in [photos, save] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open System Settings'")).count, 0)
        XCTAssertTrue(app.staticTexts["Photos access is off for Filmy."].exists)
        let photosBadge = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Photos, Off'")).firstMatch
        XCTAssertTrue(photosBadge.exists, "The Photos badge must read its subject and state")
        attach("settings-access-plain-words")
        let cameraBadge = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Camera, Simulator'")).firstMatch
        XCTAssertTrue(cameraBadge.exists, "The Camera badge must read its subject and state")
        #else
        throw XCTSkip("Needs the forced Photos-denied UI-test state")
        #endif
    }

    func testStorageExplainerAndInlineClearCacheConfirmation() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ui-testing-cache-confirm"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 20))
        app.buttons["settings-tab"].tap()

        let clear = reveal(app.buttons["clear-local-cache"], app, requireHittable: false)
        let places = ["photos", "roll", "captures"].map { app.descendants(matching: .any)["settings-storage-place-\($0)"] }
        let photosPlace = reveal(places[0], app, requireHittable: false)
        XCTAssertTrue(app.staticTexts["Where your photos are"].exists)
        for place in places { XCTAssertTrue(place.exists, place.identifier) }
        XCTAssertTrue(photosPlace.label.contains("saves here by itself"), photosPlace.label)
        XCTAssertGreaterThanOrEqual(photosPlace.frame.minY, clear.frame.maxY, "The explainer sits below the clear row")
        attach("settings-storage-where-photos-are")

        let confirm = app.buttons["confirm-clear-local-cache"]
        let keep = app.buttons["keep-local-cache"]
        let row = reveal(app.buttons["clear-local-cache"], app)
        XCTAssertEqual(row.value as? String, "Available")
        row.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isHittable && keep.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        XCTAssertGreaterThanOrEqual(keep.frame.height, 44)
        XCTAssertTrue(app.buttons["Keep cache"].exists)
        XCTAssertEqual(app.popovers.count + app.sheets.count, 0, "The confirmation is inline, not a popover")
        XCTAssertLessThanOrEqual(keep.frame.maxY, confirm.frame.minY)
        XCTAssertTrue(app.staticTexts["Clear cache?"].exists)
        attach("settings-clear-cache-inline-confirm")

        keep.tap()
        XCTAssertTrue(wait { !confirm.exists })
        XCTAssertEqual(row.value as? String, "Available")
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(wait { !confirm.exists })
        XCTAssertTrue(row.exists)

        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 20))
        app.buttons["settings-tab"].tap()
        reveal(app.buttons["clear-local-cache"], app).tap()
        XCTAssertTrue(wait { keep.isHittable && confirm.isHittable },
                      "Keep and Clear must both be reachable without scrolling at the largest text size")
        attach("settings-clear-cache-inline-confirm-largest-text")
        #else
        throw XCTSkip("Needs the forced Photos-denied UI-test state")
        #endif
    }

    func testOnboardingStartingLooksGridAndPermissionNote() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ui-testing-onboarding"]
        app.launch()
        defer { app.terminate() }

        let ids = ["g7x-compact", "classic-chrome", "nostalgic-negative", "acros-monochrome"]
        let tiles = ids.map { app.buttons["onboarding-recipe-\($0)"] }
        let t0 = tiles[0], t1 = tiles[1], t2 = tiles[2], t3 = tiles[3]
        let cont = app.buttons["onboarding-continue"]
        XCTAssertTrue(t0.waitForExistence(timeout: 15))
        for tile in tiles {
            XCTAssertTrue(tile.isHittable, tile.identifier)
            XCTAssertGreaterThanOrEqual(tile.frame.height, 44, tile.identifier)
        }
        XCTAssertTrue(cont.isHittable)
        XCTAssertLessThanOrEqual(t3.frame.maxY, cont.frame.minY)
        XCTAssertLessThanOrEqual(abs(t0.frame.minY - t1.frame.minY), 2)
        XCTAssertLessThanOrEqual(t0.frame.maxX, t1.frame.minX + 1)
        XCTAssertGreaterThanOrEqual(t2.frame.minY, t0.frame.maxY)
        XCTAssertLessThanOrEqual(abs(t2.frame.minX - t0.frame.minX), 2)
        XCTAssertLessThanOrEqual(abs(t3.frame.minX - t1.frame.minX), 2)
        XCTAssertGreaterThan(t0.frame.width, 140)
        XCTAssertLessThanOrEqual(abs(t0.frame.width - t1.frame.width), 2)
        XCTAssertEqual(t0.value as? String, "Selected")
        t1.tap()
        XCTAssertTrue(wait { t1.value as? String == "Selected" })

        let note = app.staticTexts["onboarding-permission-note"]
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("camera") && note.label.contains("Photos"), note.label)
        XCTAssertGreaterThanOrEqual(
            note.frame.minY, app.staticTexts["onboarding-save-explanation"].frame.maxY - 1)
        if app.frame.height >= 870 {
            XCTAssertTrue(app.scrollViews["onboarding-content"].frame.contains(note.frame))
            XCTAssertLessThanOrEqual(note.frame.maxY, cont.frame.minY)
        }
        attach("onboarding-starting-looks-grid")
        cont.tap()
        XCTAssertTrue(app.buttons["roll-tab"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding-screen"].exists)
        #else
        throw XCTSkip("Needs the simulator onboarding launch state")
        #endif
    }

    private func makeApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.AllSettings.\(UUID().uuidString)"
        #if targetEnvironment(simulator)
        app.launchArguments = ["-ui-testing", "-selectedRecipeID", "g7x-compact"]
        #else
        app.launchArguments = ["-ui-testing-real-roll", "-selectedRecipeID", "g7x-compact"]
        #endif
        addUIInterruptionMonitor(withDescription: "Settings QA camera and Photos permissions") { alert in
            MainActor.assumeIsolated {
                for title in ["Allow", "Allow Full Access", "Allow Access to All Photos", "OK"] {
                    if alert.buttons[title].exists {
                        alert.buttons[title].tap()
                        return true
                    }
                }
                return false
            }
        }
        return app
    }

    private func openSetup(_ app: XCUIApplication) {
        waitForUnobscuredApp(app)
        XCTAssertTrue(app.buttons["capture-setup-open"].waitForExistence(timeout: 20))
        app.buttons["capture-setup-open"].tap()
        XCTAssertTrue(app.buttons["capture-setup-done"].waitForExistence(timeout: 5))
    }

    private func closeSetup(_ app: XCUIApplication) {
        waitForUnobscuredApp(app)
        let done = app.buttons["capture-setup-done"]
        XCTAssertTrue(done.exists && done.isHittable)
        done.tap()
        XCTAssertTrue(wait {
            app.state == .runningForeground && !done.exists
                && app.buttons["capture-setup-open"].exists
        }, "Capture setup must dismiss and leave the camera app in the foreground")
    }

    private func waitForUnobscuredApp(_ app: XCUIApplication) {
        // A real notification banner intercepted Done and opened another app.
        // Wait for its disappearance before touching the top controls; do not
        // swipe a banner that can disappear while XCTest prepares the gesture.
        if app.state != .runningForeground { app.activate() }
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .descendants(matching: .any)["NotificationShortLookView"].firstMatch
        XCTAssertTrue(wait(timeout: 20) {
            app.state == .runningForeground && !banner.exists
        }, "The camera app must be foregrounded with no notification over its controls")
    }

    private func choose(_ id: String, _ title: String, _ app: XCUIApplication) {
        let picker = reveal(app.descendants(matching: .any)[id], app, diagnosticName: id)
        picker.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        assertChoice(picker, title)
    }

    private func assertChoice(_ picker: XCUIElement, _ title: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI menu pickers can expose the current choice in their label
        // instead of value. Read only this picker, never the menu's options or
        // unrelated text, so a successful tap alone cannot satisfy the test.
        let selected = wait {
            guard picker.exists, picker.isHittable else { return false }
            if picker.value as? String == title { return true }
            return picker.label.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains(title)
        }
        if !selected {
            let diagnostics = XCTAttachment(string: picker.debugDescription)
            diagnostics.name = "picker-selection-\(picker.identifier)"
            diagnostics.lifetime = .keepAlways
            add(diagnostics)
            attach("picker-selection-failure")
        }
        XCTAssertTrue(selected,
                      "\(picker.identifier) should select \(title); value=\(String(describing: picker.value)), label=\(picker.label)",
                      file: file, line: line)
    }

    @discardableResult
    private func reveal(_ control: XCUIElement, _ app: XCUIApplication,
                        requireHittable: Bool = true,
                        diagnosticName: String = "unresolved control") -> XCUIElement {
        let form = app.descendants(matching: .any)["capture-setup-form"]
        let editor = app.descendants(matching: .any)["recipe-detail-scroll"]
        let scroll = form.exists ? form : (editor.exists ? editor : app.scrollViews.firstMatch)
        // A native iPad Form can require more than one viewport of travel when
        // keyboard or large-text settings change its content height.
        let settings = app.scrollViews["settings-scroll"]
        let returnBar = app.buttons["settings-back-to-camera"]
        for attempt in 0..<40 {
            var viewport = scroll.frame.intersection(app.frame)
            // The pinned Settings return bar is opaque and can report a
            // control under it as hittable, so exclude the strip it covers.
            if settings.exists && returnBar.exists {
                let top = returnBar.frame.maxY + 12
                if top > viewport.minY {
                    viewport.size.height = max(0, viewport.maxY - top)
                    viewport.origin.y = top
                }
            }
            let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apply changes to ' OR label BEGINSWITH 'Done editing '")).firstMatch
            if editor.exists && action.exists {
                viewport.size.height = max(0, min(viewport.height, action.frame.minY - viewport.minY - 8))
            }
            if control.exists && (!requireHittable || control.isHittable) {
                // SwiftUI can report a one-pixel edge mismatch between the
                // hosted collection view and its accessibility frame.
                if viewport.insetBy(dx: -2, dy: -2).contains(control.frame) { return control }
            }
            let downward = control.exists && control.frame.midY < viewport.midY
            // Use a measured, bounded movement in the editor's margin. A
            // full-height swipe can jump past a nearby slider and alternate
            // between opposite sides of the pinned Apply button forever.
            if editor.exists {
                let overflow = control.exists
                    ? (downward ? viewport.minY - control.frame.minY : control.frame.maxY - viewport.maxY)
                    : viewport.height * 0.3
                let distance = min(max(overflow + 28, 80), viewport.height * 0.35)
                let start = CGPoint(x: viewport.minX + 8, y: downward ? viewport.minY + 40 : viewport.maxY - 40)
                let end = CGPoint(x: start.x, y: start.y + (downward ? distance : -distance))
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
            } else if form.exists && !control.exists {
                // A SwiftUI Form can virtualize an off-screen row on iPad, so
                // an unresolved target gives us no frame from which to infer
                // the direction. Search from both ends instead of repeatedly
                // swiping toward the bottom when the target is absent.
                if attempt < 20 { scroll.swipeDown() } else { scroll.swipeUp() }
            } else if !form.exists && settings.exists {
                // A measured drag in the page margin; a fling can overshoot
                // and leave the target under the pinned return bar.
                let from = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: downward ? 0.35 : 0.65))
                let to = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: downward ? 0.65 : 0.35))
                from.press(forDuration: 0.05, thenDragTo: to)
            } else if downward { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        let container = form.exists ? "capture-setup-form" : (editor.exists ? "recipe-detail-scroll" : "first scroll view")
        let diagnostics = XCTAttachment(string: "Target: \(diagnosticName)\nScroll container: \(container)")
        diagnostics.name = "unrevealed-control-geometry"
        diagnostics.lifetime = .keepAlways
        add(diagnostics)
        attach("unrevealed-control")
        XCTFail("Could not fully reveal \(diagnosticName)")
        return control
    }

    private func exerciseSlider(_ title: String, _ app: XCUIApplication) {
        let slider = reveal(app.sliders[title], app, diagnosticName: title)
        slider.adjust(toNormalizedSliderPosition: 0.1)
        let low = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertNotEqual(slider.value as? String, low, "\(title) must react across its range")
    }

    private func expandSection(_ title: String, _ app: XCUIApplication) {
        let section = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ",")).firstMatch
        // Disclosure groups expose the title and description together.
        let fallback = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        reveal(section.exists ? section : fallback, app, diagnosticName: title).tap()
    }

    private func setToggle(_ row: XCUIElement, _ value: String) {
        if row.value as? String == value { return }
        let control = row.switches.count == 1 ? row.switches.firstMatch : row
        XCTAssertTrue(control.isEnabled && control.isHittable)
        control.tap()
        XCTAssertTrue(wait { row.value as? String == value }, "\(row.label) must become \(value)")
    }

    private func requireLive(_ app: XCUIApplication) {
        let shutter = app.buttons["Capture photo"]
        let status = app.descendants(matching: .any)["camera-preview-render-status"]
        var firstToken: String?
        XCTAssertTrue(wait(timeout: 20) {
            guard shutter.exists, shutter.isEnabled, status.exists,
                  let token = status.value as? String, token.hasPrefix("state=rendered;") else { return false }
            if let firstToken { return token != firstToken }
            firstToken = token
            return false
        }, "The viewfinder must deliver two fresh GPU-rendered frames")
    }

    private func assertAutomaticSave(_ app: XCUIApplication, expectedRatio: CGFloat? = nil) {
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved with '")).firstMatch
        XCTAssertTrue(wait(timeout: 45) { saved.exists }, "Physical capture must auto-save without review")
        XCTAssertFalse(app.buttons["Keep frame"].exists)
        XCTAssertFalse(app.buttons["Retake"].exists)
        guard let expectedRatio else { return }

        // The preview assertion above proves the selected control changed the
        // viewfinder. Open the newly saved frame as well so the test verifies
        // the persisted crop, rather than only the pre-capture layout.
        let openRoll = app.buttons["Open roll"]
        XCTAssertTrue(openRoll.waitForExistence(timeout: 10))
        openRoll.tap()
        let frame = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH 'Photo in your gallery'")).firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 20) && frame.isHittable)
        let dimensions = frame.value as? String
        // XCTest exposes the localized AX value (for example,
        // "3,024x4,032"), so remove grouping characters before parsing.
        let parts: [Double]? = dimensions.flatMap { value in
            let components = value.split(separator: "x", omittingEmptySubsequences: false)
            guard components.count == 2 else { return nil }
            let groupingSeparators = Set([
                Locale.current.groupingSeparator ?? ",",
                ","
            ])
            let parsed = components.compactMap { component -> Double? in
                let normalized = component.filter {
                    !$0.isWhitespace && !groupingSeparators.contains(String($0))
                }
                guard !normalized.isEmpty, normalized.allSatisfy({ $0.isNumber }) else {
                    return nil
                }
                return Double(String(normalized))
            }
            guard parsed.count == 2 else { return nil }
            return parsed
        }
        XCTAssertEqual(parts?.count, 2, "The saved gallery tile must expose persisted pixel dimensions")
        if let parts, parts.count == 2 {
            XCTAssertTrue(parts.allSatisfy { $0 > 0 }, "The saved gallery tile must expose positive pixel dimensions")
        }
        if let parts, parts.count == 2, parts.allSatisfy({ $0 > 0 }) {
            XCTAssertEqual(parts[0] / parts[1], Double(expectedRatio), accuracy: 0.03,
                           "The saved gallery asset must preserve the selected crop")
        }
        frame.tap()
        let photo = app.images["Photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 20))
        app.buttons["Close frame"].tap()
        XCTAssertTrue(app.buttons["roll-back-to-camera"].waitForExistence(timeout: 5))
        app.buttons["roll-back-to-camera"].tap()
    }

    private func wait(timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return false
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
