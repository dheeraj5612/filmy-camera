import XCTest

/// Real Photos UI acceptance on the disposable cafe-seeded simulator only.
/// Every destructive action targets a frame imported and saved by this case;
/// the public source remains in Photos. Never run against a physical library.
@MainActor
final class NormalRollManagementTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!
    private let recipeName = "G7 X Compact"
    private var sourceLibraryCount: Int?

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_SEEDED_PHOTOS_E2E"] == "1",
                          "Use only the disposable simulator seeded with cafe-original.png")
        #else
        throw XCTSkip("Destructive fixture acceptance is restricted to a disposable simulator")
        #endif
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            launchedApp?.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testNormalDeleteCancelConfirmAndClearCachePreservePhotosUntilDeletion() throws {
        launchNormalApp()
        let countBefore = try openAuthorizedRoll()
        returnToCamera()
        try saveCafeFixture(newerSavedFrameCount: countBefore)
        XCTAssertEqual(try openAuthorizedRoll(), countBefore + 1)
        try openNewestSavedFrame(expectedCount: countBefore + 1)
        let metadataBefore = app.descendants(matching: .any)["gallery-frame-metadata"].label

        app.buttons["Delete frame"].tap()
        XCTAssertTrue(app.buttons["Delete Frame"].waitForExistence(timeout: 5))
        screenshot("owned-frame-delete-confirmation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(waitUntil { !self.app.buttons["Delete Frame"].exists })
        XCTAssertEqual(app.descendants(matching: .any)["gallery-frame-metadata"].label, metadataBefore)
        XCTAssertTrue(app.images["Photo"].exists, "Cancel must retain the loaded frame")
        app.buttons["Close frame"].tap()
        XCTAssertEqual(try loadedRollCount(), countBefore + 1)
        returnToCamera()

        try clearCacheThroughSettings()
        XCTAssertEqual(try openAuthorizedRoll(), countBefore + 1,
                       "Clearing cache must retain the actual Photos asset and ownership")
        XCTAssertFalse(app.staticTexts["Local cache"].exists)
        try openNewestSavedFrame(expectedCount: countBefore + 1)
        screenshot("cleared-cache-frame-loaded-from-photos")
        try confirmDeletionOfOpenFixture(expectedCountAfter: countBefore)

        app.terminate()
        launchNormalApp()
        XCTAssertEqual(try openAuthorizedRoll(), countBefore,
                       "Confirmed deletion must remain deleted after service reconstruction")
        screenshot("deleted-fixture-stays-deleted-after-relaunch")
        try verifyPhotosLibraryCountAfterDeletion()
    }

    func testNormalDeniedPhotosUsesCacheThenRecoversSavedFrameAfterAccessReturns() throws {
        launchNormalApp()
        let countBefore = try openAuthorizedRoll()
        returnToCamera()
        try saveCafeFixture(newerSavedFrameCount: countBefore)
        XCTAssertEqual(try openAuthorizedRoll(), countBefore + 1)

        // Public XCTest setup API resets only this disposable app's permission.
        // iOS may terminate the app, so this does not claim an in-place live
        // revocation test. Actual deny/grant decisions use the system prompt.
        app.terminate()
        app.resetAuthorizationStatus(for: .photos)
        launchNormalApp()
        openSettings()
        let request = app.buttons["photos-permission-action"]
        reveal(request)
        XCTAssertTrue(request.exists && request.isHittable)
        request.tap()
        try respondToPhotoPrompt(allow: false)
        let deniedSettings = app.buttons["photos-permission-settings"]
        XCTAssertTrue(deniedSettings.waitForExistence(timeout: 10))
        screenshot("photos-denied-settings-action")
        app.buttons["settings-back-to-camera"].tap()

        openRoll()
        XCTAssertTrue(app.staticTexts["Local cache"].waitForExistence(timeout: 15))
        let saved = savedFrameButton()
        XCTAssertTrue(saved.waitForExistence(timeout: 15) && saved.isHittable)
        saved.tap()
        XCTAssertTrue(app.images["Photo"].waitForExistence(timeout: 20),
                      "Read denial must still allow the owned cached frame to load")
        XCTAssertTrue(app.descendants(matching: .any)["gallery-frame-metadata"].label.contains(recipeName))
        XCTAssertFalse(app.buttons["Delete frame"].exists,
                       "A cache-only frame must not offer a Photos deletion operation")
        XCTAssertTrue(app.buttons["Share frame"].isEnabled)
        screenshot("photos-denied-cached-frame-without-delete")
        app.buttons["frame-back-to-camera"].tap()

        try clearCacheThroughSettings()
        openRoll()
        XCTAssertTrue(app.staticTexts["Photo access is off"].waitForExistence(timeout: 15))
        XCTAssertFalse(savedFrameButton().exists,
                       "A denied library with the local cache cleared must not retain a stale tile")
        let settingsAction = app.buttons["Open Settings"]
        XCTAssertTrue(settingsAction.exists && settingsAction.isHittable)
        settingsAction.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10),
                      "The denied-state recovery action must actually open iOS Settings")
        screenshot("photos-denied-recovery-opens-system-settings")

        // Reset makes the genuine grant prompt available again without
        // depending on Settings' OS-specific permission-cell hierarchy.
        app.terminate()
        app.resetAuthorizationStatus(for: .photos)
        launchNormalApp()
        XCTAssertEqual(try openAuthorizedRoll(), countBefore + 1,
                       "Restored read access must recover the saved Photos frame after cache removal")
        try openNewestSavedFrame(expectedCount: countBefore + 1)
        XCTAssertTrue(app.buttons["Delete frame"].exists,
                      "Read access must restore operations on this known owned Photos frame")
        screenshot("photos-restored-frame-loaded-without-local-cache")
        try confirmDeletionOfOpenFixture(expectedCountAfter: countBefore)
        try verifyPhotosLibraryCountAfterDeletion()
    }

    private func launchNormalApp() {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // No -ui-testing: exercise actual PhotosPicker, PhotoKit and cache.
        app.launch()
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        XCTAssertTrue(app.buttons["roll-tab"].waitForExistence(timeout: 15))
    }

    private func openRoll() {
        let roll = app.buttons["roll-tab"]
        XCTAssertTrue(roll.waitForExistence(timeout: 10) && roll.isHittable)
        roll.tap()
        XCTAssertTrue(app.staticTexts["Roll"].waitForExistence(timeout: 10))
    }

    private func openAuthorizedRoll() throws -> Int {
        openRoll()
        let request = app.buttons["Allow Photos access"]
        if request.waitForExistence(timeout: 2) {
            request.tap()
            try respondToPhotoPrompt(allow: true)
        }
        XCTAssertFalse(app.staticTexts["Photo access is off"].exists)
        return try loadedRollCount()
    }

    private func returnToCamera() {
        app.buttons["roll-back-to-camera"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 10))
    }

    private func saveCafeFixture(newerSavedFrameCount: Int) throws {
        let current = app.buttons["recipe-menu"]
        if !current.label.contains(recipeName) {
            current.tap()
            let tile = app.buttons["recipe-g7x-compact"]
            XCTAssertTrue(tile.waitForExistence(timeout: 10) && tile.isHittable)
            tile.tap()
            XCTAssertTrue(waitUntil { current.label.contains(self.recipeName) })
            app.buttons["recipe-drawer-close"].tap()
        }
        app.buttons["import-photo"].tap()
        let photos = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info'"))
        XCTAssertTrue(waitUntil(timeout: 30) {
            if photos.count > newerSavedFrameCount { return true }
            let notice = self.app.buttons["Dismiss"]
            if notice.exists && notice.isHittable { notice.tap() }
            return false
        }, "The seeded source must be visible after the newer app-created fixtures")
        sourceLibraryCount = photos.count
        // The harness seeds cafe newest; earlier app saves sort ahead of it.
        let source = photos.element(boundBy: newerSavedFrameCount)
        XCTAssertTrue(app.frame.contains(source.frame), "Never tap an offscreen or unknown Photos tile")
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["IMPORTED PHOTO"].waitForExistence(timeout: 40))
        let save = app.buttons["Save filtered photo"]
        XCTAssertTrue(waitUntil(timeout: 30) { save.exists && save.isEnabled })
        XCTAssertTrue(app.descendants(matching: .any)["review-image"].label.contains(recipeName))
        save.tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved with '")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 45) {
            if saved.exists { return true }
            self.tapPhotoPromptIfPresent(allow: true)
            return false
        }, "The new owned fixture must complete the real Photos save")
        XCTAssertTrue(app.buttons["roll-tab"].waitForExistence(timeout: 10))
    }

    private func savedFrameButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", "Photo in your gallery, \(recipeName)")).firstMatch
    }

    private func openNewestSavedFrame(expectedCount: Int) throws {
        let saved = savedFrameButton()
        XCTAssertTrue(saved.waitForExistence(timeout: 20) && saved.isHittable)
        saved.tap()
        XCTAssertTrue(app.images["Photo"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["gallery-frame-metadata"].label.contains(recipeName))
        if expectedCount > 1 {
            XCTAssertEqual(app.descendants(matching: .any)["gallery-frame-position"].value as? String,
                           "1 of \(expectedCount)", "Only delete the newest fixture just created by this case")
        }
        XCTAssertTrue(app.buttons["Delete frame"].exists && app.buttons["Delete frame"].isEnabled)
    }

    private func confirmDeletionOfOpenFixture(expectedCountAfter: Int) throws {
        app.buttons["Delete frame"].tap()
        let confirm = app.buttons["Delete Frame"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(waitUntil(timeout: 30) {
            // PhotoKit may additionally ask permission to remove this one photo.
            for application in [self.app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
                let alert = application.alerts.firstMatch
                guard alert.exists else { continue }
                for title in ["Delete", "Delete Photo"] where alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    return false
                }
            }
            return !self.app.buttons["Close frame"].exists && self.rollCount() == expectedCountAfter
        }, "Confirmed deletion must remove the selected fixture and publish the reduced Roll count")
        XCTAssertFalse(app.alerts["Couldn’t update frame"].exists)
    }

    private func verifyPhotosLibraryCountAfterDeletion() throws {
        let expected = try XCTUnwrap(sourceLibraryCount)
        XCTAssertGreaterThan(expected, 0, "The public source must remain in Photos")
        returnToCamera()
        app.buttons["import-photo"].tap()
        let photos = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info'"))
        XCTAssertTrue(waitUntil(timeout: 30) { photos.count == expected },
                      "The system PhotosPicker must return to its pre-save item count; hiding a Roll tile is insufficient")
        let attachment = XCTAttachment(string:
            "PhotosPicker count before fixture save: \(expected); count after confirmed deletion: \(photos.count)")
        attachment.name = "photos-library-count-after-owned-fixture-deletion"
        attachment.lifetime = .keepAlways
        add(attachment)
        screenshot("system-photos-count-restored-after-deletion")
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5) && cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(app.buttons["import-photo"].waitForExistence(timeout: 10))
    }

    private func openSettings() {
        app.buttons["settings-tab"].tap()
        XCTAssertTrue(app.buttons["settings-back-to-camera"].waitForExistence(timeout: 10))
    }

    private func clearCacheThroughSettings() throws {
        openSettings()
        let clear = app.buttons["clear-local-cache"]
        reveal(clear)
        XCTAssertEqual(clear.value as? String, "Available", "A just-saved fixture must have a persistent local fallback")
        XCTAssertTrue(clear.isEnabled && clear.isHittable)
        clear.tap()
        XCTAssertTrue(waitUntil { clear.value as? String == "Empty" && !clear.isEnabled },
                      "Clear must remove the cached files and disable the empty action")
        screenshot("clear-local-cache-empty-readback")
        app.buttons["settings-back-to-camera"].tap()
    }

    private func reveal(_ control: XCUIElement) {
        for _ in 0..<8 {
            if control.exists && control.isHittable && app.frame.insetBy(dx: 4, dy: 65).contains(control.frame) { return }
            app.swipeUp()
        }
        XCTFail("Control did not become fully visible: \(control.identifier)")
    }

    private func loadedRollCount() throws -> Int {
        XCTAssertTrue(waitUntil(timeout: 20) { self.rollCount() != nil })
        return try XCTUnwrap(rollCount())
    }

    private func rollCount() -> Int? {
        for label in app.staticTexts.allElementsBoundByIndex.map(\.label) where label.hasSuffix(" frames") {
            if let count = Int(label.dropLast(" frames".count)) { return count }
        }
        if app.staticTexts["Your frames will live here"].exists || app.staticTexts["Your selected roll is empty"].exists {
            return 0
        }
        return nil
    }

    private func respondToPhotoPrompt(allow: Bool) throws {
        XCTAssertTrue(waitUntil(timeout: 15) { self.tapPhotoPromptIfPresent(allow: allow) },
                      "Expected the actual Photos \(allow ? "grant" : "deny") prompt")
    }

    @discardableResult
    private func tapPhotoPromptIfPresent(allow: Bool) -> Bool {
        let titles = allow ? ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK"]
                           : ["Don’t Allow", "Don't Allow", "Don’t Allow Access", "Don't Allow Access"]
        for application in [app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let alert = application.alerts.firstMatch
            guard alert.exists else { continue }
            for title in titles where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
        }
        return false
    }

    private func waitUntil(timeout: TimeInterval = 10, _ predicate: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        return predicate()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
