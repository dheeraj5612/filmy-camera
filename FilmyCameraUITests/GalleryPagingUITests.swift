import XCTest

/// Saves three new QA frames and keeps them. Never deletes a frame, opens a
/// recipient, or sends from the share sheet. Requires explicit write opt-in.
@MainActor
final class GalleryPagingUITests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Roll capture paging acceptance requires a physical iPhone or iPad")
        #else
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
                          "Set FILMY_RUN_PHOTOS_WRITE=1 to keep three new QA photos")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_ROLL_QA"] == "1",
                          "Set FILMY_RUN_ROLL_QA=1 to run physical Roll paging acceptance")
        #endif
        addUIInterruptionMonitor(withDescription: "Roll paging camera and Photos permissions") { alert in
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

    func testPhysicalRollSwipesFreshFramesAndPreservesZoomAndShare() throws {
        app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.GalleryPaging.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing-real-roll", "-selectedRecipeID", "classic-chrome"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let skip = app.buttons["onboarding-skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        app.tap()

        let recipes = [("classic-chrome", "Muted Color"), ("acros-monochrome", "Fine Monochrome"), ("velvia-vivid", "Vivid Slide")]
        for (index, recipe) in recipes.enumerated() {
            try ensureRecipe(id: recipe.0, name: recipe.1)
            XCTAssertTrue(waitForFreshCameraFrames(), "Each QA capture needs two fresh physical viewfinder frames")
            app.buttons["Capture photo"].tap()
            let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved with '")).firstMatch
            XCTAssertTrue(waitUntil(timeout: 45) { saved.exists }, "Capture must auto-save on physical devices")
            XCTAssertFalse(app.buttons["Keep frame"].exists)
            XCTAssertTrue(saved.label.contains(recipe.1))
            attach("roll-paging-capture-\(index + 1)-\(recipe.0)")
        }

        app.buttons["Open roll"].tap()
        let newest = app.buttons.matching(NSPredicate(format: "label == 'Photo in your gallery, Vivid Slide'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 30))
        attach("roll-paging-three-fresh-frames")
        newest.tap()
        assertFrame(1, recipe: "Vivid Slide")
        XCTAssertFalse(app.buttons["gallery-previous-frame"].isEnabled)
        photo.swipeRight()
        assertFrame(1, recipe: "Vivid Slide")

        photo.swipeLeft()
        assertFrame(2, recipe: "Fine Monochrome")
        photo.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(waitUntil(timeout: 5) { (self.photo.value as? String)?.hasPrefix("Zoomed ") == true })
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55)).press(
            forDuration: 0.1,
            thenDragTo: photo.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
        )
        XCTAssertTrue((position.value as? String)?.hasPrefix("2 of ") == true,
                      "Panning a zoomed image must keep the selected frame")
        XCTAssertTrue((photo.value as? String)?.hasPrefix("Zoomed ") == true)
        attach("roll-paging-zoomed-pan-stays-on-second-frame")
        photo.doubleTap()
        XCTAssertTrue(waitUntil(timeout: 5) { self.photo.value as? String == "Fit to screen" })

        photo.swipeLeft()
        assertFrame(3, recipe: "Muted Color")
        photo.swipeRight()
        assertFrame(2, recipe: "Fine Monochrome")
        app.buttons["gallery-previous-frame"].tap()
        assertFrame(1, recipe: "Vivid Slide")
        app.buttons["gallery-next-frame"].tap()
        assertFrame(2, recipe: "Fine Monochrome")

        // Button navigation also resets zoom, so a frame cannot inherit its
        // neighbour's magnification and crop.
        photo.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(waitUntil(timeout: 5) { (self.photo.value as? String)?.hasPrefix("Zoomed ") == true })
        app.buttons["gallery-next-frame"].tap()
        assertFrame(3, recipe: "Muted Color")
        app.buttons["gallery-previous-frame"].tap()
        assertFrame(2, recipe: "Fine Monochrome")

        // The product locks this flow to portrait; verify geometry remains stable.
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.frame.height >= self.app.frame.width })
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(position.frame))

        // The active frame is the distinct monochrome treatment, making the
        // share preview reviewable against the visible Roll frame screenshot.
        attach("roll-paging-active-monochrome-before-share")
        app.buttons["Share frame"].tap()
        let copy = app.descendants(matching: .any)["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 30))
        attach("roll-paging-active-monochrome-share-preview")
        let close = app.descendants(matching: .any)["Close"]
        if close.exists && close.isHittable {
            close.tap()
        } else {
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            sheet.swipeDown()
        }
        XCTAssertTrue(waitUntil(timeout: 10) { !copy.exists })
        assertFrame(2, recipe: "Fine Monochrome")
        app.buttons["frame-back-to-camera"].tap()
        XCTAssertTrue(waitForFreshCameraFrames())
    }

    private var photo: XCUIElement { app.images["Photo"] }
    private var position: XCUIElement { app.descendants(matching: .any)["gallery-frame-position"] }

    private func assertFrame(_ number: Int, recipe: String) {
        XCTAssertTrue(waitUntil(timeout: 30) {
            self.photo.exists && self.photo.value as? String == "Fit to screen"
                && (self.position.value as? String)?.hasPrefix("\(number) of ") == true
                && self.app.buttons["Share frame"].isEnabled
        }, "The expected frame must finish loading at fit zoom")
        let metadata = app.descendants(matching: .any)["gallery-frame-metadata"]
        XCTAssertTrue(metadata.label.contains(recipe), "Paging must update metadata to \(recipe): \(metadata.label)")
    }

    private func waitForFreshCameraFrames() -> Bool {
        var firstToken: String?
        return waitUntil(timeout: 25) {
            let preview = self.app.descendants(matching: .any)["camera-preview-render-status"]
            guard self.app.buttons["Capture photo"].isEnabled, preview.exists,
                  let token = preview.value as? String, token.hasPrefix("state=rendered;") else { return false }
            if let firstToken { return token != firstToken }
            firstToken = token
            return false
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        return condition()
    }

    private func attach(_ name: String) {
        // UIKit reports the new frame before the orientation animation ends.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.7))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func ensureRecipe(id: String, name: String) throws {
        let menu = app.buttons["recipe-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        guard !menu.label.contains(name) else { return }
        menu.tap()
        let tile = app.buttons["recipe-\(id)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        let picker = app.scrollViews["recipe-picker"]
        let deadline = Date(timeIntervalSinceNow: 8)
        while !tile.isHittable && Date() < deadline { picker.swipeUp() }
        XCTAssertTrue(tile.isHittable, "Recipe \(name) must be selectable")
        tile.tap()
        let close = app.buttons["recipe-drawer-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Recipe picker must expose its close control")
        close.tap()
        XCTAssertTrue(waitUntil(timeout: 5) {
            !app.descendants(matching: .any)["recipe-drawer"].exists
                && menu.label.contains(name)
                && app.buttons["Capture photo"].isEnabled
                && app.buttons["Capture photo"].isHittable
        }, "Selecting \(name) must dismiss the picker and restore the shutter")
    }

}
