import XCTest

@MainActor
final class StoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        #if targetEnvironment(simulator)
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_STORE_MEDIA"] == "1",
            "Set FILMY_RUN_STORE_MEDIA=1 and seed one public-safe photo to capture store media"
        )
        #else
        throw XCTSkip("Store screenshot capture runs only on a seeded simulator")
        #endif

        addUIInterruptionMonitor(withDescription: "Filmy Camera permissions") { alert in
            MainActor.assumeIsolated {
                for title in ["Allow", "Allow Full Access", "Allow Access to All Photos", "OK"] {
                    let button = alert.buttons[title]
                    if button.exists {
                        button.tap()
                        return true
                    }
                }
                return false
            }
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testCaptureCurrentStoreScreens() throws {
        try importSeededPhoto(
            recipeID: "g7x-compact",
            recipeName: "G7 X Compact",
            minimumPhotoCount: 1,
            screenshotName: "01-g7x-import"
        )
        try importSeededPhoto(
            recipeID: "classic-chrome",
            recipeName: "Muted Color",
            minimumPhotoCount: 2,
            screenshotName: "02-film-import"
        )
        try importSeededPhoto(
            recipeID: "acros-monochrome",
            recipeName: "Fine Monochrome",
            minimumPhotoCount: 3,
            screenshotName: "03-monochrome-import"
        )

        let openRoll = app.buttons["Open roll"]
        XCTAssertTrue(openRoll.waitForExistence(timeout: 10))
        openRoll.tap()
        XCTAssertTrue(app.staticTexts["Roll"].waitForExistence(timeout: 10))

        for recipeName in ["G7 X Compact", "Muted Color", "Fine Monochrome"] {
            let savedFrame = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", recipeName)
            ).firstMatch
            XCTAssertTrue(
                savedFrame.waitForExistence(timeout: 30),
                "Roll must contain the saved \(recipeName) treatment"
            )
        }
        attachScreenshot(named: "04-roll")

        let monochromeFrame = app.buttons.matching(
            NSPredicate(format: "label == 'Photo in your gallery, Fine Monochrome'")
        ).firstMatch
        monochromeFrame.tap()
        let photo = app.images["Photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 30))
        XCTAssertEqual(photo.value as? String, "Fit to screen")
        attachScreenshot(named: "05-photo-detail")
    }

    private func importSeededPhoto(
        recipeID: String,
        recipeName: String,
        minimumPhotoCount: Int,
        screenshotName: String
    ) throws {
        launchNormalApp(recipeID: recipeID)

        let selectedRecipe = app.buttons["recipe-\(recipeID)"]
        XCTAssertTrue(selectedRecipe.waitForExistence(timeout: 15))
        XCTAssertEqual(selectedRecipe.value as? String, "Selected")

        let importPhoto = app.buttons["import-photo"]
        XCTAssertTrue(importPhoto.waitForExistence(timeout: 10))
        importPhoto.tap()

        let photos = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        )
        XCTAssertTrue(
            waitUntil(timeout: 15) { photos.count >= minimumPhotoCount },
            "Seed exactly one public-safe source before running; prior saves should remain visible"
        )

        // PhotosPicker is newest-first. The freshly seeded original starts at
        // index zero and moves one place after each save. Fresh simulators may
        // also show older system sample placeholders; never select those.
        let originalPhoto = photos.element(boundBy: minimumPhotoCount - 1)
        let photoFrame = originalPhoto.frame
        let appFrame = app.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: (photoFrame.midX - appFrame.minX) / appFrame.width,
                dy: (photoFrame.midY - appFrame.minY) / appFrame.height
            )
        ).tap()

        XCTAssertTrue(app.staticTexts["IMPORTED PHOTO"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts[recipeName].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Filter applied'")
            ).firstMatch.exists
        )
        attachScreenshot(named: screenshotName)

        let save = app.buttons["Save filtered photo"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        app.tap()
        let savedToast = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Saved with '")
        ).firstMatch
        XCTAssertTrue(
            savedToast.waitForExistence(timeout: 20),
            "The \(recipeName) output must save before the next treatment"
        )
    }

    private func launchNormalApp(recipeID: String) {
        app?.terminate()
        app = XCUIApplication()
        // -ui-testing is intentionally absent because it denies Photos reads.
        app.launchArguments = ["-selectedRecipeID", recipeID]
        app.launch()
        app.tap()

        let onboarding = app.descendants(matching: .any)["onboarding-screen"]
        if onboarding.waitForExistence(timeout: 3) {
            let skip = app.buttons["Skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
            app.tap()
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return condition()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
