import XCTest

@MainActor
final class RecipeLibraryUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchApp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "RecipeLibraryUITests.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-ui-testing-viewfinder-chrome", "-selectedRecipeID", "classic-chrome"]
        app.launch()
    }

    func testEnableAllHideAllUndoAndRelaunchPreserveTheCurrentLook() throws {
        launchApp()
        openManager()
        let count = app.staticTexts["recipe-manager-active-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.hasPrefix("128 of "), count.label)
        attach("recipe-packs-default")
        app.buttons["recipe-manager-actions"].tap()
        app.buttons["recipe-enable-all"].tap()
        let all = try activeCounts()
        XCTAssertGreaterThanOrEqual(all.total, 648)
        XCTAssertEqual(all.enabled, all.total)
        app.buttons["recipe-manager-actions"].tap()
        app.buttons["recipe-hide-all"].tap()
        XCTAssertEqual(try activeCounts().enabled, 0)
        app.buttons["recipe-manager-undo"].tap()
        XCTAssertEqual(try activeCounts().enabled, all.total)
        XCTAssertFalse(app.buttons["recipe-manager-undo"].exists)
        app.buttons["recipe-manager-actions"].tap()
        app.buttons["recipe-hide-all"].tap()
        app.buttons["recipe-manager-done"].tap()
        XCTAssertTrue(app.staticTexts["camera-looks-empty"].waitForExistence(timeout: 5))
        attach("recipe-popup-empty-with-packs-recovery")
        let before = app.buttons["recipe-menu"].label
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["recipe-menu"].label, before)
        openManager()
        XCTAssertEqual(try activeCounts().enabled, 0)
    }

    func testSearchIndividualVisibilityAndPublishedSourceDetails() throws {
        launchApp()
        openManager()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Kodachrome")
        let toggle = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH 'manage-toggle-'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        if app.keyboards.firstMatch.exists {
            let done = app.keyboards.buttons["search"].exists ? app.keyboards.buttons["search"] : app.keyboards.buttons["Search"]
            if done.exists { done.tap() }
        }
        let before = try activeCounts().enabled
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(try activeCounts().enabled, before + 1)
        attach("recipe-manager-search-individual-enabled")
        let details = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'manage-source-'")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        XCTAssertTrue(app.buttons["recipe-source-done"].waitForExistence(timeout: 5))
        attach("recipe-published-settings-and-comparison")
        XCTAssertTrue(app.staticTexts["Original recipe"].exists || app.staticTexts["ORIGINAL RECIPE"].exists)
        app.buttons["recipe-source-done"].tap()
        XCTAssertTrue(app.buttons["recipe-manager-done"].waitForExistence(timeout: 5))
    }

    private func openManager() {
        let menu = app.buttons["recipe-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        if !app.buttons["camera-recipe-packs"].exists { menu.tap() }
        let packs = app.buttons["camera-recipe-packs"]
        XCTAssertTrue(packs.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(packs.frame.height, 44)
        packs.tap()
        XCTAssertTrue(app.buttons["recipe-manager-done"].waitForExistence(timeout: 5))
    }

    private func activeCounts() throws -> (enabled: Int, total: Int) {
        let label = app.staticTexts["recipe-manager-active-count"].label
        let values = label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(values.count, 2, label)
        return (try XCTUnwrap(values.first), try XCTUnwrap(values.last))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
