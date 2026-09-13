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
        app.buttons["camera-looks-favorites"].tap()
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
        app.buttons["camera-looks-favorites"].tap()
        XCTAssertTrue(app.staticTexts["camera-favorites-empty"].waitForExistence(timeout: 5))
        assertReachable(app.buttons["camera-looks-all"], in: app)
        app.buttons["camera-looks-all"].tap()
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
    }

    private func makeApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.SignalFrame.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-viewfinder-chrome", "-selectedRecipeID", "g7x-compact"]
        return app
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
