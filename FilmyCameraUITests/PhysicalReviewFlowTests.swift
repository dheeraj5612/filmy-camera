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
        XCTAssertTrue(app.buttons["roll-back-to-camera"].waitForExistence(timeout: 10))
        app.buttons["roll-back-to-camera"].tap()
        XCTAssertTrue(app.buttons["import-photo"].waitForExistence(timeout: 15))

        // Import one real library photo through the system picker. The picker is the
        // user's existing library; there is no fixture or synthetic image in this test.
        app.buttons["import-photo"].tap()
        let firstPhoto = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        ).firstMatch
        guard firstPhoto.waitForExistence(timeout: 30) else {
            app.buttons["Cancel"].firstMatch.tap()
            throw XCTSkip("The connected device has no photo available in the system picker")
        }
        tapCenter(of: firstPhoto)

        XCTAssertTrue(app.staticTexts["IMPORTED PHOTO"].waitForExistence(timeout: 40))
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
        let close = app.buttons["recipe-drawer-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
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
