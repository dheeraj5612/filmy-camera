import XCTest
@testable import FilmyCamera

@MainActor
final class SceneAutoIntegrationTests: XCTestCase {
    func testCameraConstructionDoesNotEnableSceneAutoOrAlterManualControls() {
        let camera = CameraService()
        XCTAssertEqual(camera.sceneAuto, SceneAutoState())
        XCTAssertEqual(camera.manualControls, .unavailable)
        XCTAssertEqual(camera.exposureBias, 0)
    }

    func testNeutralDevelopmentIsExactIdentityForEveryBuiltIn() {
        for recipe in FilmRecipe.builtIns {
            XCTAssertEqual(SceneAutoDevelopment().applying(to: recipe), recipe, recipe.id)
        }
    }

    func testDevelopmentChangesOnlyTheFourOwnedFields() throws {
        let original = try XCTUnwrap(FilmRecipe.builtIns.first)
        let adjustment = SceneAutoDevelopment(highlights: -0.16, shadows: -0.12, noiseReduction: 0.16, sharpness: -0.1)
        let developed = adjustment.applying(to: original)
        var reversed = developed
        reversed.tone.highlight = original.tone.highlight
        reversed.tone.shadow = original.tone.shadow
        reversed.noiseReduction = original.noiseReduction
        reversed.sharpness = original.sharpness
        XCTAssertEqual(reversed, original)
        XCTAssertEqual(developed.id, original.id)
        XCTAssertEqual(developed.filmBase, original.filmBase)
        XCTAssertEqual(developed.grain, original.grain)
        XCTAssertEqual(developed.whiteBalance, original.whiteBalance)
    }

    func testDevelopmentClampsWithoutMutatingSavedRecipe() throws {
        var recipe = try XCTUnwrap(FilmRecipe.builtIns.first)
        recipe.tone.highlight = -0.95
        recipe.tone.shadow = -0.95
        recipe.noiseReduction = 0.95
        recipe.sharpness = -0.95
        let baseline = recipe
        let adjustment = SceneAutoDevelopment(highlights: -0.16, shadows: -0.12, noiseReduction: 0.16, sharpness: -0.1)
        let developed = adjustment.applying(to: recipe)
        XCTAssertEqual(developed.tone.highlight, -1)
        XCTAssertEqual(developed.tone.shadow, -1)
        XCTAssertEqual(developed.noiseReduction, 1)
        XCTAssertEqual(developed.sharpness, -1)
        XCTAssertEqual(recipe, baseline)
    }

    func testShutterSnapshotIsIndependentOfLaterAutoDevelopment() throws {
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first)
        var development = SceneAutoDevelopment(highlights: -0.1)
        let captured = development.applying(to: recipe)
        let expected = captured
        development.highlights = 0
        development.shadows = -0.12
        _ = development.applying(to: recipe)
        XCTAssertEqual(captured, expected)
        XCTAssertEqual(captured.tone.highlight, max(recipe.tone.highlight - 0.1, -1))
    }

    func testAutoFacePointUsesExistingPortraitAndFrontMirroringTransform() {
        let previewPoint = CGPoint(x: 0.2, y: 0.3)
        let rear = CameraService.captureDevicePoint(fromRotatedPreviewPoint: previewPoint, rotationAngle: 90, mirrored: false)
        let front = CameraService.captureDevicePoint(fromRotatedPreviewPoint: previewPoint, rotationAngle: 90, mirrored: true)
        XCTAssertEqual(rear.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(rear.y, 0.8, accuracy: 0.000001)
        XCTAssertEqual(front.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(front.y, 0.2, accuracy: 0.000001)
    }

    private final class ObservationRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [SceneAutoObservation] = []
        func add(_ observation: SceneAutoObservation) { lock.lock(); stored.append(observation); lock.unlock() }
        var observations: [SceneAutoObservation] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private func skipWhenThrottled() throws {
        let state = ProcessInfo.processInfo.thermalState
        let constrained = state == .serious || state == .critical || ProcessInfo.processInfo.isLowPowerModeEnabled
        try XCTSkipIf(constrained, "The analyzer throttles under thermal or Low Power pressure")
    }

    private func submit(_ analyzer: SceneAutoAnalyzer, _ image: CIImage, generation: UInt64,
                        expecting count: Int, wait: TimeInterval = 120) async -> [SceneAutoObservation] {
        let recorder = ObservationRecorder()
        let delivered = expectation(description: "scene auto observation")
        delivered.expectedFulfillmentCount = max(count, 1)
        delivered.isInverted = count == 0
        analyzer.submit(image, generation: generation) { observation, _ in
            recorder.add(observation)
            delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: count == 0 ? 0.5 : wait)
        return recorder.observations
    }

    private func splitFrame(whiteOnLeft: Bool) -> CIImage {
        let full = CGRect(x: 0, y: 0, width: 64, height: 48)
        let half = CGRect(x: whiteOnLeft ? 0 : 32, y: 0, width: 32, height: 48)
        let base = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: full)
        return CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: half).composited(over: base)
    }

    func testAnalyzerAcceptsOffsetExtent() async throws {
        try skipWhenThrottled()
        let analyzer = SceneAutoAnalyzer(detectsFaces: false)
        let offset = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 100, y: 100, width: 64, height: 48))
        let result = await submit(analyzer, offset, generation: 1, expecting: 1)
        XCTAssertEqual(result.count, 1)
        let median = try XCTUnwrap(result.first?.median)
        XCTAssertEqual(median, 0.5, accuracy: 0.05)
    }

    func testAnalyzerSurvivesEmptyFrameAndStillDeliversNext() async throws {
        try skipWhenThrottled()
        let analyzer = SceneAutoAnalyzer(detectsFaces: false)
        let empty = await submit(analyzer, CIImage.empty(), generation: 1, expecting: 0)
        XCTAssertTrue(empty.isEmpty)
        try await Task.sleep(nanoseconds: 600_000_000)
        let result = await submit(analyzer, splitFrame(whiteOnLeft: true), generation: 1, expecting: 1)
        XCTAssertEqual(result.count, 1)
    }

    func testAnalyzerGenerationChangeClearsMotionHistory() async throws {
        try skipWhenThrottled()
        let analyzer = SceneAutoAnalyzer(detectsFaces: false)
        let first = await submit(analyzer, splitFrame(whiteOnLeft: true), generation: 1, expecting: 1)
        XCTAssertEqual(first.first?.motion, 0)
        try await Task.sleep(nanoseconds: 600_000_000)
        let moved = await submit(analyzer, splitFrame(whiteOnLeft: false), generation: 1, expecting: 1)
        XCTAssertGreaterThan(moved.first?.motion ?? 0, 0.1)
        try await Task.sleep(nanoseconds: 600_000_000)
        let reset = await submit(analyzer, splitFrame(whiteOnLeft: true), generation: 2, expecting: 1)
        XCTAssertEqual(reset.first?.motion, 0)
    }
}
