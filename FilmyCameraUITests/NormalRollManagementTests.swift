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

        // The header folds Select and the layout toggle into one row, so the
        // first thumbnail row starts high and entering select mode moves nothing.
        let select = app.buttons["roll-select-toggle"]
        let layout = app.buttons["roll-grid-layout"]
        let originals = app.descendants(matching: .any)["roll-filmy-originals"]
        let first = savedFrameButton()
        XCTAssertTrue(select.exists && select.isHittable && layout.exists && originals.exists)
        XCTAssertGreaterThanOrEqual(select.frame.height, 44)
        // The same-row check only holds for the short "Photos" source label; a longer
        // label may legitimately stack Select under the layout toggle. Assumes lookFilter == nil.
        if app.staticTexts["Photos"].exists {
            XCTAssertLessThan(abs(select.frame.midY - layout.frame.midY), 8, "Select and the layout toggle must share one header row")
        }
        XCTAssertFalse(app.staticTexts["LIBRARY"].exists)
        XCTAssertLessThan(first.frame.minY, 440, "The first thumbnail row must start within 440 pt of the top")
        XCTAssertLessThanOrEqual(first.frame.maxY, app.frame.maxY, "The first thumbnail row must be fully on screen")
        screenshot("roll-header-one-row")
        let selectFrame = select.frame
        let firstTop = first.frame.minY
        select.tap()
        XCTAssertTrue(app.buttons["roll-select-all"].waitForExistence(timeout: 5))
        XCTAssertEqual(select.label, "Done")
        XCTAssertTrue(waitUntil { select.frame.contains(CGPoint(x: selectFrame.midX, y: selectFrame.midY)) }, "Done must sit under the finger that tapped Select")
        XCTAssertTrue(waitUntil { abs(first.frame.minY - firstTop) < 8 }, "Entering select mode must not move the grid")
        XCTAssertEqual(app.staticTexts["roll-count-summary"].label, "0 selected")
        screenshot("roll-select-mode")
        select.tap()
        XCTAssertTrue(waitUntil { !self.app.buttons["roll-select-all"].exists && originals.exists })

        try openNewestSavedFrame(expectedCount: countBefore + 1)

        // One tap hides the viewer controls, a second brings them back, and a
        // double tap zooms in without toggling them. Each check waits because
        // the single tap waits out the double-tap window.
        let photo = app.images["Photo"]
        let close = app.buttons["Close frame"]
        let photoFrame = photo.frame
        photo.tap()
        XCTAssertTrue(waitUntil { !close.exists }, "One tap must hide the viewer controls")
        XCTAssertTrue(waitUntil { !app.descendants(matching: .any)["gallery-frame-metadata"].exists }, "Hidden controls must hide the frame metadata")
        XCTAssertEqual(photo.frame, photoFrame, "Hiding the controls must not move or resize the photo")
        screenshot("frame-chrome-hidden")
        photo.tap()
        XCTAssertTrue(waitUntil { close.exists && close.isHittable }, "A second tap must bring the controls back")
        XCTAssertTrue(waitUntil { app.descendants(matching: .any)["gallery-frame-metadata"].exists }, "A second tap must bring the frame metadata back")
        photo.doubleTap()
        XCTAssertTrue(waitUntil { (photo.value as? String) == "Zoomed 200 percent" }, "Double tap from fit must zoom in")
        XCTAssertTrue(close.exists, "Double tap must not toggle the controls")
        screenshot("frame-double-tap-zoom")
        photo.doubleTap()
        XCTAssertTrue(waitUntil { (photo.value as? String) == "Fit to screen" })

        let metadataBefore = app.descendants(matching: .any)["gallery-frame-metadata"].label
        XCTAssertFalse(metadataBefore.contains("Local copy"), "A Photos frame must not carry the cached-frame note")

        app.buttons["Delete frame"].tap()
        XCTAssertTrue(app.buttons["Delete Frame"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Photos may ask you to confirm once more")).firstMatch.waitForExistence(timeout: 5),
            "The delete prompt must say Photos will ask again"
        )
        screenshot("owned-frame-delete-confirmation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(waitUntil { !self.app.buttons["Delete Frame"].exists })
        XCTAssertEqual(app.descendants(matching: .any)["gallery-frame-metadata"].label, metadataBefore)
        XCTAssertTrue(app.images["Photo"].exists, "Cancel must retain the loaded frame")
        app.buttons["Close frame"].tap()
        XCTAssertEqual(try loadedRollCount(), countBefore + 1)

        // Large text: the detail toolbar must keep every control reachable and apart.
        // The accessibility size forces two rows; the plain extra-large size
        // exercises the one-row fit check and its two-row fallback.
        let categories = [
            "UICTContentSizeCategoryAccessibilityXXXL",
            "UICTContentSizeCategoryExtraExtraExtraLarge"
        ]
        for category in categories {
            app.terminate()
            launchNormalApp(contentSizeCategory: category)
            XCTAssertEqual(try openAuthorizedRoll(), countBefore + 1)
            try openNewestSavedFrame(expectedCount: countBefore + 1, scrollingToTile: true)
            let toolbarButtons = [
                app.buttons["Close frame"],
                app.buttons["frame-back-to-camera"],
                app.buttons["gallery-info-frame"],
                app.buttons["gallery-share-frame"],
                app.buttons["Delete frame"]
            ]
            for button in toolbarButtons {
                XCTAssertTrue(button.exists && button.isHittable,
                              "Large text must keep \(button.identifier.isEmpty ? button.label : button.identifier) hittable")
            }
            for first in 0..<toolbarButtons.count {
                for second in (first + 1)..<toolbarButtons.count {
                    XCTAssertFalse(toolbarButtons[first].frame.intersects(toolbarButtons[second].frame),
                                   "Large text must not overlap detail controls \(first) and \(second)")
                }
            }
            screenshot("frame-detail-large-text-\(category)")
            app.buttons["Close frame"].tap()
            XCTAssertTrue(waitUntil(timeout: 30) { !self.app.buttons["Close frame"].exists })
            screenshot("roll-large-text-\(category)")
        }
        app.terminate()
        launchNormalApp()
        XCTAssertEqual(try openAuthorizedRoll(), countBefore + 1)
        returnToCamera()

        // A second fixture gives the delete a neighbour, so the pager must
        // land on it instead of closing. A lone fixture would only ever
        // exercise the last-frame exit.
        try saveCafeFixture(newerSavedFrameCount: countBefore + 1)
        XCTAssertEqual(try openAuthorizedRoll(), countBefore + 2)
        returnToCamera()

        try clearCacheThroughSettings()
        XCTAssertEqual(try openAuthorizedRoll(), countBefore + 2,
                       "Clearing cache must retain the actual Photos asset and ownership")
        XCTAssertFalse(app.staticTexts["Local cache"].exists)
        try openNewestSavedFrame(expectedCount: countBefore + 2)
        screenshot("cleared-cache-frame-loaded-from-photos")
        try confirmDeletionOfOpenFixture(expectedCountAfter: countBefore + 1)
        try openNewestSavedFrame(expectedCount: countBefore + 1)
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
        XCTAssertTrue(app.descendants(matching: .any)["gallery-frame-metadata"].label.contains("Local copy kept in Filmy"),
                      "A cached frame must say it is Filmy's local copy")
        XCTAssertFalse(app.buttons["Delete frame"].exists,
                       "A cache-only frame must not offer a Photos deletion operation")
        XCTAssertTrue(app.buttons["Share frame"].isEnabled)
        screenshot("photos-denied-cached-frame-without-delete")
        app.buttons["gallery-info-frame"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Storage")).firstMatch.waitForExistence(timeout: 5),
            "Frame info must carry the local-copy note"
        )
        screenshot("photos-denied-cached-frame-info")
        app.buttons["gallery-info-done"].tap()
        XCTAssertTrue(waitUntil { !self.app.buttons["gallery-info-done"].exists })
        app.buttons["frame-back-to-camera"].tap()

        try clearCacheThroughSettings()
        openRoll()
        XCTAssertTrue(app.staticTexts["Photo access is off"].waitForExistence(timeout: 15))
        XCTAssertFalse(savedFrameButton().exists,
                       "A denied library with the local cache cleared must not retain a stale tile")
        let settingsAction = app.buttons["Open Settings"]
        XCTAssertTrue(settingsAction.exists && settingsAction.isHittable)
        let start = app.buttons["roll-start-shooting"]
        let originals = app.descendants(matching: .any)["roll-filmy-originals"]
        XCTAssertTrue(start.exists && originals.exists)
        XCTAssertLessThanOrEqual(settingsAction.frame.maxY, start.frame.minY, "The access fix must sit above the camera route")
        XCTAssertLessThanOrEqual(start.frame.maxY, originals.frame.minY, "Originals must sit below both actions while access is off")
        screenshot("photos-denied-empty-roll-one-primary")
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

    private func launchNormalApp(contentSizeCategory: String? = nil) {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Avoid the exact -ui-testing flag so PhotosPicker, PhotoKit and cache
        // remain real while premium entitlement is deterministic for this lane.
        app.launchArguments = ["-ui-testing-photos-e2e"]
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
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
        let back = app.buttons["roll-back-to-camera"]
        let menu = app.buttons["recipe-menu"]
        for attempt in 1...3 {
            var tapped = false
            if back.waitForExistence(timeout: 5), back.isHittable {
                back.tap()
                tapped = true
            }
            if menu.waitForExistence(timeout: 10) { return }
            // CI run 38345928864: the button dimmed (press recognized) but the
            // Roll stayed up. Keep evidence so a recurring ignored press shows.
            let name = tapped ? "roll-back-to-camera-ignored-attempt-\(attempt)" : "roll-back-to-camera-not-hittable-attempt-\(attempt)"
            screenshot(name)
        }
        XCTFail("Back to camera must reach the viewfinder")
    }

    private func saveCafeFixture(newerSavedFrameCount: Int) throws {
        let current = app.buttons["recipe-menu"]
        if !current.label.contains(recipeName) {
            current.tap()
            let tile = app.buttons["recipe-g7x-compact"]
            XCTAssertTrue(tile.waitForExistence(timeout: 10) && tile.isHittable)
            tile.tap()
            XCTAssertTrue(waitUntil { current.label.contains(self.recipeName) })
            XCTAssertTrue(waitUntil(timeout: 5) {
                !app.descendants(matching: .any)["recipe-drawer"].exists
            }, "Selecting a look must dismiss the picker")
        }
        app.buttons["import-photo"].tap()
        let photos = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info'"))
        XCTAssertTrue(waitUntil(timeout: 30) {
            if photos.count > newerSavedFrameCount { return true }
            let notice = self.app.buttons["Dismiss"]
            if notice.exists && notice.isHittable { notice.tap() }
            return false
        }, "The seeded source must be visible after the newer app-created fixtures")
        // Keep the count from before the first fixture of the case.
        if sourceLibraryCount == nil { sourceLibraryCount = photos.count }
        // The harness seeds cafe newest; earlier app saves sort ahead of it.
        let source = photos.element(boundBy: newerSavedFrameCount)
        XCTAssertTrue(app.frame.contains(source.frame), "Never tap an offscreen or unknown Photos tile")
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["review-heading"].waitForExistence(timeout: 40))
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

    private func openNewestSavedFrame(expectedCount: Int, scrollingToTile: Bool = false) throws {
        let saved = savedFrameButton()
        if scrollingToTile {
            // Large text pushes the first tile below the fold, and the lazy grid
            // creates it only near the screen. Short drags that end with a hold:
            // a flick could carry the tile past the visible band.
            _ = saved.waitForExistence(timeout: 3)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            for _ in 0..<10 where !(saved.exists && saved.isHittable) {
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
        } else {
            XCTAssertTrue(saved.waitForExistence(timeout: 20))
        }
        XCTAssertTrue(saved.exists && saved.isHittable)
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
            let position = self.app.descendants(matching: .any)["gallery-frame-position"]
            if expectedCountAfter > 1, self.app.buttons["Close frame"].exists,
               position.value as? String == "1 of \(expectedCountAfter)" {
                // The pager stays open on the neighbouring frame.
                return true
            }
            if expectedCountAfter == 1, self.app.buttons["Close frame"].exists, !position.exists,
               self.app.images["Photo"].exists,
               self.app.descendants(matching: .any)["gallery-frame-metadata"].label.contains(self.recipeName) {
                // A single survivor has no position label but still shows its photo.
                return true
            }
            // A closed pager is only a valid landing once nothing is left to show.
            guard expectedCountAfter == 0 else { return false }
            return !self.app.buttons["Close frame"].exists && self.rollCount() == expectedCountAfter
        }, "Confirmed deletion must remove the selected fixture and publish the reduced Roll count")
        if app.buttons["Close frame"].exists {
            screenshot("frame-after-delete-landing")
            app.buttons["Close frame"].tap()
            XCTAssertTrue(waitUntil(timeout: 30) {
                !self.app.buttons["Close frame"].exists && self.rollCount() == expectedCountAfter
            }, "Closing the pager must show the reduced Roll count")
        }
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
        let confirm = app.buttons.matching(identifier: "confirm-clear-local-cache").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        screenshot("clear-cache-confirmation-keeps-photos")
        let keepCache = app.buttons["Keep cache"]
        let dismissRegion = app.otherElements["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(waitUntil { keepCache.exists || dismissRegion.exists })
        if keepCache.exists {
            keepCache.tap()
        } else {
            // Native popover presentations omit the cancel button. Dismiss
            // outside the popover, then verify the same cache-preserving result.
            let popover = app.popovers.firstMatch
            XCTAssertTrue(popover.waitForExistence(timeout: 5))
            let bounds = dismissRegion.frame
            let excluded = popover.frame.insetBy(dx: -8, dy: -8)
            let candidates = [
                CGPoint(x: bounds.minX + 8, y: bounds.midY),
                CGPoint(x: bounds.maxX - 8, y: bounds.midY),
                CGPoint(x: bounds.midX, y: bounds.minY + 48)
            ]
            let point = try XCTUnwrap(candidates.first { bounds.contains($0) && !excluded.contains($0) },
                                      "The native popover must expose a safe outside dismissal region")
            dismissRegion.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - bounds.minX, dy: point.y - bounds.minY)).tap()
        }
        XCTAssertTrue(waitUntil { !confirm.exists })
        XCTAssertEqual(clear.value as? String, "Available", "Cancel must retain the local fallback")
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
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
        let countLabel = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", " frames")
        ).firstMatch
        if countLabel.exists,
           let count = Int(countLabel.label.dropLast(" frames".count)) {
            return count
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
