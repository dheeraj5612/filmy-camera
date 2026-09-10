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
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "GalleryPagingUITests.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing-preview-status", "-selectedRecipeID", "classic-chrome"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let skip = app.buttons["onboarding-skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        app.tap()

        let recipes = [("classic-chrome", "Muted Color"), ("acros-monochrome", "Fine Monochrome"), ("velvia-vivid", "Vivid Slide")]
        for (index, recipe) in recipes.enumerated() {
            XCTAssertTrue(waitForFreshCameraFrames(), "Each QA capture needs two fresh physical viewfinder frames")
            app.buttons["Capture photo"].tap()
            let keep = app.buttons["Keep frame"]
            XCTAssertTrue(keep.waitForExistence(timeout: 40))
            let reviewImage = app.descendants(matching: .any)["review-image"]
            if !reviewImage.label.contains(recipe.1) {
                app.buttons["review-look-picker"].tap()
                let search = app.textFields["look-library-search"]
                XCTAssertTrue(search.waitForExistence(timeout: 10))
                let clear = app.buttons["look-library-clear-search"]
                if clear.exists { clear.tap() }
                app.buttons["look-filter-all"].tap()
                search.tap()
                search.typeText(recipe.1 + "\n")
                let option = app.buttons["review-look-\(recipe.0)"]
                XCTAssertTrue(option.waitForExistence(timeout: 10) && option.isHittable)
                option.tap()
            }
            XCTAssertTrue(waitUntil(timeout: 30) { reviewImage.label.contains(recipe.1) && keep.isEnabled })
            attach("roll-paging-capture-\(index + 1)-\(recipe.0)")
            keep.tap()
            app.tap()
            let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved with '")).firstMatch
            XCTAssertTrue(saved.waitForExistence(timeout: 30), "QA frame must be accepted by Photos")
            XCTAssertTrue(saved.label.contains(recipe.1))
            XCTAssertTrue(waitUntil(timeout: 10) { !keep.exists })
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

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.frame.width > self.app.frame.height })
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(position.frame))
        photo.swipeRight()
        assertFrame(1, recipe: "Vivid Slide")
        photo.swipeLeft()
        assertFrame(2, recipe: "Fine Monochrome")
        attach("roll-paging-landscape-second-frame")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.frame.height > self.app.frame.width })

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
}
