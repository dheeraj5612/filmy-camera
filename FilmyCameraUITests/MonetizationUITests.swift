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
        app.buttons["settings-tab"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["membership-account-settings"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
    }

    func testMonetizationOffShowsNoMonetizationSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-monetization-free", "-ui-testing-monetization-off"]
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.Monetization.\(UUID().uuidString)"
        app.launch()
        let settings = app.buttons["settings-tab"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["membership-photo-allowance"].exists)
        XCTAssertFalse(app.buttons["membership-upgrade"].exists)
        XCTAssertFalse(app.buttons["membership-close"].exists)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["free-tier-advertisement"].firstMatch.exists)
        XCTAssertFalse(app.buttons["membership-close"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["membership-account-settings"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Account & Filmy Pro"].exists)
        XCTAssertFalse(app.buttons["Explore Filmy Pro"].exists)
        app.terminate()
    }
}
