import XCTest

/// Real UI interactions with isolated preferences; physical captures are
/// retained as review screenshots and are not written to the user's library.
@MainActor
final class ComprehensiveSettingsTests: XCTestCase {
    func testEveryRecipeEditorSettingChangesAndResetRestoresTheLook() {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = ["-ui-testing", "-selectedRecipeID", "classic-chrome"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 20))
        app.buttons["recipe-menu"].tap()
        let tune = app.buttons["Tune Muted Color"]
        XCTAssertTrue(tune.waitForExistence(timeout: 5))
        tune.tap()
        XCTAssertTrue(app.staticTexts["Recipe controls"].waitForExistence(timeout: 5))

        for label in ["Exposure", "Highlights", "Shadows", "Contrast"] { exerciseSlider(label, app) }
        for title in ["AUTO", "DR100", "DR200", "DR400"] {
            choose("recipe-choice-Dynamic range", title, app)
        }
        for title in ["AUTO", "Off", "Weak", "Strong"] {
            choose("recipe-choice-D Range Priority", title, app)
        }
        exerciseSlider("Color", app)
        for (id, options) in [
            ("recipe-choice-Color Chrome", ["Off", "Weak", "Strong"]),
            ("fx-blue-control", ["Off", "Weak", "Strong"]),
            ("recipe-choice-White balance", ["AUTO", "White priority", "Ambience priority", "Daylight", "Shade",
                                            "Fluorescent 1", "Fluorescent 2", "Fluorescent 3", "Incandescent", "Underwater",
                                            "Custom 1", "Custom 2", "Custom 3", "Color temperature"])
        ] {
            for title in options { choose(id, title, app) }
        }
        for label in ["Color temperature", "Warmth", "Tint"] { exerciseSlider(label, app) }
        expandSection("Texture", app)
        for label in ["Sharpness", "Noise reduction", "Clarity"] { exerciseSlider(label, app) }
        expandSection("Finish", app)
        for title in ["Off", "Weak", "Strong"] { choose("recipe-choice-Grain Effect", title, app) }
        for title in ["Small", "Large"] { choose("recipe-choice-Grain Size", title, app) }
        for label in ["Vignette", "Halation"] { exerciseSlider(label, app) }
        XCTAssertTrue(app.buttons["Apply changes to Muted Color"].isEnabled)
        attach("all-recipe-editor-settings-modified")
        reveal(app.buttons["Reset recipe controls"], app).tap()
        XCTAssertTrue(app.buttons["Done editing Muted Color"].waitForExistence(timeout: 5),
                      "Reset must remove the entire draft, including all edited sections")
        app.buttons["Done editing Muted Color"].tap()
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 5))
    }

    func testEveryCaptureSetupOptionAndSettingsTogglePersists() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        openSetup(app)
        for title in ["3s", "5s", "10s", "Off"] {
            choose("capture-delay-picker", title, app)
        }
        for title in ["4:3", "1:1", "3:2", "16:9", "Fit screen"] {
            choose("capture-aspect-picker", title, app)
        }
        for title in ["Golden ratio", "Square guide", "Center crosshair", "Rule of thirds"] {
            choose("capture-guide-picker", title, app)
        }
        let toggles = ["capture-grid-toggle", "capture-level-toggle", "capture-histogram-toggle",
                       "capture-zebras-toggle", "capture-peaking-toggle"]
        for id in toggles {
            let control = reveal(app.switches[id], app)
            let original = control.value as? String
            setToggle(control, original == "1" ? "0" : "1")
            setToggle(control, original ?? "0")
            setToggle(control, "1")
        }
        choose("capture-delay-picker", "5s", app)
        choose("capture-aspect-picker", "3:2", app)
        choose("capture-guide-picker", "Golden ratio", app)
        closeSetup(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["capture-setup-open"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["capture-setup-open"].value as? String, "Timer 5s, 3:2")
        openSetup(app)
        assertChoice(reveal(app.descendants(matching: .any)["capture-delay-picker"], app), "5s")
        assertChoice(reveal(app.descendants(matching: .any)["capture-aspect-picker"], app), "3:2")
        assertChoice(reveal(app.descendants(matching: .any)["capture-guide-picker"], app), "Golden ratio")
        for id in toggles { XCTAssertEqual(reveal(app.switches[id], app).value as? String, "1", id) }
        attach("every-capture-option-restored")
        closeSetup(app)
        app.buttons["settings-tab"].tap()
        for label in ["Framing grid", "Haptic feedback"] {
            setToggle(reveal(app.switches[label], app), "0")
        }
        app.buttons["settings-back-to-camera"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 20))
        app.buttons["settings-tab"].tap()
        for label in ["Framing grid", "Haptic feedback"] {
            let toggle = reveal(app.switches[label], app)
            XCTAssertEqual(toggle.value as? String, "0", label)
            setToggle(toggle, "1")
        }
        // Clearing an existing personal cache is intentionally not a UI test.
        // Cache deletion and recovery are covered with owned fixture files.
        XCTAssertTrue(reveal(app.buttons["clear-local-cache"], app, requireHittable: false).exists)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["privacy-policy-link"], app).isHittable)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["support-link"], app).isHittable)
        attach("settings-links-storage-and-preferences")
        app.buttons["settings-back-to-camera"].tap()
        openSetup(app)
        XCTAssertEqual(reveal(app.switches["capture-grid-toggle"], app).value as? String, "1",
                       "Settings and Capture setup must share the grid preference")
    }

    func testMonochromeEditorAxesChangeAndReset() {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = ["-ui-testing", "-selectedRecipeID", "acros-neutral-filter"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["recipe-menu"].waitForExistence(timeout: 20))
        app.buttons["recipe-menu"].tap()
        let tune = app.buttons["Tune Neutral Monochrome"]
        XCTAssertTrue(tune.waitForExistence(timeout: 5))
        tune.tap()
        XCTAssertTrue(app.staticTexts["Monochrome recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["Color"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipe-choice-Color Chrome"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["fx-blue-control"].exists)
        for label in ["Monochromatic warm-cool", "Monochromatic green-magenta"] {
            exerciseSlider(label, app)
        }
        XCTAssertTrue(app.buttons["Apply changes to Neutral Monochrome"].isEnabled)
        attach("monochrome-editor-both-color-axes-modified")
        reveal(app.buttons["Reset recipe controls"], app).tap()
        XCTAssertTrue(app.buttons["Done editing Neutral Monochrome"].waitForExistence(timeout: 5))
        app.buttons["Done editing Neutral Monochrome"].tap()
    }

    func testPhysicalEveryAspectAndTimerCapturesThenFrontCameraReturnsLive() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires a real iPhone camera")
        #else
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let cases: [(String, String, CGFloat?)] = [
            ("Fit screen", "Off", nil), ("4:3", "3s", 3.0 / 4.0),
            ("1:1", "5s", 1), ("3:2", "10s", 2.0 / 3.0), ("16:9", "Off", 9.0 / 16.0)
        ]
        for (aspect, delay, ratio) in cases {
            openSetup(app)
            choose("capture-delay-picker", delay, app)
            choose("capture-aspect-picker", aspect, app)
            closeSetup(app)
            requireLive(app)
            let preview = app.descendants(matching: .any)["camera-preview"]
            let expectedRatio = ratio ?? preview.frame.width / preview.frame.height
            XCTAssertEqual(preview.frame.width / preview.frame.height, expectedRatio, accuracy: 0.015)
            app.buttons["Capture photo"].tap()
            if delay != "Off" {
                XCTAssertTrue(app.buttons["capture-countdown-cancel"].waitForExistence(timeout: 2))
            }
            requireReview(app)
            let finish = app.buttons["review-finish-photo"]
            finish.tap()
            XCTAssertTrue(wait { finish.value as? String == "Selected" && app.buttons["Keep frame"].isEnabled })
            let photo = app.descendants(matching: .any)["review-image"]
            XCTAssertEqual(photo.frame.width / photo.frame.height, expectedRatio, accuracy: 0.02,
                           "Review must retain the \(aspect) capture framing")
            attach("physical-crop-\(aspect.replacingOccurrences(of: ":", with: "x"))-timer-\(delay)")
            app.buttons["Retake"].tap()
            requireLive(app)
        }
        let cameraSwitch = app.buttons["camera-switch-control"]
        let originalPosition = cameraSwitch.value as? String
        cameraSwitch.tap()
        XCTAssertTrue(wait { cameraSwitch.value as? String != originalPosition })
        requireLive(app)
        app.buttons["Capture photo"].tap()
        requireReview(app)
        attach("physical-front-camera-review")
        app.buttons["Retake"].tap()
        requireLive(app)
        cameraSwitch.tap()
        XCTAssertTrue(wait { cameraSwitch.value as? String == originalPosition })
        requireLive(app)
        #endif
    }

    private func makeApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.AllSettings.\(UUID().uuidString)"
        app.launchArguments = ["-ui-testing", "-selectedRecipeID", "g7x-compact"]
        return app
    }

    private func openSetup(_ app: XCUIApplication) {
        waitForUnobscuredApp(app)
        XCTAssertTrue(app.buttons["capture-setup-open"].waitForExistence(timeout: 20))
        app.buttons["capture-setup-open"].tap()
        XCTAssertTrue(app.buttons["capture-setup-done"].waitForExistence(timeout: 5))
    }

    private func closeSetup(_ app: XCUIApplication) {
        waitForUnobscuredApp(app)
        let done = app.buttons["capture-setup-done"]
        XCTAssertTrue(done.exists && done.isHittable)
        done.tap()
        XCTAssertTrue(wait {
            app.state == .runningForeground && !done.exists
                && app.buttons["capture-setup-open"].exists
        }, "Capture setup must dismiss and leave the camera app in the foreground")
    }

    private func waitForUnobscuredApp(_ app: XCUIApplication) {
        // A real notification banner intercepted Done and opened another app.
        // Wait for its disappearance before touching the top controls; do not
        // swipe a banner that can disappear while XCTest prepares the gesture.
        if app.state != .runningForeground { app.activate() }
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .descendants(matching: .any)["NotificationShortLookView"].firstMatch
        XCTAssertTrue(wait(timeout: 20) {
            app.state == .runningForeground && !banner.exists
        }, "The camera app must be foregrounded with no notification over its controls")
    }

    private func choose(_ id: String, _ title: String, _ app: XCUIApplication) {
        let picker = reveal(app.descendants(matching: .any)[id], app)
        picker.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        assertChoice(picker, title)
    }

    private func assertChoice(_ picker: XCUIElement, _ title: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI menu pickers can expose the current choice in their label
        // instead of value. Read only this picker, never the menu's options or
        // unrelated text, so a successful tap alone cannot satisfy the test.
        let selected = wait {
            guard picker.exists, picker.isHittable else { return false }
            if picker.value as? String == title { return true }
            return picker.label.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains(title)
        }
        if !selected {
            let diagnostics = XCTAttachment(string: picker.debugDescription)
            diagnostics.name = "picker-selection-\(picker.identifier)"
            diagnostics.lifetime = .keepAlways
            add(diagnostics)
            attach("picker-selection-failure")
        }
        XCTAssertTrue(selected,
                      "\(picker.identifier) should select \(title); value=\(String(describing: picker.value)), label=\(picker.label)",
                      file: file, line: line)
    }

    private func reveal(_ control: XCUIElement, _ app: XCUIApplication, requireHittable: Bool = true) -> XCUIElement {
        let form = app.descendants(matching: .any)["capture-setup-form"]
        let editor = app.descendants(matching: .any)["recipe-detail-scroll"]
        let scroll = form.exists ? form : (editor.exists ? editor : app.scrollViews.firstMatch)
        for _ in 0..<22 {
            var viewport = scroll.frame.intersection(app.frame)
            let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apply changes to ' OR label BEGINSWITH 'Done editing '")).firstMatch
            if editor.exists && action.exists {
                viewport.size.height = max(0, min(viewport.height, action.frame.minY - viewport.minY - 8))
            }
            if control.exists && (!requireHittable || control.isHittable) && viewport.contains(control.frame) { return control }
            let downward = control.exists && control.frame.midY < viewport.midY
            // Use a measured, bounded movement in the editor's margin. A
            // full-height swipe can jump past a nearby slider and alternate
            // between opposite sides of the pinned Apply button forever.
            if editor.exists {
                let overflow = control.exists
                    ? (downward ? viewport.minY - control.frame.minY : control.frame.maxY - viewport.maxY)
                    : viewport.height * 0.3
                let distance = min(max(overflow + 28, 80), viewport.height * 0.35)
                let start = CGPoint(x: viewport.minX + 8, y: downward ? viewport.minY + 40 : viewport.maxY - 40)
                let end = CGPoint(x: start.x, y: start.y + (downward ? distance : -distance))
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
            } else if downward { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        let diagnostics = XCTAttachment(string: "Target: \(control.debugDescription)\nScroll: \(scroll.debugDescription)")
        diagnostics.name = "unrevealed-control-geometry"
        diagnostics.lifetime = .keepAlways
        add(diagnostics)
        attach("unrevealed-control")
        XCTFail("Could not fully reveal \(control.identifier.isEmpty ? control.label : control.identifier)")
        return control
    }

    private func exerciseSlider(_ title: String, _ app: XCUIApplication) {
        let slider = reveal(app.sliders[title], app)
        slider.adjust(toNormalizedSliderPosition: 0.1)
        let low = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertNotEqual(slider.value as? String, low, "\(title) must react across its range")
    }

    private func expandSection(_ title: String, _ app: XCUIApplication) {
        let section = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ",")).firstMatch
        // Disclosure groups expose the title and description together.
        let fallback = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        reveal(section.exists ? section : fallback, app).tap()
    }

    private func setToggle(_ row: XCUIElement, _ value: String) {
        if row.value as? String == value { return }
        let control = row.switches.count == 1 ? row.switches.firstMatch : row
        XCTAssertTrue(control.isEnabled && control.isHittable)
        control.tap()
        XCTAssertTrue(wait { row.value as? String == value }, "\(row.label) must become \(value)")
    }

    private func requireLive(_ app: XCUIApplication) {
        let shutter = app.buttons["Capture photo"]
        let status = app.descendants(matching: .any)["camera-preview-render-status"]
        var firstToken: String?
        XCTAssertTrue(wait(timeout: 20) {
            guard shutter.exists, shutter.isEnabled, status.exists,
                  let token = status.value as? String, token.hasPrefix("state=rendered;") else { return false }
            if let firstToken { return token != firstToken }
            firstToken = token
            return false
        }, "The viewfinder must deliver two fresh GPU-rendered frames")
    }

    private func requireReview(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Keep frame"].waitForExistence(timeout: 45))
        XCTAssertTrue(wait { app.buttons["Keep frame"].isEnabled && app.descendants(matching: .any)["review-image"].exists })
    }

    private func wait(timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return false
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
