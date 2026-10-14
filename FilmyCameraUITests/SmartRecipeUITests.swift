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
        XCTAssertEqual(entry.label, "Smart looks")
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.switches["smart-recipes-enabled"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["smart-recipes-empty"].exists
            || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No suggestions yet")).firstMatch.exists)
        XCTAssertFalse(app.buttons["smart-recipes-quick-apply"].exists)
        let back = app.buttons["smart-recipes-empty-close"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        for _ in 0..<4 where !back.isHittable { app.swipeUp() }
        XCTAssertTrue(back.isHittable)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "smart-looks-empty-sheet"
        shot.lifetime = .keepAlways
        add(shot)
        back.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.switches["smart-recipes-enabled"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
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
        app.buttons["Done"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }
}
