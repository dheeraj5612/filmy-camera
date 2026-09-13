import XCTest

/// Deliberately a simulator UI suite: the sample is labeled as a sample and
/// capture stays disabled. Hardware preview/capture requires the device lane.
@MainActor
final class FrameIndexUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Frame Index sample-preview evidence runs on a simulator, not a live camera")
        #endif
        XCUIDevice.shared.orientation = .portrait
    }

    func testOriginalSampleComparisonKeepsCaptureLookAndDisabledShutter() {
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        let current = app.buttons["recipe-menu"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        let selected = current.label
        let compare = app.buttons["camera-compare-original"]
        assertControl(compare, in: app)
        XCTAssertEqual(compare.value as? String, "Look")
        XCTAssertTrue(app.staticTexts["Preview mode"].exists)
        XCTAssertFalse(app.buttons["camera-shutter"].isEnabled, "A sample must not simulate successful capture")
        snapshot("frame-index-camera-look")
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Original")
        XCTAssertEqual(current.label, selected)
        XCTAssertTrue(app.descendants(matching: .any)["camera-original-disclosure"].exists)
        snapshot("frame-index-camera-original")
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Look")
        XCTAssertEqual(current.label, selected)
    }

    func testTuneIsDirectAndOpeningLooksEndsComparison() {
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        let tune = app.buttons["camera-tune-look"]
        assertControl(tune, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["recipe-drawer"].exists)
        tune.tap()
        XCTAssertTrue(app.staticTexts["Recipe controls"].waitForExistence(timeout: 10))
        snapshot("frame-index-direct-tune")
        app.buttons["Done editing Muted Color"].tap()
        let compare = app.buttons["camera-compare-original"]
        XCTAssertTrue(compare.waitForExistence(timeout: 10))
        compare.tap()
        XCTAssertEqual(compare.value as? String, "Original")
        app.buttons["recipe-menu"].tap()
        XCTAssertTrue(app.buttons["recipe-drawer-close"].waitForExistence(timeout: 5))
        XCTAssertEqual(compare.value as? String, "Look", "Opening a look control must return to its actual treatment")
        snapshot("frame-index-look-drawer")
        app.buttons["recipe-drawer-close"].tap()
    }

    func testLargestDynamicTypeKeepsCoreControlsInsideSafeShell() {
        let app = makeApp(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.launch()
        defer { app.terminate() }
        for identifier in ["recipe-menu", "camera-tune-look", "camera-compare-original", "roll-tab", "import-photo", "settings-tab"] {
            assertControl(app.buttons[identifier], in: app)
        }
        XCTAssertFalse(app.buttons["roll-tab"].frame.intersects(app.buttons["recipe-menu"].frame))
        snapshot("frame-index-camera-ax5")
        app.buttons["recipe-menu"].tap()
        assertControl(app.buttons["recipe-drawer-close"], in: app)
        snapshot("frame-index-drawer-ax5")
        app.buttons["recipe-drawer-close"].tap()
    }

    func testSystemLightAppearanceKeepsPhotographicSurroundNeutral() {
        let app = makeApp(extraArguments: ["-AppleInterfaceStyle", "Light"])
        app.launch()
        defer { app.terminate() }
        assertControl(app.buttons["recipe-menu"], in: app)
        assertControl(app.buttons["camera-compare-original"], in: app)
        // This product deliberately uses a dark photographic workspace in
        // either system appearance. This is not a claimed new light theme.
        snapshot("frame-index-system-light-neutral-workspace")
    }

    func testOnePageOnboardingPrivacyAndLargestType() {
        let app = makeApp(extraArguments: ["-ui-testing-onboarding", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.launch()
        defer { app.terminate() }
        assertControl(app.buttons["onboarding-continue"], in: app)
        assertControl(app.buttons["onboarding-privacy"], in: app)
        snapshot("frame-index-onboarding-ax5")
        app.buttons["onboarding-privacy"].tap()
        let close = app.buttons["onboarding-privacy-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        snapshot("frame-index-first-use-privacy")
        close.tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding-screen"].exists)
    }

    private func makeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.FrameIndex.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-viewfinder-chrome", "-selectedRecipeID", "classic-chrome"] + extraArguments
        return app
    }

    private func assertControl(_ control: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.waitForExistence(timeout: 15), control.identifier, file: file, line: line)
        XCTAssertTrue(control.isHittable, control.identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.width, 44, control.identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44, control.identifier, file: file, line: line)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(control.frame), "\(control.identifier) must stay inside the window", file: file, line: line)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
