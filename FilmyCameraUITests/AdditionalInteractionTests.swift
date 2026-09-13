import XCTest

/// Reuses the three retained Roll QA frames. No Photos writes, deletes, or
/// outgoing shares; normal preferences are restored before the test finishes.
@MainActor
final class AdditionalInteractionTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Additional interaction acceptance requires physical camera hardware")
        #endif
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
            launchedApp?.terminate()
        }
    }

    func testNormalFlashSettingsAndRollLayoutPersistAndDeleteCanBeCanceled() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_ROLL_QA"] == "1",
                          "Set FILMY_RUN_ROLL_QA=1 after the three Roll QA frames have been saved")
        launch(isolated: false)
        XCTAssertTrue(waitForFreshCameraFrames())
        try exerciseFlashSettingsAndRestore()
        try exerciseRollLayoutAndDeleteCancellation()
    }

    func testBackgroundingDuringCountdownPreventsTheShotAndReturnsFreshPreview() {
        launch(isolated: true)
        XCTAssertTrue(waitForFreshCameraFrames())
        let recipeBefore = app.buttons["recipe-menu"].label
        app.buttons["capture-setup-open"].tap()
        let picker = app.descendants(matching: .any)["capture-delay-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["5s"].tap()
        dismissBanner()
        app.buttons["capture-setup-done"].tap()
        XCTAssertTrue(waitUntil { !self.app.buttons["capture-setup-done"].exists })
        XCTAssertTrue(waitUntil {
            (self.app.buttons["capture-setup-open"].value as? String)?
                .components(separatedBy: ", ").contains("Timer 5s") == true
        }, "The setup summary must read back the selected five-second timer")
        XCTAssertTrue(waitForFreshCameraFrames())

        let started = Date()
        app.buttons["Capture photo"].tap()
        XCTAssertTrue(app.buttons["capture-countdown-cancel"].waitForExistence(timeout: 1))
        XCUIDevice.shared.press(.home)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5,
                          "The app must leave the foreground before the actual timer deadline")
        RunLoop.current.run(until: started.addingTimeInterval(6))
        app.activate()
        dismissBanner()
        let review = app.descendants(matching: .any)["review-image"]
        XCTAssertFalse(review.exists, "A backgrounded countdown must not deliver a capture review")
        XCTAssertFalse(app.buttons["capture-countdown-cancel"].exists)
        XCTAssertTrue(waitForFreshCameraFrames(), "Returning must restore two fresh rendered preview tokens")
        let staleShot = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: review)
        staleShot.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [staleShot], timeout: 2), .completed,
                       "No canceled timer completion may arrive after foregrounding")
        XCTAssertEqual(app.buttons["recipe-menu"].label, recipeBefore)
        attach("timer-background-cancellation-live-preview")
    }

    private func exerciseFlashSettingsAndRestore() throws {
        let flash = app.buttons["flash-control"]
        try XCTSkipUnless(flash.exists && flash.isEnabled,
                          "Flash settings acceptance needs an available flash on the active camera")
        let original = try XCTUnwrap(flash.value as? String)
        XCTAssertTrue(["Off", "Auto", "On"].contains(original))
        record("Original normal flash mode: \(original)", named: "flash-preference-before-qa")
        defer { restoreFlash(original) }

        for mode in ["Off", "Auto", "On"] {
            openSettings()
            let segment = app.descendants(matching: .any)["flash-setting"].buttons[mode]
            XCTAssertTrue(segment.waitForExistence(timeout: 5) && segment.isEnabled && segment.isHittable)
            segment.tap()
            XCTAssertTrue(waitUntil { segment.isSelected || segment.value as? String == "1" },
                          "Settings must show the selected \(mode) flash segment")
            attach("settings-flash-\(mode.lowercased())")
            returnFromSettings()
            XCTAssertTrue(waitUntil { flash.value as? String == mode },
                          "The viewfinder must read back the Settings flash selection")
        }

        app.terminate()
        app.launch()
        dismissBanner()
        XCTAssertTrue(waitForFreshCameraFrames())
        XCTAssertEqual(flash.value as? String, "On", "Normal launch must restore the persisted flash choice")
        openSettings()
        let on = app.descendants(matching: .any)["flash-setting"].buttons["On"]
        XCTAssertTrue(on.waitForExistence(timeout: 5))
        XCTAssertTrue(on.isSelected || on.value as? String == "1")
        returnFromSettings()
        restoreFlash(original)
        app.terminate()
        app.launch()
        dismissBanner()
        XCTAssertTrue(waitForFreshCameraFrames())
        XCTAssertEqual(flash.value as? String, original, "Restore must survive a fresh normal launch")
    }

    private func exerciseRollLayoutAndDeleteCancellation() throws {
        openRoll()
        let layout = app.buttons["roll-grid-layout"]
        let original = try XCTUnwrap(layout.value as? String)
        XCTAssertTrue(["Roomy grid", "Contact sheet"].contains(original))
        let changed = original == "Roomy grid" ? "Contact sheet" : "Roomy grid"
        let originalCount = try XCTUnwrap(rollFrameCount())
        record("Original Roll layout: \(original); frame count: \(originalCount)", named: "roll-preference-before-qa")
        defer { restoreRollLayout(original) }

        layout.tap()
        XCTAssertTrue(waitUntil { layout.value as? String == changed })
        attach("roll-layout-changed")
        app.buttons["roll-back-to-camera"].tap()
        openRoll()
        XCTAssertEqual(layout.value as? String, changed)
        app.terminate()
        app.launch()
        dismissBanner()
        XCTAssertTrue(waitForFreshCameraFrames())
        openRoll()
        XCTAssertEqual(layout.value as? String, changed, "Roll layout must survive relaunch")
        XCTAssertEqual(rollFrameCount(), originalCount)
        restoreRollLayout(original)
        XCTAssertEqual(layout.value as? String, original)

        // The known Vivid Slide treatment is the newest of the three retained
        // QA frames; never use an arbitrary personal asset for this dialog.
        let qaFrame = app.buttons.matching(NSPredicate(format:
            "label == 'Photo in your gallery, Vivid Slide'")).firstMatch
        XCTAssertTrue(qaFrame.waitForExistence(timeout: 10) && qaFrame.isHittable)
        let cacheOnlyRoll = app.staticTexts["Local cache"].exists
        qaFrame.tap()
        let photo = app.images["Photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 20))
        let metadata = app.descendants(matching: .any)["gallery-frame-metadata"]
        XCTAssertTrue(metadata.label.contains("Vivid Slide"))
        let originalMetadata = metadata.label
        let position = app.descendants(matching: .any)["gallery-frame-position"]
        let originalPosition = position.value as? String
        let delete = app.buttons["Delete frame"]
        if delete.exists {
            XCTAssertTrue(delete.isEnabled)
            delete.tap()
            XCTAssertTrue(app.buttons["Delete Frame"].waitForExistence(timeout: 5))
            attach("qa-frame-delete-confirmation-before-cancel")
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.isHittable)
            cancel.tap()
            XCTAssertTrue(waitUntil { !self.app.buttons["Delete Frame"].exists })
            XCTAssertTrue(photo.exists)
            XCTAssertEqual(metadata.label, originalMetadata)
            XCTAssertEqual(position.value as? String, originalPosition)
            XCTAssertTrue(app.buttons["Share frame"].isEnabled)
            attach("qa-frame-delete-canceled")
        } else {
            XCTAssertTrue(cacheOnlyRoll, "A cache-only Roll may omit Photos deletion; other cases need separate evidence")
            XCTAssertFalse(delete.exists, "A local cached frame must not expose a Photos delete action")
            attach("cache-only-qa-frame-has-no-photos-delete")
        }
        app.buttons["Close frame"].tap()
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        XCTAssertEqual(rollFrameCount(), originalCount, "Canceling Delete must retain every Roll frame")
        XCTAssertEqual(layout.value as? String, original)
        app.buttons["roll-back-to-camera"].tap()
        XCTAssertTrue(waitForFreshCameraFrames())
    }

    private func launch(isolated: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = isolated ? ["-ui-testing", "-selectedRecipeID", "classic-chrome"] : ["-ui-testing-preview-status"]
        if isolated {
            app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Additional.\(UUID().uuidString)"
        }
        app.launch()
        let skip = app.buttons["onboarding-skip"]
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        dismissBanner()
    }

    private func openSettings() {
        dismissBanner()
        let settings = app.buttons["settings-tab"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10) && settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.buttons["settings-back-to-camera"].waitForExistence(timeout: 5))
    }

    private func returnFromSettings() {
        dismissBanner()
        app.buttons["settings-back-to-camera"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
    }

    private func openRoll() {
        dismissBanner()
        let roll = app.buttons["roll-tab"]
        XCTAssertTrue(roll.waitForExistence(timeout: 10) && roll.isHittable)
        roll.tap()
        XCTAssertTrue(app.buttons["roll-grid-layout"].waitForExistence(timeout: 15))
    }

    private func restoreFlash(_ original: String) {
        if app.state != .runningForeground { app.activate() }
        dismissBanner()
        if app.buttons["settings-back-to-camera"].exists { returnFromSettings() }
        let flash = app.buttons["flash-control"]
        for _ in 0..<3 where flash.exists && flash.isEnabled && flash.value as? String != original {
            let before = flash.value as? String
            flash.tap()
            XCTAssertTrue(waitUntil { flash.value as? String != before })
        }
        XCTAssertEqual(flash.value as? String, original, "Restore the original flash mode")
    }

    private func restoreRollLayout(_ original: String) {
        if app.state != .runningForeground { app.activate() }
        dismissBanner()
        if app.buttons["Delete Frame"].exists && app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        if app.buttons["Close frame"].exists {
            app.buttons["Close frame"].tap()
            XCTAssertTrue(app.buttons["roll-grid-layout"].waitForExistence(timeout: 5))
        }
        if !app.buttons["roll-grid-layout"].exists { openRoll() }
        let layout = app.buttons["roll-grid-layout"]
        if layout.value as? String != original { layout.tap() }
        XCTAssertTrue(waitUntil { layout.value as? String == original }, "Restore the original Roll layout")
    }

    private func rollFrameCount() -> Int? {
        for text in app.staticTexts.allElementsBoundByIndex.map(\.label) where text.hasSuffix(" frames") {
            if let count = Int(text.dropLast(" frames".count)) { return count }
        }
        return nil
    }

    private func dismissBanner() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard
            .descendants(matching: .any)["NotificationShortLookView"].firstMatch
        if banner.exists {
            // The banner can expire between the existence check and event
            // delivery. Anchor dismissal to the screen, not the transient node.
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                .press(forDuration: 0.01, thenDragTo:
                    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)))
        }
        if app.state != .runningForeground { app.activate() }
        XCTAssertTrue(waitUntil(timeout: 12) { !banner.exists },
                      "Wait until the notification no longer covers app controls")
    }

    private func waitForFreshCameraFrames() -> Bool {
        let preview = app.descendants(matching: .any)["camera-preview-render-status"]
        var firstToken: String?
        return waitUntil(timeout: 25) {
            guard self.app.buttons["Capture photo"].exists,
                  self.app.buttons["Capture photo"].isEnabled, preview.exists,
                  let token = preview.value as? String, token.hasPrefix("state=rendered;") else { return false }
            if let firstToken { return token != firstToken }
            firstToken = token
            return false
        }
    }

    private func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return condition()
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func record(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
