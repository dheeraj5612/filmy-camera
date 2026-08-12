import XCTest

@MainActor
final class FilmyCameraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testCameraShellAndRecipeDetails() throws {
        XCTAssertTrue(app.staticTexts["FILMY CAMERA"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Provia Standard"].waitForExistence(timeout: 5))

        let classicChrome = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Classic Chrome'")
        ).firstMatch
        XCTAssertTrue(classicChrome.waitForExistence(timeout: 5))
        classicChrome.tap()

        let details = app.buttons["View details for Classic Chrome"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        XCTAssertTrue(app.staticTexts["Recipe controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Classic Chrome is selected"].waitForExistence(timeout: 5))
        attachScreenshot(named: "recipe-details")
    }

    func testGalleryAndSettingsNavigation() throws {
        let gallery = app.buttons["Gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        gallery.tap()
        dismissPhotosPermissionIfNeeded()

        XCTAssertTrue(app.staticTexts["Gallery"].waitForExistence(timeout: 5))
        attachScreenshot(named: "gallery-empty-state")

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        attachScreenshot(named: "settings")
    }

    private func dismissPhotosPermissionIfNeeded() {
        let monitor = addUIInterruptionMonitor(withDescription: "Photos permission") { alert in
            self.tapPhotosPermissionButton(in: alert)
        }

        let springBoard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemAlert = springBoard.alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 5) {
            _ = tapPhotosPermissionButton(in: systemAlert)
        }
        app.tap()
        if systemAlert.exists {
            _ = tapPhotosPermissionButton(in: systemAlert)
        }
        XCTAssertFalse(
            springBoard.alerts.firstMatch.exists,
            "Photos permission prompt remained on screen"
        )
        removeUIInterruptionMonitor(monitor)
    }

    private func tapPhotosPermissionButton(in alert: XCUIElement) -> Bool {
        for label in ["Allow Full Access", "Allow Limited Access", "Allow"] {
            if alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
        }
        if alert.buttons["Don’t Allow"].exists {
            alert.buttons["Don’t Allow"].tap()
            return true
        }
        return false
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
