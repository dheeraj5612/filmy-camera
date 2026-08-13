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
        XCTAssertTrue(app.staticTexts["Natural Standard"].waitForExistence(timeout: 5))

        let classicChrome = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Muted Color'")
        ).firstMatch
        assertMinimumHitTarget(classicChrome, named: "Muted Color recipe")
        classicChrome.tap()

        let details = app.buttons["Tune Muted Color"]
        assertMinimumHitTarget(details, named: "Tune recipe")
        details.tap()

        XCTAssertTrue(app.staticTexts["Recipe controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Muted Color is selected"].waitForExistence(timeout: 5))

        let reset = app.buttons["Reset recipe controls"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertTrue(reset.isHittable, "Reset recipe controls should be reachable")

        let exposure = app.descendants(matching: .any)["exposure-control"]
        if exposure.waitForExistence(timeout: 1) {
            assertMinimumHitTarget(exposure, named: "Exposure control")
            XCTAssertFalse(app.buttons["Decrease exposure compensation"].exists)
            XCTAssertFalse(app.buttons["Increase exposure compensation"].exists)
        }
        attachScreenshot(named: "recipe-details")
    }

    func testGalleryAndSettingsNavigation() throws {
        let gallery = app.buttons["Roll"]
        assertMinimumHitTarget(gallery, named: "Roll")
        gallery.tap()

        XCTAssertTrue(app.staticTexts["Photo access is off"].waitForExistence(timeout: 5))
        attachScreenshot(named: "gallery-empty-state")

        let settings = app.buttons["Settings"]
        assertMinimumHitTarget(settings, named: "Settings tab")
        settings.tap()

        let settingsHeading = app.staticTexts["Settings"]
        XCTAssertTrue(settingsHeading.waitForExistence(timeout: 5))

        let privacyPolicy = app.descendants(matching: .any)["privacy-policy-link"]
        scrollToHittable(privacyPolicy, in: app)
        assertMinimumHitTarget(privacyPolicy, named: "Privacy Policy")

        let support = app.descendants(matching: .any)["support-link"]
        scrollToHittable(support, in: app)
        assertMinimumHitTarget(support, named: "Contact Support")

        let photosPermission = app.buttons["photos-permission-settings"]
        assertMinimumHitTarget(photosPermission, named: "Photos permission settings")

        let clearCache = app.descendants(matching: .any)["clear-local-cache"]
        XCTAssertTrue(clearCache.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(clearCache.frame.width, 44, "Clear local cache needs a 44pt width")
        XCTAssertGreaterThanOrEqual(clearCache.frame.height, 44, "Clear local cache needs a 44pt height")
        attachScreenshot(named: "settings")
    }

    private func assertMinimumHitTarget(_ element: XCUIElement, named: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), named + " should exist")
        XCTAssertTrue(element.isHittable, named + " should be hittable")
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, named + " needs a 44pt width")
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, named + " needs a 44pt height")
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
