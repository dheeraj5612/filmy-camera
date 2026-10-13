import XCTest

@MainActor
final class SmartRecipeUITests: XCTestCase {
    private func launch(suite: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-viewfinder-chrome"]
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = suite
        app.launch()
        return app
    }

    func testSmartLooksIsDiscoverableAndUnavailableSceneHasNoApplyAction() {
        let app = launch(suite: "FilmyCameraUITests.Smart.\(UUID().uuidString)")
        let entry = app.buttons["smart-recipes-open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.switches["smart-recipes-enabled"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["smart-recipes-empty"].exists
            || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Return to the viewfinder")).firstMatch.exists)
        XCTAssertFalse(app.buttons["smart-recipes-quick-apply"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    func testDisablingSuggestionsPersistsAcrossRelaunch() {
        let suite = "FilmyCameraUITests.Smart.\(UUID().uuidString)"
        let app = launch(suite: suite)
        let entry = app.buttons["smart-recipes-open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let toggle = app.switches["smart-recipes-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.terminate()
        app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }
}
