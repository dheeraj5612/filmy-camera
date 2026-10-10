import XCTest

final class G7CameraUITests: XCTestCase {
    func testG7LaunchUsesDedicatedControlDeck() {
        let app = XCUIApplication(bundleIdentifier: "com.dheeraj.g7camera")
        app.launchArguments += ["-ui-testing"]
        app.launch()

        let deck = app.otherElements["g7x-camera-control-deck"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Q/SET"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["DISP"].exists)
        XCTAssertFalse(app.buttons["Next look"].exists)

        app.buttons["Q/SET"].tap()
        let dateStamp = app.buttons["DATE STAMP"]
        XCTAssertTrue(dateStamp.waitForExistence(timeout: 2))
        let initialValue = dateStamp.value as? String
        XCTAssertTrue(initialValue == "ON" || initialValue == "OFF")
        dateStamp.tap()
        XCTAssertEqual(dateStamp.value as? String, initialValue == "ON" ? "OFF" : "ON")
        dateStamp.tap()
        XCTAssertEqual(dateStamp.value as? String, initialValue)
    }
}
