import XCTest

/// Opt-in end-to-end coverage for a disposable simulator whose Photos library
/// contains the public cafe fixture and any built-in simulator sample photos.
/// The normal app path is intentional:
/// `-ui-testing` denies Photos access for the deterministic UI suite.
@MainActor
final class NormalPhotoFlowTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        #if targetEnvironment(simulator)
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_SEEDED_PHOTOS_E2E"] == "1",
            "Set FILMY_RUN_SEEDED_PHOTOS_E2E=1 on a disposable simulator seeded with cafe-original.png"
        )
        #else
        throw XCTSkip("Seeded Photos E2E runs only on a disposable simulator")
        #endif

        addUIInterruptionMonitor(withDescription: "Filmy Camera Photos permissions") { alert in
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

    func testNormalSeededImportSaveRelaunchesIntoRollDetail() throws {
        launchNormalApp()
        try ensureRecipe(id: "g7x-compact", name: "G7 X Compact")
        try importSeededFixture()

        let save = app.buttons["Save filtered photo"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Imported review must offer Save filtered photo")
        save.tap()
        app.tap()
        try waitForSaveCompletion()

        app.terminate()
        launchNormalApp()
        openRoll()

        let savedFrame = app.buttons.matching(
            NSPredicate(format: "label == 'Photo in your gallery, G7 X Compact'")
        ).firstMatch
        XCTAssertTrue(
            savedFrame.waitForExistence(timeout: 30),
            "The saved seeded treatment must survive relaunch and populate Roll"
        )
        savedFrame.tap()

        let photo = app.images["Photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "Saved Roll detail must load its image")
        XCTAssertEqual(photo.value as? String, "Fit to screen")
    }

    func testNormalSeededImportCancelDoesNotCreateRollFrame() throws {
        launchNormalApp(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
        try ensureRecipe(id: "g7x-compact", name: "G7 X Compact")
        openRoll()
        let countBefore = try waitForRollFrameCount()
        app.buttons["roll-back-to-camera"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 10))

        try importSeededFixture(newerSavedFrameCount: countBefore)
        assertReviewControl(app.buttons["review-look-picker"], name: "Large-text review look picker")
        assertReviewControl(app.buttons["review-compare-original"], name: "Large-text Original comparison")
        attachScreenshot(named: "review-large-text")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Imported review must offer Cancel")
        cancel.tap()
        let review = app.descendants(matching: .any)["review-screen"]
        XCTAssertTrue(waitForDisappearance(review, timeout: 10), "Cancel must dismiss imported review")

        openRoll()
        XCTAssertEqual(
            try waitForRollFrameCount(),
            countBefore,
            "Canceling an imported photo must not add an app-owned Roll frame"
        )
    }

    func testNormalReviewComparesAndSwitchesLookBeforeSaving() throws {
        launchNormalApp()
        try ensureRecipe(id: "g7x-compact", name: "G7 X Compact")
        try importSeededFixture()

        let compare = app.buttons["review-compare-original"]
        let lookPicker = app.buttons["review-look-picker"]
        assertReviewControl(compare, name: "Original comparison")
        assertReviewControl(lookPicker, name: "Review look picker")

        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { compare.value as? String == "Original" })
        let photo = app.descendants(matching: .any)["review-image"]
        XCTAssertTrue(photo.label.contains("Original"), "Comparison must identify the source photo")
        attachScreenshot(named: "review-original-portrait")

        lookPicker.tap()
        let monochrome = app.buttons["review-look-acros-monochrome"]
        XCTAssertTrue(monochrome.waitForExistence(timeout: 5), "Look selection must expose the monochrome treatment")
        monochrome.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                photo.label.contains("Fine Monochrome") && app.buttons["Save filtered photo"].isEnabled
            },
            "The finished review must publish the selected look before allowing Save"
        )
        XCTAssertEqual(compare.value as? String, "Look", "Changing a look must return from Original to the treatment")
        XCTAssertFalse(app.descendants(matching: .any)["review-render-error"].exists)

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(
            waitUntil(timeout: 10) { app.frame.width > app.frame.height },
            "The review must settle into landscape before layout assertions"
        )
        assertReviewControl(compare, name: "Landscape Original comparison", containedInApp: true)
        assertReviewControl(lookPicker, name: "Landscape review look picker", containedInApp: true)
        assertReviewControl(
            app.buttons["Save filtered photo"],
            name: "Landscape Save filtered photo",
            containedInApp: true
        )
        attachScreenshot(named: "review-monochrome-landscape")

        // Original is a comparison, never an alternate export. Leave it
        // visible while saving and verify the chosen look survives relaunch.
        compare.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { compare.value as? String == "Original" })
        app.buttons["Save filtered photo"].tap()
        app.tap()
        try waitForSaveCompletion()
        XCTAssertTrue(
            app.buttons["recipe-menu"].label.contains("G7 X Compact"),
            "Trying a review look must not change the next camera shot's look"
        )

        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        launchNormalApp()
        openRoll()
        let savedFrame = app.buttons.matching(
            NSPredicate(format: "label == 'Photo in your gallery, Fine Monochrome'")
        ).firstMatch
        XCTAssertTrue(savedFrame.waitForExistence(timeout: 30), "Save must retain the chosen review look's metadata")
        savedFrame.tap()
        XCTAssertTrue(app.images["Photo"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.images["Photo"].value as? String, "Fit to screen")
    }

    private func assertReviewControl(
        _ element: XCUIElement,
        name: String,
        containedInApp: Bool = false
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(name) must be discoverable")
        XCTAssertTrue(waitUntil(timeout: 5) { element.isHittable }, "\(name) must be reachable without scrolling at normal text size")
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(name) needs a usable touch width")
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(name) needs a usable touch height")
        if containedInApp {
            XCTAssertTrue(
                app.frame.insetBy(dx: -1, dy: -1).contains(element.frame),
                "\(name) must remain entirely inside the landscape app frame"
            )
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchNormalApp(contentSizeCategory: String? = nil) {
        app?.terminate()
        app = XCUIApplication()
        // Deliberately omit -ui-testing so PhotosPicker and the real save path
        // are exercised against the disposable seeded library.
        if let contentSizeCategory {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launch()

        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }
        app.tap()
        XCTAssertTrue(app.buttons["Open roll"].waitForExistence(timeout: 15))
    }

    private func ensureRecipe(id: String, name: String) throws {
        let currentLook = app.buttons["recipe-menu"]
        XCTAssertTrue(currentLook.waitForExistence(timeout: 10))
        guard !currentLook.label.contains(name) else { return }

        currentLook.tap()
        let tile = app.buttons["recipe-\(id)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "The seeded flow must expose \(name)")
        if tile.isHittable {
            tile.tap()
        } else {
            let screen = app.frame
            let frame = tile.frame
            app.coordinate(withNormalizedOffset: CGVector(
                dx: (frame.midX - screen.minX) / screen.width,
                dy: (frame.midY - screen.minY) / screen.height
            )).tap()
        }
        XCTAssertTrue(
            waitUntil(timeout: 10) { currentLook.label.contains(name) },
            "Selecting \(name) must update the current look"
        )
        let close = app.buttons["recipe-drawer-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "The look drawer must remain dismissible")
        close.tap()
        XCTAssertTrue(waitForDisappearance(close, timeout: 5), "Selecting a look must leave the camera controls available")
    }

    private func importSeededFixture(newerSavedFrameCount: Int? = nil) throws {
        let newerFrames: Int
        if let newerSavedFrameCount {
            newerFrames = newerSavedFrameCount
        } else {
            openRoll()
            newerFrames = try waitForRollFrameCount()
            app.buttons["roll-back-to-camera"].tap()
            XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 10))
        }
        let importPhoto = app.buttons["import-photo"]
        XCTAssertTrue(importPhoto.waitForExistence(timeout: 10))
        importPhoto.tap()

        let photos = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        )
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                if photos.count > newerFrames { return true }
                let dismissNotice = app.buttons["Dismiss"]
                if dismissNotice.exists, dismissNotice.isHittable {
                    dismissNotice.tap()
                }
                return false
            },
            "The disposable simulator must expose the seeded cafe fixture. Picker: \(app.debugDescription)"
        )

        // The cafe source is newer than the simulator's stock photos. Saves
        // from earlier cases sort ahead of it; skip exactly the app's Roll
        // count so every case starts from the same unfiltered public fixture.
        let source = photos.element(boundBy: newerFrames)
        let sourceFrame = source.frame
        let appFrame = app.frame
        app.coordinate(withNormalizedOffset: CGVector(
            dx: (sourceFrame.midX - appFrame.minX) / appFrame.width,
            dy: (sourceFrame.midY - appFrame.minY) / appFrame.height
        )).tap()

        XCTAssertTrue(app.staticTexts["IMPORTED PHOTO"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.descendants(matching: .any)["review-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Filter applied'")).firstMatch.exists,
            "Imported review must state the applied resolution"
        )
    }

    private func waitForSaveCompletion() throws {
        let savedToast = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                if savedToast.exists { return true }
                tapPhotosPermissionPromptIfPresent()
                return false
            },
            "The seeded filtered photo must complete its Photos save"
        )
    }

    private func openRoll() {
        let openRoll = app.buttons["Open roll"]
        XCTAssertTrue(openRoll.waitForExistence(timeout: 10))
        openRoll.tap()
        XCTAssertTrue(app.staticTexts["Roll"].waitForExistence(timeout: 15))

        // A fresh XCTest install starts Photos at notDetermined even when the
        // disposable simulator was pre-seeded. Resolve the in-app CTA and the
        // subsequent system prompt while waiting for Roll's loaded or empty
        // state; a missing count is never treated as an empty Roll.
        let loaded = waitUntil(timeout: 30) {
            tapPhotosPermissionPromptIfPresent()
            return rollFrameCount() != nil
        }
        if !loaded {
            XCTFail(
                "Roll did not publish a loaded frame count or empty state after Photos permission handling. " +
                "Permission UI: \(photosPermissionPromptDescription())\nAccessibility tree:\n\(app.debugDescription)"
            )
        }
    }

    @discardableResult
    private func tapPhotosPermissionPromptIfPresent() -> Bool {
        let appPermissionButton = app.buttons["Allow Photos access"]
        if appPermissionButton.exists, appPermissionButton.isHittable {
            appPermissionButton.tap()
            return true
        }

        let permissionTitles = ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK"]
        let applications: [XCUIApplication] = [
            app,
            XCUIApplication(bundleIdentifier: "com.apple.springboard")
        ]
        for application in applications {
            let alert = application.alerts.firstMatch
            guard alert.exists else { continue }
            for title in permissionTitles {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
        }
        return false
    }

    private func photosPermissionPromptDescription() -> String {
        if app.buttons["Allow Photos access"].exists {
            return "in-app Allow Photos access CTA remains"
        }
        if app.buttons["Open Settings"].exists {
            return "Photos access is denied or restricted"
        }
        if XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists {
            return "system Photos permission alert remains"
        }
        return "no permission prompt visible"
    }

    private func rollFrameCount() -> Int? {
        for label in app.staticTexts.allElementsBoundByIndex.map(\.label)
            where label.hasSuffix(" frames") {
            if let count = Int(label.dropLast(" frames".count)) {
                return count
            }
        }
        if app.staticTexts["Your frames will live here"].exists
            || app.staticTexts["Your selected roll is empty"].exists {
            return 0
        }
        return nil
    }

    private func waitForRollFrameCount() throws -> Int {
        let loaded = waitUntil(timeout: 30) { rollFrameCount() != nil }
        if !loaded {
            XCTFail(
                "Roll did not publish a loaded frame count or empty state. Accessibility tree:\n\(app.debugDescription)"
            )
        }
        return try XCTUnwrap(rollFrameCount())
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
