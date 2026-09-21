import XCTest

/// Camera discovery stays deterministic and never touches the user's Photos.
/// Split comparison uses the separate, existing seeded Photos lane.
@MainActor
final class SignalFrameUITests: XCTestCase {
    func testCameraFavoriteAndQuickRailSharePersistentLibraryState() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        let look = app.buttons["recipe-menu"]
        XCTAssertTrue(look.waitForExistence(timeout: 15))
        let initialLook = look.label
        let favorite = app.buttons["camera-favorite-look"]
        assertReachable(favorite, in: app)
        XCTAssertEqual(favorite.value as? String, "Not favorite")
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, "Favorite")
        XCTAssertEqual(look.label, initialLook)
        look.tap()
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.buttons["recipe-g7x-compact"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-classic-chrome"].exists)
        snapshot("signal-frame-quick-favorites")
        app.buttons["recipe-drawer-close"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(favorite.waitForExistence(timeout: 15))
        XCTAssertEqual(favorite.value as? String, "Favorite")
        favorite.tap()
        look.tap()
        tapWhenStable(app.buttons["camera-looks-favorites"], in: app)
        XCTAssertTrue(app.staticTexts["camera-favorites-empty"].waitForExistence(timeout: 5))
        assertReachable(app.buttons["camera-looks-all"], in: app)
        tapWhenStable(app.buttons["camera-looks-all"], in: app)
        XCTAssertTrue(app.buttons["recipe-g7x-compact"].waitForExistence(timeout: 5))
        app.buttons["recipe-drawer-close"].tap()
        XCTAssertEqual(look.label, initialLook)
    }

    func testCameraPrimaryControlsRemainReachableAtLargestAccessibilityText() {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 15))
        for id in ["recipe-menu", "camera-favorite-look", "import-photo", "camera-chrome-toggle"] {
            assertReachable(app.buttons[id], in: app)
        }
        snapshot("signal-frame-camera-largest-text")
        app.buttons["recipe-menu"].tap()
        for id in ["recipe-drawer-close", "camera-looks-favorites", "camera-looks-all"] {
            assertReachable(app.buttons[id], in: app)
        }
        snapshot("signal-frame-drawer-largest-text")
        app.buttons["recipe-drawer-close"].tap()

        // Secondary destinations must honor the full text size, rather than
        // inheriting the camera shell's intentionally bounded chrome scale.
        app.buttons["settings-tab"].tap()
        assertReachable(app.buttons["settings-back-to-camera"], in: app)
        let clearCache = app.buttons["clear-local-cache"]
        revealInPage(clearCache, in: app)
        XCTAssertGreaterThan(clearCache.frame.width, 180)
        XCTAssertFalse(app.staticTexts["250 MB"].exists, "Do not present the cache budget as measured usage")
        snapshot("signal-frame-settings-storage-largest-text")
        app.buttons["settings-back-to-camera"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments += ["-ui-testing-onboarding"]
        app.launch()
        assertReachable(app.buttons["onboarding-continue"], in: app)
        let recipe = app.buttons["onboarding-recipe-classic-chrome"]
        revealInPage(recipe, in: app)
        assertReachable(recipe, in: app)
        XCTAssertGreaterThan(recipe.frame.width, 180, "Accessibility choices should be readable rows, not narrow tiles")
        recipe.tap()
        XCTAssertEqual(recipe.value as? String, "Selected")
        snapshot("signal-frame-onboarding-choices-largest-text")
        let compare = app.buttons["onboarding-compare"]
        revealInPage(compare, in: app)
        assertReachable(compare, in: app)
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Original")
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Look")
        snapshot("signal-frame-onboarding-compare-largest-text")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["recipe-menu"].label.contains("Classic Chrome"))
    }

    private func revealInPage(_ control: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<24 {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 8)
            if control.exists && viewport.contains(control.frame) { return }
            let downward = control.exists && control.frame.midY < viewport.midY
            let overflow = control.exists
                ? (downward ? viewport.minY - control.frame.minY : control.frame.maxY - viewport.maxY)
                : viewport.height * 0.3
            let distance = min(max(overflow + 24, 60), viewport.height * 0.35)
            let start = CGPoint(x: viewport.minX + 8, y: downward ? viewport.minY + 30 : viewport.maxY - 30)
            let end = CGPoint(x: start.x, y: start.y + (downward ? distance : -distance))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
        }
        snapshot("signal-frame-unreachable-page-control")
        XCTFail("Could not fully reveal \(control.identifier)")
    }

    private func makeApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.SignalFrame.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-viewfinder-chrome", "-selectedRecipeID", "g7x-compact"]
        return app
    }

    private func tapWhenStable(_ control: XCUIElement, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        var previousFrame: CGRect?
        var stableSamples = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard control.exists, control.isHittable else {
                previousFrame = nil
                stableSamples = 0
                return false
            }
            let frame = control.frame
            stableSamples = frame == previousFrame ? stableSamples + 1 : 0
            previousFrame = frame
            return stableSamples >= 2 && app.frame.contains(frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed,
                       "Drawer control must settle before tapping", file: file, line: line)
        control.tap()
    }

    private func assertReachable(_ control: XCUIElement, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44, file: file, line: line)
        XCTAssertTrue(app.frame.contains(control.frame), "Control must not be partially clipped", file: file, line: line)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
