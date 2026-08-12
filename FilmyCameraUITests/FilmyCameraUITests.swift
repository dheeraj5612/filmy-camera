import XCTest

@MainActor
final class FilmyCameraUITests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let launchedApp = MainActor.assumeIsolated {
            let launchedApp = XCUIApplication()
            launchedApp.launchArguments = ["-ui-testing"]
            launchedApp.launch()
            return launchedApp
        }
        app = launchedApp
    }

    func testCameraShellAndRecipeDetails() throws {
        XCTAssertTrue(app.staticTexts["FILMY CAMERA"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Provia Standard"].waitForExistence(timeout: 5))

        let classicChrome = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Classic Chrome'")
        ).firstMatch
        XCTAssertTrue(classicChrome.waitForExistence(timeout: 5))
        classicChrome.tap()

        let details = app.buttons["Tune Classic Chrome"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        XCTAssertTrue(app.staticTexts["Recipe controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Classic Chrome is selected"].waitForExistence(timeout: 5))
        attachScreenshot(named: "recipe-details")
    }

    func testGalleryAndSettingsNavigation() throws {
        let gallery = app.buttons["Roll"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        gallery.tap()

        XCTAssertTrue(app.staticTexts["Photo access is off"].waitForExistence(timeout: 5))
        attachScreenshot(named: "gallery-empty-state")

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy-policy-link"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].waitForExistence(timeout: 5))
        attachScreenshot(named: "settings")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
