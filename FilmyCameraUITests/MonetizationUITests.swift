import XCTest

@MainActor
final class MonetizationUITests: XCTestCase {
    func testFreeCameraShowsAllowanceAndDismissiblePaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-monetization-free"]
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Monetization.\(UUID().uuidString)"
        app.launch()
        let allowance = app.staticTexts["membership-photo-allowance"]
        XCTAssertTrue(allowance.waitForExistence(timeout: 15))
        XCTAssertEqual(allowance.label, "10 of 10 photos left today")
        XCTAssertFalse(app.otherElements["free-tier-advertisement"].exists)
        app.buttons["membership-upgrade"].tap()
        let close = app.buttons["membership-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["membership-restore"].exists)
        close.tap()
        XCTAssertTrue(app.buttons["membership-upgrade"].waitForExistence(timeout: 5))
        app.terminate()
    }
}
