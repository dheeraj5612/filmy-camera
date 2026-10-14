import XCTest

/// A normal-user acceptance path for the physical review recording sent to App Review.
///
/// This deliberately launches without `-ui-testing` or preview fixtures. It is opt-in
/// because capture and the imported-photo save both write to the device's Photos library.
@MainActor
final class PhysicalReviewFlowTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        #if targetEnvironment(simulator)
        throw XCTSkip("App Review recording requires a physical iPhone or iPad")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHYSICAL_REVIEW"] == "1",
            "Set FILMY_RUN_PHYSICAL_REVIEW=1 to run the physical App Review flow"
        )
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
            "Set FILMY_RUN_PHOTOS_WRITE=1 because this flow saves two real Photos frames"
        )
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
            XCUIDevice.shared.orientation = .portrait
            launchedApp?.terminate()
        }
    }

    func testPhysicalAppleReviewFlow() throws {
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Deliberately omit -ui-testing and all preview or seeded-photo flags.
        app.launch()
        dismissOnboardingIfPresent()
        app.tap()
        XCTAssertTrue(
            app.buttons["Open roll"].waitForExistence(timeout: 20),
            "The normal launch must expose the camera shell"
        )

        try chooseG7XLook()

        XCTAssertTrue(
            waitForLiveShutter(timeout: 30),
            "The App Review flow must reach a live physical camera preview"
        )
        attachScreenshot(named: "app-review-camera-live")

        // Choose the actual camera finish before capture. Captures save automatically;
        // there is no Retake/Keep review screen on this path.
        let setup = app.buttons["capture-setup-open"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        setup.tap()
        let finishPicker = app.descendants(matching: .any)["capture-finish-picker"]
        XCTAssertTrue(finishPicker.waitForExistence(timeout: 10))
        finishPicker.tap()
        let instantPrint = app.buttons["Instant Print"]
        XCTAssertTrue(instantPrint.waitForExistence(timeout: 10))
        instantPrint.tap()
        let done = app.buttons["capture-setup-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        XCTAssertTrue(waitForLiveShutter(timeout: 30))
        waitForSavedToastToDisappear()
        app.buttons["Capture photo"].tap()
        assertAutomaticSave()
        attachScreenshot(named: "app-review-camera-auto-saved")

        // Confirm the camera frame is visible in Filmy Camera's own Roll.
        let openRoll = app.buttons["Open roll"]
        XCTAssertTrue(openRoll.waitForExistence(timeout: 15))
        openRoll.tap()
        XCTAssertTrue(app.staticTexts["Roll"].waitForExistence(timeout: 15))
        resolvePhotosAccessIfNeeded()
        let savedFrame = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Photo in your gallery'")
        ).firstMatch
        XCTAssertTrue(
            savedFrame.waitForExistence(timeout: 30),
            "The automatically saved camera frame must appear in the in-app Roll"
        )
        attachScreenshot(named: "app-review-roll-camera-frame")
        savedFrame.tap()
        XCTAssertTrue(
            app.images["Photo"].waitForExistence(timeout: 30),
            "The saved camera frame must open in Roll detail"
        )
        app.buttons["Close frame"].tap()

        // Import one real library photo through the system picker. The picker is the
        // user's existing library; there is no fixture or synthetic image in this test.
        let rollImport = app.buttons["roll-import-photo"]
        XCTAssertTrue(rollImport.waitForExistence(timeout: 15))
        rollImport.tap()
        let firstPhoto = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        ).firstMatch
        guard firstPhoto.waitForExistence(timeout: 30) else {
            app.buttons["Cancel"].firstMatch.tap()
            throw XCTSkip("The connected device has no photo available in the system picker")
        }
        tapCenter(of: firstPhoto)

        XCTAssertTrue(app.staticTexts["review-heading"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.descendants(matching: .any)["review-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Filter applied'")).firstMatch.exists,
            "Imported review must report the applied resolution"
        )

        let compare = app.buttons["review-compare-original"]
        XCTAssertTrue(compare.waitForExistence(timeout: 10))
        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { (compare.value as? String) == "Original" })
        XCTAssertTrue(
            app.descendants(matching: .any)["review-image"].label.contains("Original"),
            "Imported review must expose an Original comparison"
        )
        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { (compare.value as? String) == "Look" })

        let importedInstantPrint = app.buttons["review-finish-instantPrint"]
        XCTAssertTrue(importedInstantPrint.waitForExistence(timeout: 10))
        importedInstantPrint.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                app.descendants(matching: .any)["review-image"].label.contains("Instant Print")
                    && app.buttons["Save filtered photo"].isEnabled
            },
            "Imported review must render the selected Instant Print finish"
        )
        attachScreenshot(named: "app-review-import-original-instant-print")

        let save = app.buttons["Save filtered photo"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        app.tap()
        resolvePhotosAccessIfNeeded()
        let savedToast = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                if savedToast.exists { return true }
                resolvePhotosAccessIfNeeded()
                return false
            },
            "Saving the imported photo must complete in Photos"
        )
        attachScreenshot(named: "app-review-import-saved")
    }

    private func dismissOnboardingIfPresent() {
        for identifier in ["onboarding-skip", "onboarding-skip-for-now"] {
            let skip = app.buttons[identifier]
            if skip.waitForExistence(timeout: 3) {
                skip.tap()
                return
            }
        }
        let textSkip = app.buttons["Skip"]
        if textSkip.waitForExistence(timeout: 2) {
            textSkip.tap()
        }
    }

    private func chooseG7XLook() throws {
        let currentLook = app.buttons["recipe-menu"]
        XCTAssertTrue(currentLook.waitForExistence(timeout: 10))
        // The connected iPad has AssistiveTouch enabled and its floating button can
        // overlap the center of this control. Use the unobstructed left side of the
        // visible button so the normal look picker opens reliably.
        currentLook.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let g7x = app.buttons["recipe-g7x-compact"]
        XCTAssertTrue(g7x.waitForExistence(timeout: 10), "The look picker must expose G7 X Compact")
        if g7x.isHittable {
            g7x.tap()
        } else {
            tapCenter(of: g7x)
        }
        XCTAssertTrue(waitUntil(timeout: 15) { currentLook.label.contains("G7 X Compact") })
        app.buttons["recipe-drawer-close"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) {
            !app.descendants(matching: .any)["recipe-drawer"].exists
        }, "Closing the look picker must leave the camera controls available")
    }

    private func waitForLiveShutter(timeout: TimeInterval) -> Bool {
        let shutter = app.buttons["Capture photo"]
        let preview = app.descendants(matching: .any)["camera-preview"]
        return waitUntil(timeout: timeout) {
            guard shutter.exists, shutter.isEnabled, preview.exists else { return false }
            return preview.label == "Live camera preview"
        }
    }

    private func waitForSavedToastToDisappear() {
        let saved = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        _ = waitUntil(timeout: 10) { !saved.exists }
    }

    private func assertAutomaticSave() {
        let saved = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                resolvePhotosAccessIfNeeded()
                return saved.exists
            },
            "Capture must save directly to Photos without a Retake/Keep review"
        )
        XCTAssertFalse(app.descendants(matching: .any)["capture-save-recovery"].exists)
    }

    @discardableResult
    private func resolvePhotosAccessIfNeeded() -> Bool {
        let permissionTitles = ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK"]
        var handled = false
        var applications = [app!]
        applications.append(XCUIApplication(bundleIdentifier: "com.apple.springboard"))
        for application in applications {
            let alert = application.alerts.firstMatch
            guard alert.exists else { continue }
            for title in permissionTitles {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    handled = true
                    break
                }
            }
        }
        let inApp = app.buttons["Allow Photos access"]
        if inApp.exists, inApp.isHittable {
            inApp.tap()
            handled = true
        }
        return handled
    }

    private func tapCenter(of element: XCUIElement) {
        let frame = element.frame
        let appFrame = app.frame
        app.coordinate(withNormalizedOffset: CGVector(
            dx: (frame.midX - appFrame.minX) / appFrame.width,
            dy: (frame.midY - appFrame.minY) / appFrame.height
        )).tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return condition()
    }
}

/// Focused physical-camera coverage for the newer capture workspaces.
///
/// This is intentionally separate from the App Review recording flow above. It
/// writes real originals to the device, so it is opt-in and is never selected
/// by simulator lanes. Unsupported modes are skipped with an explicit reason.
@MainActor
final class PhysicalCaptureFeatureTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical capture feature coverage requires a real iPhone or iPad")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
            "Set FILMY_RUN_PHOTOS_WRITE=1 because these cases save real camera originals"
        )
        #endif

        addUIInterruptionMonitor(withDescription: "Physical capture permissions") { alert in
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
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
            launchedApp?.terminate()
        }
    }

    func testPhysicalBurstFilmVideoAndNightRetainOriginals() throws {
        launchNormalCamera()
        openCaptureModes()

        try captureMode("burst", start: { shutter in
            shutter.tap()
            XCTAssertTrue(waitUntil(timeout: 8) { shutter.label.contains("Stop capture") },
                          "Burst should enter its recording state after the first tap")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.2))
            shutter.tap()
        })
        try assertCaptureModeRow("Burst")
        attachScreenshot(named: "capture-mode-burst-saved")

        try captureMode("filmVideo", start: { shutter in
            shutter.tap()
            XCTAssertTrue(waitUntil(timeout: 8) { shutter.label.contains("Stop capture") },
                          "Film Video should start recording")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 2.0))
            shutter.tap()
        })
        try assertCaptureModeRow("Film Video")
        attachScreenshot(named: "capture-mode-film-video-saved")

        try captureMode("night", start: { shutter in
            shutter.tap()
        })
        try assertCaptureModeRow("Filmy Night")
        attachScreenshot(named: "capture-mode-night-saved")
    }

    func testPhysicalFujiFilmBracketSavesThreeDevelopedOutputs() throws {
        launchNormalCamera()
        let menu = app.buttons["fuji-q-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10) && menu.isEnabled,
                      "The physical camera must expose the Fuji Q menu")
        try chooseFujiDrive(menu: menu, title: "Film simulation bracketing")

        let before = try rollFrameIDs()
        XCTAssertTrue(waitForLiveShutter(), "The camera must remain live after selecting film bracketing")
        app.buttons["Capture photo"].tap()
        assertFujiFinished("Film simulation bracketing")
        try assertRollDelta(from: before, exact: 3, name: "film-bracket")
        attachScreenshot(named: "fuji-film-bracket-saved")

        // Successful film-bracket source JPEGs are intentionally removed after
        // their three developed Photos exports complete.
    }

    func testPhysicalFujiComputationalNDMultipleExposureAndPreShotControls() throws {
        launchNormalCamera()
        let menu = app.buttons["fuji-q-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10) && menu.isEnabled,
                      "The physical camera must expose the Fuji Q menu")

        try chooseFujiDrive(menu: menu, title: "Computational ND")
        let ndBefore = try rollFrameIDs()
        XCTAssertTrue(waitForLiveShutter(), "The preview must remain live after selecting Computational ND")
        app.buttons["Capture photo"].tap()
        assertFujiFinished("Computational ND")
        try assertRollDelta(from: ndBefore, exact: 1, name: "computational-nd")
        try assertRetainedFujiOriginal(prefix: "Computational ND 1/")
        attachScreenshot(named: "fuji-computational-nd-saved")

        try chooseFujiDrive(menu: menu, title: "Multiple exposure")
        let multipleBefore = try rollFrameIDs()
        XCTAssertTrue(waitForLiveShutter(), "The preview must remain live after selecting Multiple Exposure")
        app.buttons["Capture photo"].tap()
        XCTAssertTrue(waitUntil(timeout: 60) {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Compose the next layer'" )).firstMatch.exists
        }, "Multiple Exposure must retain the first layer and request the next shutter")
        app.buttons["Capture photo"].tap()
        assertFujiFinished("Multiple exposure")
        try assertRollDelta(from: multipleBefore, exact: 1, name: "multiple-exposure")
        try assertRetainedFujiOriginal(prefix: "Multiple exposure layer 1/")
        attachScreenshot(named: "fuji-multiple-exposure-saved")

        try configurePreShot(menu: menu)

        let preShotBefore = try rollFrameIDs()
        XCTAssertTrue(waitForLiveShutter(), "The preview must remain live after configuring the Fuji controls")
        app.buttons["Capture photo"].tap()
        assertFujiFinished("Single frame")
        try assertRollDelta(from: preShotBefore, minimum: 2, name: "pre-shot")
        attachScreenshot(named: "fuji-pre-shot-saved")
    }

    private func launchNormalCamera() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-real-roll"]
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.PhysicalCapture.\(UUID().uuidString)"
        app.launch()
        dismissOnboardingIfPresent()
        resolvePhotosAccessIfNeeded()
        XCTAssertTrue(waitForLiveShutter(timeout: 30), "A physical camera preview must become live")
    }

    private func openCaptureModes() {
        let entry = app.buttons["open-capture-modes"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10) && entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.otherElements["capture-modes-viewfinder"].waitForExistence(timeout: 20))
    }

    private func captureMode(_ identifier: String, start: (XCUIElement) -> Void) throws {
        let mode = app.buttons["capture-mode-\(identifier)"]
        XCTAssertTrue(mode.waitForExistence(timeout: 8), "Capture mode \(identifier) must be exposed")
        guard mode.isEnabled, mode.isHittable else {
            throw XCTSkip("The device reported capture mode \(identifier) as unavailable")
        }
        mode.tap()
        let shutter = app.descendants(matching: .any)["capture-modes-shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15), "Capture mode \(identifier) must expose its shutter")
        guard shutter.isEnabled else {
            throw XCTSkip("The device reported capture mode \(identifier) shutter as unavailable")
        }
        start(shutter)
        XCTAssertTrue(waitUntil(timeout: 60) {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Saved in Filmy Captures'" )).firstMatch.exists
        }, "Capture mode \(identifier) must finish with a persisted Filmy Capture")
    }

    private func assertCaptureModeRow(_ title: String) throws {
        app.buttons["open-mode-captures"].tap()
        XCTAssertTrue(app.staticTexts["Filmy Captures"].waitForExistence(timeout: 10))
        // Scope to the list rows so the mode bar behind the sheet or the save
        // toast cannot satisfy the query. A row may expose its texts as
        // children or as one combined label on the cell, so check both.
        func rowsContain(_ text: String) -> Bool {
            let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
            return app.cells.matching(predicate).firstMatch.exists
                || app.cells.descendants(matching: .any).matching(predicate).firstMatch.exists
        }
        XCTAssertTrue(waitUntil(timeout: 20) { rowsContain(title) }, "Saved \(title) capture must retain its mode record")
        XCTAssertTrue(rowsContain("originals"), "Saved \(title) capture must expose retained original sources")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.exists)
        done.tap()
    }

    private func chooseFujiDrive(menu: XCUIElement, title: String) throws {
        menu.tap()
        let drive = app.buttons["fuji-q-drive"]
        XCTAssertTrue(drive.waitForExistence(timeout: 8) && drive.isEnabled,
                      "The Fuji drive control must be available")
        drive.tap()
        let mode = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Mode'")
        ).firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 8), "The Fuji drive picker must expose Mode")
        mode.tap()
        let choice = app.buttons[title].exists ? app.buttons[title] : app.staticTexts[title]
        XCTAssertTrue(choice.waitForExistence(timeout: 8), "The Fuji drive picker must expose \(title)")
        choice.tap()
        app.buttons["Back"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "The Fuji Q menu must expose Done after changing drive")
        done.tap()
        XCTAssertTrue(waitForLiveShutter(), "The camera must return to a live view after changing Fuji drive")
    }

    private func configurePreShot(menu: XCUIElement) throws {
        try chooseFujiDrive(menu: menu, title: "Single frame")
        menu.tap()
        let preShot = app.buttons["fuji-q-preShot"]
        XCTAssertTrue(preShot.waitForExistence(timeout: 8) && preShot.isEnabled,
                      "The Fuji Q menu must expose Pre-Shot Buffer")
        preShot.tap()
        let buffer = app.descendants(matching: .any)["Buffer"]
        XCTAssertTrue(buffer.waitForExistence(timeout: 8), "Pre-Shot Buffer must expose its Buffer picker")
        let oneSecond = app.buttons["1 second"]
        if oneSecond.exists && oneSecond.isEnabled {
            oneSecond.tap()
        } else {
            buffer.tap()
            XCTAssertTrue(app.buttons["1 second"].waitForExistence(timeout: 5),
                          "Pre-Shot Buffer must expose a selectable one-second duration")
            app.buttons["1 second"].tap()
        }
        app.buttons["Back"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "The Fuji Q menu must expose Done after configuring Pre-Shot")
        done.tap()
        XCTAssertTrue(waitForLiveShutter(), "The camera must return to a live view after configuring Pre-Shot")
    }

    private func assertFujiFinished(_ drive: String) {
        let status = app.descendants(matching: .any)["fuji-shooting-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Fuji \(drive) capture must expose its active status")
        XCTAssertTrue(waitUntil(timeout: 60) {
            !status.exists && !app.buttons["Cancel"].exists && !app.buttons["Discard layers"].exists
        }, "Fuji \(drive) capture must finish and dismiss its busy/composing overlay")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'error'" )).firstMatch.exists,
                       "Fuji \(drive) capture must not finish in an error state")
        XCTAssertTrue(app.buttons["Open roll"].exists, "The normal Roll entry must remain reachable after Fuji capture")
    }

    private func rollFrameIDs() throws -> Set<String> {
        let roll = app.buttons["Open roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15), "The normal Roll entry must remain reachable")
        roll.tap()
        XCTAssertTrue(app.staticTexts["Roll"].waitForExistence(timeout: 15))
        resolvePhotosAccessIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        let ids = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'roll-frame-'" )).allElementsBoundByIndex.map(\.identifier))
        let back = app.buttons["roll-back-to-camera"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Roll must provide a camera return path")
        back.tap()
        XCTAssertTrue(waitForLiveShutter(), "Returning from Roll must restore the live camera")
        return ids
    }

    private func assertRollDelta(from before: Set<String>, exact: Int? = nil, minimum: Int? = nil, name: String) throws {
        let after = try rollFrameIDs()
        let delta = after.subtracting(before)
        if let exact { XCTAssertEqual(delta.count, exact, "\(name) must add exactly \(exact) Roll frames") }
        if let minimum { XCTAssertGreaterThanOrEqual(delta.count, minimum, "\(name) must add at least \(minimum) Roll frames") }
    }

    private func assertRetainedFujiOriginal(prefix: String) throws {
        let menu = app.buttons["fuji-q-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10) && menu.isEnabled)
        menu.tap()
        let raw = app.buttons["fuji-q-rawDevelopment"]
        XCTAssertTrue(raw.waitForExistence(timeout: 8) && raw.isEnabled,
                      "Fuji RAW development must be available to inspect retained sequence sources")
        raw.tap()
        XCTAssertTrue(app.staticTexts["RAW Develop"].waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch.waitForExistence(timeout: 20),
            "Fuji originals must retain a source labeled \(prefix)"
        )
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForLiveShutter(), "The camera must return live after inspecting Fuji originals")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForLiveShutter(timeout: TimeInterval = 20) -> Bool {
        let shutter = app.buttons["Capture photo"]
        let preview = app.descendants(matching: .any)["camera-preview"]
        return waitUntil(timeout: timeout) {
            shutter.exists && shutter.isEnabled && preview.exists && preview.label == "Live camera preview"
        }
    }

    private func assertAutomaticSave() {
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved with '" )).firstMatch
        XCTAssertTrue(waitUntil(timeout: 45) {
            resolvePhotosAccessIfNeeded()
            return saved.exists
        }, "Physical capture must save directly to Photos")
        XCTAssertFalse(app.descendants(matching: .any)["capture-save-recovery"].exists)
    }

    @discardableResult
    private func resolvePhotosAccessIfNeeded() -> Bool {
        var handled = false
        for application in [app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let alert = application.alerts.firstMatch
            guard alert.exists else { continue }
            for title in ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK"] {
                if alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    handled = true
                    break
                }
            }
        }
        let inApp = app.buttons["Allow Photos access"]
        if inApp.exists && inApp.isHittable { inApp.tap(); handled = true }
        return handled
    }

    private func dismissOnboardingIfPresent() {
        for title in ["Skip", "Continue"] {
            let button = app.buttons[title]
            if button.waitForExistence(timeout: 2) { button.tap() }
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
}


/// Physical acceptance for interval, focus stacking and reference import.
@MainActor
final class PhysicalFeatureGapTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
            "These cases save real camera originals; set FILMY_RUN_PHOTOS_WRITE=1"
        )
    }

    private func launchPhysicalCamera() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-real-roll"]
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.PhysicalFeatureGap.\(UUID().uuidString)"
        app.launch()
        for title in ["Skip", "Continue"] {
            let button = app.buttons[title]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
        resolvePhotosAccessIfNeeded()
        XCTAssertTrue(waitForLiveShutter(), "The physical camera must render a live shutter")
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            launchedApp?.terminate()
        }
    }

    func testPhysicalIntervalShootingCompletesAndRetainsRollOutputs() throws {
        launchPhysicalCamera()
        try openFujiDrive("interval")

        guard app.buttons["Use Interval Shooting"].waitForExistence(timeout: 5) else {
            XCTFail("Interval detail must expose Use Interval Shooting on a supported device")
            return
        }
        reduceStepper(containing: "Frames", to: "Frames: 2")
        reduceStepper(containing: "Interval", to: "Interval: 1 seconds")
        app.buttons["Use Interval Shooting"].tap()
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForLiveShutter(), "Selecting interval shooting must return to a live shutter")

        let before = try rollFrameIDs()
        app.buttons["Capture photo"].tap()
        try assertFujiFinished("Interval shooting")
        try assertRollDelta(from: before, exact: 2, name: "interval")
    }

    func testPhysicalFocusStackCompletesOrReportsLensCapabilityAndRetainsOriginals() throws {
        launchPhysicalCamera()
        try openFujiDrive("focusStack")

        guard app.buttons["Use Focus Stacking · fused image"].waitForExistence(timeout: 5) else {
            let unavailable = app.staticTexts["Focus bracketing requires a lens with manual focus control."]
            if unavailable.exists {
                throw XCTSkip(unavailable.label)
            }
            XCTFail("Focus detail must expose the fused-image action or the exact manual-focus capability error")
            return
        }
        reduceStepper(containing: "Positions", to: "Positions: 2")
        app.buttons["Use Focus Stacking · fused image"].tap()
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForLiveShutter(), "Selecting focus stacking must return to a live shutter")
        let before = try rollFrameIDs()
        app.buttons["Capture photo"].tap()
        try assertFujiFinished("Focus stacking")
        try assertRollDelta(from: before, exact: 1, name: "focus-stack")
        try assertRetainedFujiOriginals(prefixes: ["Focus stacking 1/2", "Focus stacking 2/2"])
    }

    func testPhysicalFreshPhotoDrivesReferenceOverlaySplitAndRemoval() throws {
        launchPhysicalCamera()
        // Establish a fresh app-owned image before entering the reference picker.
        app.buttons["Capture photo"].tap()
        XCTAssertTrue(waitForSavedToast(timeout: 45))
        XCTAssertTrue(waitForLiveShutter())

        app.buttons["open-capture-modes"].tap()
        XCTAssertTrue(app.otherElements["capture-modes-viewfinder"].waitForExistence(timeout: 10))
        app.buttons["Reference image"].tap()
        let choose = app.buttons["choose-reference-image"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        selectMostRecentPhoto()

        let overlay = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Reference image' AND label CONTAINS[c] 'not included'")
        ).firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 15), "Imported reference must publish the non-destructive overlay")
        XCTAssertTrue(app.switches["Side-by-side comparison"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Mirror reference"].waitForExistence(timeout: 5))
        app.switches["Side-by-side comparison"].tap()
        app.switches["Mirror reference"].tap()
        app.sliders["Reference opacity"].adjust(toNormalizedSliderPosition: 0.7)
        app.sliders["Reference scale"].adjust(toNormalizedSliderPosition: 0.8)

        app.buttons["Remove reference"].tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "Removing the reference must restore the picker entry point")
    }

    private func openFujiDrive(_ identifier: String) throws {
        let menu = app.buttons["fuji-q-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let control = app.buttons["fuji-q-\(identifier)"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    }

    private func assertFujiFinished(_ drive: String) throws {
        let status = app.descendants(matching: .any)["fuji-shooting-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Fuji \(drive) capture must expose its active status")
        let unsupported = app.staticTexts["Focus bracketing requires a lens with manual focus control."]
        let completed = waitUntil(timeout: 90) {
            unsupported.exists || (!status.exists && !app.buttons["Cancel"].exists && !app.buttons["Discard layers"].exists)
        }
        if drive == "Focus stacking", unsupported.exists { throw XCTSkip(unsupported.label) }
        XCTAssertTrue(completed, "Fuji \(drive) capture must finish and dismiss its busy/composing overlay")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'error'" )).firstMatch.exists)
        XCTAssertTrue(app.buttons["Open roll"].exists)
    }

    private func rollFrameIDs() throws -> Set<String> {
        let roll = app.buttons["Open roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15))
        roll.tap()
        XCTAssertTrue(app.staticTexts["Roll"].waitForExistence(timeout: 15))
        resolvePhotosAccessIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        let ids = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'roll-frame-'" )).allElementsBoundByIndex.map(\.identifier))
        let back = app.buttons["roll-back-to-camera"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(waitForLiveShutter())
        return ids
    }

    private func assertRollDelta(from before: Set<String>, exact: Int, name: String) throws {
        let after = try rollFrameIDs()
        XCTAssertEqual(after.subtracting(before).count, exact, "\(name) must add exactly \(exact) Roll frames")
    }

    private func assertRetainedFujiOriginals(prefixes: [String]) throws {
        app.buttons["fuji-q-menu"].tap()
        let raw = app.buttons["fuji-q-rawDevelopment"]
        XCTAssertTrue(raw.waitForExistence(timeout: 8) && raw.isEnabled)
        raw.tap()
        XCTAssertTrue(app.staticTexts["RAW Develop"].waitForExistence(timeout: 12))
        for prefix in prefixes {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch.waitForExistence(timeout: 20),
                          "Fuji originals must retain a source labeled \(prefix)")
        }
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForLiveShutter())
    }

    private func reduceStepper(containing label: String, to target: String) {
        let value = app.staticTexts[target]
        for _ in 0..<20 {
            if value.exists { return }
            let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            guard row.exists else { break }
            let decrement = app.buttons.allElementsBoundByIndex.first {
                ($0.label.localizedCaseInsensitiveContains("decrease")
                    || $0.label.localizedCaseInsensitiveContains("decrement"))
                    && abs($0.frame.midY - row.frame.midY) < max($0.frame.height, row.frame.height) / 2
            }
            guard let decrement, decrement.isHittable else { break }
            decrement.tap()
        }
        XCTAssertTrue(value.exists, "\(label) must expose the requested minimum value")
    }

    @discardableResult
    private func resolvePhotosAccessIfNeeded() -> Bool {
        for host in [app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let alert = host.alerts.firstMatch
            if alert.exists {
                for title in ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK"] where alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    return true
                }
            }
        }
        let permission = app.buttons["Allow Photos access"]
        if permission.exists && permission.isHittable { permission.tap(); return true }
        return false
    }

    private func selectMostRecentPhoto() {
        let candidate = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info'" )).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 30), "Photos picker must expose the fresh capture")
        candidate.tap()
        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add' OR label CONTAINS[c] 'Choose'" )).firstMatch
        if add.exists { add.tap() }
        XCTAssertTrue(waitUntil(timeout: 10) { app.buttons["choose-reference-image"].exists })
    }

    private func waitForLiveShutter(timeout: TimeInterval = 20) -> Bool {
        let shutter = app.buttons["Capture photo"]
        let preview = app.descendants(matching: .any)["camera-preview"]
        return waitUntil(timeout: timeout) {
            shutter.exists && shutter.isEnabled && preview.exists && preview.label == "Live camera preview"
        }
    }

    private func waitForSavedToast(timeout: TimeInterval) -> Bool {
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved with '" )).firstMatch
        return waitUntil(timeout: timeout) { resolvePhotosAccessIfNeeded(); return saved.exists }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return false
    }
}
