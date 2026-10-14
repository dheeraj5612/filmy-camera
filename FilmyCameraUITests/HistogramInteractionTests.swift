import XCTest

/// Uses live preview analysis; a simulator cannot establish this acceptance.
@MainActor
final class HistogramInteractionTests: XCTestCase {
    private nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Movable histogram acceptance requires live camera hardware")
        #else
        addUIInterruptionMonitor(withDescription: "Histogram camera permission") { alert in
            MainActor.assumeIsolated {
                for title in ["Allow", "OK"] where alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    return true
                }
                return false
            }
        }
        app = MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchEnvironment["FILMY_TEST_DEFAULTS_SUITE"] = "FilmyCameraUITests.\(UUID().uuidString)"
            app.launchArguments = ["-ui-testing", "-selectedRecipeID", "classic-chrome"]
            app.launch()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let banner = springboard
                .descendants(matching: .any)["NotificationShortLookView"].firstMatch
            if banner.exists {
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                    .press(forDuration: 0.01, thenDragTo:
                        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)))
            }
            app.tap()
            return app
        }
        #endif
    }

    override func tearDownWithError() throws {
        let launchedApp = app
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
            launchedApp?.terminate()
        }
    }

    func testHistogramDragsClampsPersistsRotatesResetsAndAllowsFocusOutsideCard() throws {
        XCTAssertTrue(waitForLivePreview(), "Histogram acceptance needs fresh rendered camera frames")
        openSetup()
        let toggle = app.switches["capture-histogram-toggle"]
        reveal(toggle)
        if toggle.value as? String != "1" {
            let control = toggle.switches.firstMatch
            (control.exists ? control : toggle).tap()
        }
        XCTAssertTrue(waitUntil { toggle.value as? String == "1" })
        closeSetup()
        showCameraTools()

        let histogram = app.descendants(matching: .any)["camera-histogram"]
        let preview = app.descendants(matching: .any)["camera-preview"]
        XCTAssertTrue(histogram.waitForExistence(timeout: 15))
        XCTAssertTrue(histogram.isHittable)
        assertHistogramAvoidsControls(histogram)
        let initialFrame = histogram.frame
        let initialLook = app.buttons["recipe-menu"].label
        drag(histogram, into: preview, x: 0.8, y: 0.4)
        XCTAssertGreaterThan(histogram.frame.minX - initialFrame.minX, 30)
        XCTAssertTrue(preview.frame.insetBy(dx: -1, dy: -1).contains(histogram.frame))
        XCTAssertEqual(app.buttons["recipe-menu"].label, initialLook,
                       "Dragging the histogram must not swipe to another recipe")
        XCTAssertFalse(app.descendants(matching: .any)["camera-exposure-drag-readout"].exists,
                       "Dragging the histogram must not start an exposure drag")

        // A passive composition layer covering the entire finder would swallow
        // this tap. The focus-lock affordance appears only after a focus tap.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Lock focus and exposure"].waitForExistence(timeout: 2),
                      "A tap outside the histogram must reach preview focus")
        attachScreenshot("histogram-moved-with-focus")

        let persistedPosition = histogram.value as? String
        let persistedFrame = histogram.frame
        app.terminate()
        app.launch()
        XCTAssertTrue(histogram.waitForExistence(timeout: 20))
        XCTAssertEqual(histogram.value as? String, persistedPosition)
        XCTAssertEqual(histogram.frame.minX, persistedFrame.minX, accuracy: 2)
        XCTAssertEqual(histogram.frame.minY, persistedFrame.minY, accuracy: 2)

        let exposure = app.descendants(matching: .any)["exposure-control"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5) && exposure.isHittable)
        exposure.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["camera-active-adjustments"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(
            waitUntil {
                UIDevice.current.userInterfaceIdiom == .pad
                    ? self.app.frame.width > self.app.frame.height
                    : self.app.frame.height > self.app.frame.width
            },
            "The camera must follow the native iPad landscape or iPhone portrait orientation contract after rotation"
        )
        XCTAssertTrue(
            waitForStableContainedFrame(histogram, in: preview),
            "The histogram must settle inside the portrait camera preview after rotation"
        )
        XCTAssertEqual(histogram.value as? String, persistedPosition)
        for corner in [CGVector(dx: 0.99, dy: 0.01), CGVector(dx: 0.99, dy: 0.99)] {
            drag(histogram, into: preview, x: corner.dx, y: corner.dy)
            assertHistogramAvoidsControls(histogram)
        }
        attachScreenshot("histogram-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil { self.app.frame.height > self.app.frame.width })
        XCTAssertTrue(waitForStableContainedFrame(histogram, in: preview))

        for corner in [CGVector(dx: 0.99, dy: 0.99), CGVector(dx: 0.01, dy: 0.99),
                       CGVector(dx: 0.01, dy: 0.01), CGVector(dx: 0.99, dy: 0.01)] {
            drag(histogram, into: preview, x: corner.dx, y: corner.dy)
            XCTAssertTrue(preview.frame.insetBy(dx: -1, dy: -1).contains(histogram.frame),
                          "The whole card must stay in the finder at every edge")
            assertHistogramAvoidsControls(histogram)
        }

        drag(histogram, into: preview, x: 0.99, y: 0.99)
        let beforeToolsToggle = histogram.value as? String
        app.buttons["camera-chrome-toggle"].tap()
        XCTAssertEqual(histogram.value as? String, beforeToolsToggle)
        assertHistogramAvoidsControls(histogram)
        showCameraTools()
        XCTAssertEqual(histogram.value as? String, beforeToolsToggle)
        assertHistogramAvoidsControls(histogram)

        openSetup()
        let reset = app.buttons["capture-histogram-reset"]
        reveal(reset)
        reset.tap()
        closeSetup()
        XCTAssertTrue(histogram.waitForExistence(timeout: 10))
        XCTAssertEqual(histogram.value as? String, "Horizontal 0 percent, vertical 0 percent")
        XCTAssertEqual(histogram.frame.minX, initialFrame.minX, accuracy: 2)
        XCTAssertEqual(histogram.frame.minY, initialFrame.minY, accuracy: 2)
        attachScreenshot("histogram-reset")
    }

    func testPreviewSwipesReverseSingleTapFocusesAndDoubleTapKeepsCamera() throws {
        XCTAssertTrue(waitForLivePreview())
        let preview = app.descendants(matching: .any)["camera-preview"]
        let recipe = app.buttons["recipe-menu"]
        let initialLook = recipe.label
        XCTAssertFalse(initialLook.isEmpty)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45)))
        XCTAssertTrue(waitUntil { recipe.label != initialLook }, "A left swipe must select the next effective look")
        XCTAssertTrue(waitForLivePreview())
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)))
        XCTAssertTrue(waitUntil { recipe.label == initialLook }, "A reverse swipe must restore the previous look")

        let cameraSwitch = app.buttons["camera-switch-control"]
        let initialCamera = cameraSwitch.value as? String
        XCTAssertNotNil(initialCamera)
        cameraSwitch.tap()
        XCTAssertTrue(waitUntil { cameraSwitch.value as? String != initialCamera },
                      "The switch control must still flip cameras")
        XCTAssertTrue(waitForLivePreview())
        cameraSwitch.tap()
        XCTAssertTrue(waitUntil { cameraSwitch.value as? String == initialCamera })
        XCTAssertTrue(waitForLivePreview())
        // Switching cameras clears the focus point, so the launch tap's point is gone here.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["Lock focus and exposure"].waitForExistence(timeout: 2),
                      "A single tap must focus")
        // The lock button needs a focus point, which clears 5 s after the last focus tap.
        // The double tap re-focuses and the wait below is 2 s, so the assertion sits inside that window.
        preview.doubleTap()
        XCTAssertFalse(waitUntil(timeout: 2) { cameraSwitch.value as? String != initialCamera },
                       "Double tapping the preview must never switch cameras")
        XCTAssertTrue(app.buttons["Lock focus and exposure"].exists, "A double tap is two focus taps")
        XCTAssertEqual(recipe.label, initialLook)
        attachScreenshot("preview-single-tap-focus-double-tap-keeps-camera")
    }

    func testVerticalPreviewDragSetsExposureWithoutFocusAndShowsReadout() throws {
        XCTAssertTrue(waitForLivePreview())
        showCameraTools()
        let preview = app.descendants(matching: .any)["camera-preview"]
        let exposure = app.descendants(matching: .any)["exposure-control"]
        XCTAssertTrue(exposure.waitForExistence(timeout: 5))
        let initialEV = exposure.value as? String
        let initialLook = app.buttons["recipe-menu"].label
        let readout = app.descendants(matching: .any)["camera-exposure-drag-readout"]
        let lock = app.buttons["Lock focus and exposure"]
        // setUp's app.tap() focuses; its focus point clears after 5 s.
        XCTAssertTrue(waitUntil(timeout: 8) { !lock.exists },
                      "The launch tap's focus point must clear before the drag")

        dragPreviewUp(preview)
        // The readout lingers 1.5 s after lift: resolve it before any slow query.
        XCTAssertTrue(readout.waitForExistence(timeout: 1), "A vertical drag must show the EV readout")
        // One snapshot: the 1.5 s linger can remove the element between queries.
        let snap = try readout.snapshot()
        let readoutLabel = snap.label
        let readoutFrame = snap.frame
        attachScreenshot("exposure-drag-readout", settle: 0)
        XCTAssertTrue(readoutLabel.hasSuffix(" EV"))
        XCTAssertTrue(preview.frame.contains(readoutFrame))
        XCTAssertLessThanOrEqual(readoutFrame.width, preview.frame.width - 32,
                                 "The readout element is the capsule, not the finder")

        XCTAssertTrue(waitUntil(timeout: 5) {
            (exposure.value as? String).map { $0 != initialEV && $0.hasPrefix("plus") } ?? false
        }, "A vertical drag with no prior tap must raise exposure")
        XCTAssertEqual(app.buttons["recipe-menu"].label, initialLook)
        XCTAssertFalse(lock.exists, "A drag must not focus")
        XCTAssertTrue(waitUntil(timeout: 5) { !readout.exists }, "The readout must clear after the drag")

        let raised = exposure.value as? String
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45)))
        XCTAssertTrue(waitUntil { self.app.buttons["recipe-menu"].label != initialLook })
        XCTAssertEqual(exposure.value as? String, raised, "A look swipe must never change exposure")

        // The inner exposure-reset button is hidden by the combined element, so tap its centre.
        exposure.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil { exposure.value as? String == "plus 0.0 EV" })

        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(waitForLivePreview())
        let largePreview = app.descendants(matching: .any)["camera-preview"]
        dragPreviewUp(largePreview)
        XCTAssertTrue(readout.waitForExistence(timeout: 1))
        let largeSnap = try readout.snapshot()
        let largeReadoutFrame = largeSnap.frame
        attachScreenshot("exposure-drag-readout-largest-text", settle: 0)
        XCTAssertTrue(largePreview.frame.contains(largeReadoutFrame),
                      "The readout must fit the finder at the largest text size")
        XCTAssertLessThanOrEqual(largeReadoutFrame.width, largePreview.frame.width - 32)
    }

    private func dragPreviewUp(_ preview: XCUIElement) {
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .press(forDuration: 0.05, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
    }

    private func openSetup() {
        dismissNotificationBanner()
        let setup = app.buttons["capture-setup-open"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        setup.tap()
        if !app.buttons["capture-setup-done"].waitForExistence(timeout: 3),
           app.state != .runningForeground {
            // A notification arriving after the preflight can take the tap.
            // Restore the app before repeating the intended setup action.
            app.activate()
            dismissNotificationBanner()
            setup.tap()
        }
        XCTAssertTrue(app.buttons["capture-setup-done"].waitForExistence(timeout: 5))
    }

    private func closeSetup() {
        // A real banner intercepted the top-right Done tap during acceptance.
        // Dismiss that transient system overlay before targeting the app.
        dismissNotificationBanner()
        app.buttons["capture-setup-done"].tap()
        if app.state != .runningForeground {
            app.activate()
            dismissNotificationBanner()
            if app.buttons["capture-setup-done"].exists {
                app.buttons["capture-setup-done"].tap()
            }
        }
        XCTAssertTrue(waitUntil { !self.app.buttons["capture-setup-done"].exists },
                      "Capture setup must actually dismiss before checking the histogram")
    }

    private func dismissNotificationBanner() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard
            .descendants(matching: .any)["NotificationShortLookView"].firstMatch
        if banner.exists {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                .press(forDuration: 0.01, thenDragTo:
                    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)))
        }
        if app.state != .runningForeground { app.activate() }
        XCTAssertTrue(waitUntil(timeout: 12) { !banner.exists },
                      "Wait until the notification no longer covers camera controls")
    }

    private func showCameraTools() {
        let toggle = app.buttons["camera-chrome-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.label == "Show camera controls" { toggle.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["camera-utility-rail"].waitForExistence(timeout: 5))
    }

    private func assertHistogramAvoidsControls(_ histogram: XCUIElement) {
        for identifier in ["camera-utility-rail", "zoom-control", "camera-switch-control", "capture-setup-open",
                           "settings-tab", "camera-chrome-toggle", "camera-active-adjustments"] {
            let control = app.descendants(matching: .any)[identifier]
            guard control.exists && control.isHittable else { continue }
            XCTAssertTrue(waitUntil(timeout: 5) {
                !histogram.frame.intersects(control.frame.insetBy(dx: 1, dy: 1))
            }, "The histogram must remain clear of \(identifier)")
        }
    }

    private func reveal(_ element: XCUIElement) {
        let form = app.descendants(matching: .any)["capture-setup-form"]
        for _ in 0..<6 {
            if element.exists && element.isHittable && form.frame.contains(element.frame) { return }
            form.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func drag(_ card: XCUIElement, into preview: XCUIElement, x: CGFloat, y: CGFloat) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)))
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return condition()
    }

    private func waitForStableContainedFrame(
        _ element: XCUIElement,
        in viewport: XCUIElement,
        timeout: TimeInterval = 10
    ) -> Bool {
        var previousFrame: CGRect?
        var stableSamples = 0
        return waitUntil(timeout: timeout) {
            guard element.exists, viewport.exists else {
                previousFrame = nil
                stableSamples = 0
                return false
            }
            let frame = element.frame
            let viewportFrame = viewport.frame.insetBy(dx: -1, dy: -1)
            guard frame.width > 0, frame.height > 0, viewportFrame.contains(frame) else {
                previousFrame = nil
                stableSamples = 0
                return false
            }
            if let previousFrame,
               abs(frame.minX - previousFrame.minX) < 0.25,
               abs(frame.minY - previousFrame.minY) < 0.25,
               abs(frame.width - previousFrame.width) < 0.25,
               abs(frame.height - previousFrame.height) < 0.25 {
                stableSamples += 1
            } else {
                stableSamples = 1
            }
            previousFrame = frame
            return stableSamples >= 2
        }
    }

    private func waitForLivePreview() -> Bool {
        let status = app.descendants(matching: .any)["camera-preview-render-status"]
        var firstToken: String?
        return waitUntil(timeout: 20) {
            let shutter = self.app.buttons["Capture photo"]
            guard shutter.exists, shutter.isEnabled, status.exists,
                  let token = status.value as? String, token.hasPrefix("state=rendered;") else { return false }
            if let firstToken { return token != firstToken }
            firstToken = token
            return false
        }
    }

    private func attachScreenshot(_ name: String, settle: TimeInterval = 0.7) {
        // Geometry updates before UIKit's rotation animation finishes.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: settle))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
