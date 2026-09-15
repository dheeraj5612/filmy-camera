import CoreImage
import UIKit
import XCTest
@testable import FilmyCamera

@MainActor
final class FujiShootingTests: XCTestCase {
    private var recipe: FilmRecipe { FilmRecipe.builtIns[0] }

    func testAllDriveModesHaveBoundedCapturePlans() throws {
        for drive in FujiDrive.allCases {
            var settings = FujiShootingSettings()
            settings.drive = drive
            let plan = try FujiCapturePlan.make(settings)
            XCTAssertFalse(plan.steps.isEmpty, drive.rawValue)
            XCTAssertLessThanOrEqual(plan.steps.count, 120, drive.rawValue)
        }
    }

    func testFilmISOAndWBBracketsShareOneSensorFrame() throws {
        for drive in [FujiDrive.filmBracket, .isoBracket, .whiteBalanceBracket] {
            var settings = FujiShootingSettings()
            settings.drive = drive
            XCTAssertEqual(try FujiCapturePlan.make(settings).steps.count, 1)
        }
    }

    func testAEBracketOrdersAndStopSpacing() {
        XCTAssertEqual(FujiMath.bracketOffsets(count: 5, step: 0.5, order: .centerFirst), [0, -0.5, 0.5, -1, 1])
        XCTAssertEqual(FujiMath.bracketOffsets(count: 3, step: 1, order: .ascending), [-1, 0, 1])
        XCTAssertEqual(FujiMath.bracketOffsets(count: 3, step: 1, order: .descending), [1, 0, -1])
    }

    func testDRBracketRequiresThreeDistinctProtectedRAWCaptures() throws {
        var settings = FujiShootingSettings()
        settings.drive = .dynamicRangeBracket
        let plan = try FujiCapturePlan.make(settings)
        XCTAssertTrue(settings.needsRAW)
        XCTAssertEqual(plan.steps.map(\.dynamicRange), [.dr100, .dr200, .dr400])
        XCTAssertEqual(plan.steps.map { $0.dynamicRange.protectionStops }, [0, 1, 2])
    }

    func testDRExposureChangesSensorProductRatherThanMetadataOnly() throws {
        let base = FujiExposure(iso: 200, seconds: 1.0 / 125)
        let result = try FujiMath.shiftedExposure(base, stops: -2, isoRange: 50...3200, durationRange: (1.0 / 8000)...1)
        XCTAssertEqual(result.iso, 200, accuracy: 0.01)
        XCTAssertEqual(result.seconds, 1.0 / 500, accuracy: 0.000001)
        XCTAssertEqual(result.product, base.product / 4, accuracy: 0.000001)
    }

    func testUnattainableDRExposureFailsBeforeShooting() {
        XCTAssertThrowsError(try FujiMath.shiftedExposure(.init(iso: 50, seconds: 1.0 / 8000), stops: -2,
                                                         isoRange: 50...3200, durationRange: (1.0 / 8000)...1))
    }

    func testAutoISOUsesBaseISOInBrightLight() {
        let result = FujiMath.autoExposure(metered: .init(iso: 100, seconds: 1.0 / 500),
            profile: .init(minimumISO: 100, maximumISO: 800, minimumShutterSeconds: 1.0 / 125),
            isoRange: 50...6400, durationRange: (1.0 / 8000)...1)
        XCTAssertEqual(result.iso, 100, accuracy: 0.01)
        XCTAssertEqual(result.seconds, 1.0 / 500, accuracy: 0.000001)
    }

    func testAutoISORaisesISOBeforeDroppingBelowPreferredShutter() {
        let result = FujiMath.autoExposure(metered: .init(iso: 100, seconds: 1.0 / 30),
            profile: .init(minimumISO: 100, maximumISO: 800, minimumShutterSeconds: 1.0 / 125),
            isoRange: 50...6400, durationRange: (1.0 / 8000)...1)
        XCTAssertEqual(result.iso, 100 * 125 / 30, accuracy: 0.01)
        XCTAssertEqual(result.seconds, 1.0 / 125, accuracy: 0.000001)
    }

    func testAutoISOSlowsShutterAtISOCeilingAndHonorsHardwareRange() {
        let result = FujiMath.autoExposure(metered: .init(iso: 100, seconds: 0.2),
            profile: .init(minimumISO: 100, maximumISO: 800, minimumShutterSeconds: 1.0 / 125),
            isoRange: 50...6400, durationRange: (1.0 / 8000)...1)
        XCTAssertEqual(result.iso, 800, accuracy: 0.01)
        XCTAssertEqual(result.seconds, 0.025, accuracy: 0.000001)
    }

    func testFocalLengthRuleUsesMotionMultiplier() {
        let profile = FujiAutoISOProfile(minimumISO: 100, maximumISO: 3200, minimumShutterSeconds: 0.1,
                                         useFocalLengthRule: true, motionMultiplier: 2)
        let result = FujiMath.autoExposure(metered: .init(iso: 100, seconds: 0.1), profile: profile,
            isoRange: 50...6400, durationRange: (1.0 / 8000)...1, focalLength: 50)
        XCTAssertEqual(result.seconds, 0.01, accuracy: 0.000001)
        XCTAssertEqual(result.iso, 1000, accuracy: 0.01)
    }

    func testSettingsNormalizationBoundsMemoryAndRejectsNonfiniteValues() {
        var settings = FujiShootingSettings()
        settings.digitalCrop = .infinity; settings.ndStops = 100; settings.burstCount = Int.max
        settings.preShotSeconds = .nan; settings.focusCount = -5; settings.bracketCount = 42
        settings.autoISOProfiles = []; settings.autoISOIndex = 999; settings.filmRecipeIDs = []
        let clean = settings.normalized()
        XCTAssertEqual(clean.digitalCrop, 1)
        XCTAssertEqual(clean.ndStops, 5)
        XCTAssertEqual(clean.burstCount, 20)
        XCTAssertEqual(clean.preShotSeconds, 0)
        XCTAssertEqual(clean.focusCount, 2)
        XCTAssertEqual(clean.bracketCount, 3)
        XCTAssertEqual(clean.autoISOProfiles.count, 3)
        XCTAssertNil(clean.autoISOIndex)
        XCTAssertEqual(clean.filmRecipeIDs.count, 3)
    }

    func testPreShotRejectsRAWAndDriveCombinations() {
        var settings = FujiShootingSettings()
        settings.preShotSeconds = 1
        XCTAssertNoThrow(try FujiCapturePlan.make(settings))
        settings.captureRAW = true
        XCTAssertThrowsError(try FujiCapturePlan.make(settings))
        settings.captureRAW = false; settings.drive = .continuousLow
        XCTAssertThrowsError(try FujiCapturePlan.make(settings))
    }

    func testFocusSweepContainsBothEndpointsAndCanReverse() throws {
        XCTAssertEqual(FujiMath.focusPositions(near: 0.2, far: 0.8, count: 3)[1], 0.5, accuracy: 0.00001)
        XCTAssertEqual(FujiMath.focusPositions(near: 1, far: 0, count: 3), [1, 0.5, 0])
        var settings = FujiShootingSettings()
        settings.drive = .focusStack; settings.focusNear = 0.5; settings.focusFar = 0.5
        XCTAssertThrowsError(try FujiCapturePlan.make(settings))
    }

    func testNDUsesPowerOfTwoFramesAndNeverChangesExposureByDarkening() throws {
        var settings = FujiShootingSettings()
        settings.drive = .computationalND; settings.ndStops = 4
        let plan = try FujiCapturePlan.make(settings)
        XCTAssertEqual(plan.steps.count, 16)
        XCTAssertTrue(plan.steps.allSatisfy { $0.exposureOffset == 0 })
    }

    func testNaturalViewAndOVFDoNotChangeCaptureRecipeOrCrop() {
        var settings = FujiShootingSettings()
        settings.digitalCrop = 2
        XCTAssertEqual(settings.previewCrop, 2)
        settings.viewfinder = .hybrid
        XCTAssertEqual(settings.previewCrop, 1)
        XCTAssertEqual(settings.digitalCrop, 2)
        XCTAssertTrue(settings.showsNaturalPreview)
    }

    func testPreferencesRoundTripKeepsSevenExplicitBanksAndOrderedQMenu() throws {
        var preferences = FujiPreferences()
        preferences.banks = (1...9).map { .init(id: $0, name: "  Custom \($0)  ", recipe: recipe,
            settings: .init(), camera: .init(), savedAt: Date(timeIntervalSince1970: 100)) }
        preferences.quickControls = [.drive, .banks, .drive, .rawDevelopment]
        preferences.selectedBank = 9
        let restored = try JSONDecoder().decode(FujiPreferences.self, from: JSONEncoder().encode(preferences)).normalized()
        XCTAssertEqual(restored.banks.map(\.id), Array(1...7))
        XCTAssertEqual(restored.banks[0].name, "Custom 1")
        XCTAssertEqual(restored.quickControls, [.drive, .banks, .rawDevelopment])
        XCTAssertNil(restored.selectedBank)
    }

    func testCorruptSettingsAreRecoverableInsteadOfSilentlyOverwritten() throws {
        let suite = "FujiShootingTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let damaged = Data("{invalid".utf8)
        defaults.set(damaged, forKey: "fuji.shooting.v1")
        let result = FujiPreferences.load(from: defaults)
        XCTAssertTrue(result.recovered)
        XCTAssertEqual(defaults.data(forKey: "fuji.shooting.recovery"), damaged)
    }

    func testCompletionGateAllowsOnlyOneCallbackAcrossConcurrentRacers() async {
        let completed = expectation(description: "exactly one callback")
        completed.assertForOverFulfill = true
        let gate = FujiCompletionGate<Int> { _ in completed.fulfill() }
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 { group.addTask { gate.finish(.success(index)) } }
        }
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertFalse(gate.finish(.failure(FujiShootingError.cancelled)))
    }

    func testPreShotRingNeverReturnsFutureFramesOrUnboundedHistory() throws {
        let image = try XCTUnwrap(UIImage(data: jpeg()).flatMap(\.cgImage))
        var ring = FujiPreShotRing()
        for index in 0..<40 {
            ring.append(.init(image: image, capturedAt: Date(), uptime: Double(index) / 10), seconds: 1.5)
        }
        XCTAssertLessThanOrEqual(ring.frames.count, 16)
        XCTAssertLessThanOrEqual(ring.byteCount, FujiPreShotRing.maximumBytes)
        XCTAssertTrue(ring.snapshot(at: 3.5, seconds: 1).allSatisfy { $0.uptime <= 3.5 && $0.uptime >= 2.5 })
        let count = ring.frames.count
        ring.append(.init(image: image, capturedAt: Date(), uptime: 0.1), seconds: 1.5)
        XCTAssertEqual(ring.frames.count, count)
        ring.clear()
        XCTAssertEqual(ring.byteCount, 0)
    }

    func testDigitalCropIsCenteredAndDoesNotUpscaleOutput() {
        let input = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let cropped = FujiImageProcessor.crop(input, factor: 2)
        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 200, height: 150))
        let square = FujiImageProcessor.crop(input, factor: 2, viewport: CGSize(width: 1, height: 1))
        XCTAssertEqual(square.extent.width, 150, accuracy: 1)
        XCTAssertEqual(square.extent.height, 150, accuracy: 1)
    }

    func testJPEGCannotMasqueradeAsProtectedRAW() {
        let data = jpeg()
        XCTAssertFalse(FujiImageProcessor.isRAW(data))
        XCTAssertThrowsError(try FujiImageProcessor.decoded(data, isRAW: false, dynamicRange: .dr400))
        XCTAssertThrowsError(try FujiImageProcessor.decoded(data, isRAW: true, dynamicRange: .dr100))
    }

    func testLinearDevelopmentRestoresMiddleGrayAndRollsOffHighlights() throws {
        let middle = CIImage(color: CIColor(red: 0.045, green: 0.045, blue: 0.045, colorSpace: FujiImageProcessor.linearSpace)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let restored = try XCTUnwrap(FujiImageProcessor.developLinear(middle, gain: 4, recovery: 0.5, shadows: 0))
        XCTAssertEqual(pixel(restored)[0], 0.18, accuracy: 0.005)
        let bright = middle.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 4])
        let protected = try XCTUnwrap(FujiImageProcessor.developLinear(bright, gain: 4, recovery: 0.5, shadows: 0))
        XCTAssertGreaterThan(pixel(protected)[0], 0.6)
        XCTAssertLessThan(pixel(protected)[0], 1)
    }

    func testTemporalAverageIsLinearLightRatherThanGammaAverage() {
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let white = CIImage(color: .white).cropped(to: black.extent)
        let result = FujiImageProcessor.blend(black, white, count: 2, mode: .average)
        XCTAssertEqual(pixel(result)[0], 0.5, accuracy: 0.01)
        XCTAssertEqual(pixel(result)[3], 1, accuracy: 0.01)
    }

    func testFocusFusionPreservesFlatTieInsteadOfReplacingIt() throws {
        let image = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        let merged = try FujiImageProcessor.fuse(image, score: FujiImageProcessor.sharpness(image), candidate: image)
        XCTAssertEqual(merged.0.extent, image.extent)
        XCTAssertEqual(pixel(merged.0)[0], pixel(image)[0], accuracy: 0.01)
    }

    func testOriginalBytesSurviveSidecarEditingAndRelaunch() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FujiCaptureLibrary(root: root)
        let data = jpeg()
        var record = original()
        try await library.retainOriginal(data, record: record)
        record.adjustment.exposure = 1.5
        try await library.updateOriginal(record)
        let reopened = FujiCaptureLibrary(root: root)
        let records = try await reopened.originals()
        let bytes = try await reopened.originalData(record)
        XCTAssertEqual(records.first?.adjustment.exposure, 1.5)
        XCTAssertEqual(bytes, data)
        do { try await reopened.retainOriginal(Data([0]), record: record); XCTFail("Original must not be overwritten") }
        catch { XCTAssertEqual(error as? FujiShootingError, .storageFailed) }
    }

    func testOutboxSurvivesRelaunchAndDeletesOnlyOnAcknowledgment() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FujiCaptureLibrary(root: root)
        let data = jpeg()
        let pending = try await library.enqueue(data, recipe: recipe, capturedAt: Date(), label: "Test")
        let reopened = FujiCaptureLibrary(root: root)
        let exports = try await reopened.pendingExports()
        XCTAssertEqual(exports.map(\.id), [pending.id])
        let bytes = try await reopened.exportData(pending)
        XCTAssertEqual(bytes, data)
        try await reopened.markExported(pending)
        let remaining = try await reopened.pendingExports()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testOriginalFilenameCannotEscapeLibraryDirectory() {
        let record = FujiOriginalRecord(id: UUID(), capturedAt: Date(), isRAW: true, sourceFilename: "../../outside.dng",
            sequenceID: UUID(), dynamicRange: .dr100, captureExposure: nil, recipe: recipe, adjustment: .init(),
            cropFactor: 1, viewportWidth: 0, viewportHeight: 0, label: "Malicious filename")
        XCTAssertFalse(record.hasSafeSourceFilename)
    }

    func testFilmBracketCapturesOnceRestoresBeforeSavingAndExportsThreeLooks() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FujiCaptureLibrary(root: root)
        let controller = FujiShootingController(library: library)
        let driver = FujiTestDriver(data: jpeg())
        let saver = FujiTestSaver(driver: driver)
        var settings = FujiShootingSettings(); settings.drive = .filmBracket
        try await controller.run(request(settings), driver: driver, photoLibrary: saver)
        XCTAssertEqual(driver.counts.captures, 1)
        XCTAssertEqual(driver.counts.restores, 1)
        XCTAssertEqual(saver.savedCount, 3)
        XCTAssertTrue(saver.restoredBeforeEverySave)
        let pending = try await library.pendingExports()
        XCTAssertTrue(pending.isEmpty)
    }

    func testSensorFailureAlwaysRestoresLeaseWithoutSaving() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = FujiShootingController(library: FujiCaptureLibrary(root: root))
        let driver = FujiTestDriver(data: jpeg(), failure: .timedOut)
        let saver = FujiTestSaver(driver: driver)
        do { try await controller.run(request(.init()), driver: driver, photoLibrary: saver); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? FujiShootingError, .timedOut) }
        XCTAssertEqual(driver.counts.restores, 1)
        XCTAssertEqual(saver.savedCount, 0)
    }

    func testFailedPhotosSaveKeepsOriginalAndExactRenderedExport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FujiCaptureLibrary(root: root)
        let controller = FujiShootingController(library: library)
        let driver = FujiTestDriver(data: jpeg())
        let saver = FujiTestSaver(driver: driver, failSave: true)
        do { try await controller.run(request(.init()), driver: driver, photoLibrary: saver); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? PhotoLibrarySaveError, .accessDenied) }
        let pending = try await library.pendingExports()
        let originals = try await library.originals()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(originals.count, 1)
        let data = try await library.exportData(XCTUnwrap(pending.first))
        XCTAssertEqual(data, saver.lastData)
        XCTAssertEqual(driver.counts.restores, 1)
    }

    private func request(_ settings: FujiShootingSettings) -> FujiSequenceRequest {
        .init(settings: settings, recipe: recipe, filmRecipes: Array(FilmRecipe.builtIns.prefix(3)),
              viewport: CGSize(width: 4, height: 3), finish: .photo, grainSeed: 1, shutterUptime: 0)
    }
    private func original() -> FujiOriginalRecord {
        .init(id: UUID(), capturedAt: Date(), isRAW: false, sourceFilename: "source.jpg", sequenceID: UUID(),
              dynamicRange: .dr100, captureExposure: nil, recipe: recipe, adjustment: .init(), cropFactor: 1,
              viewportWidth: 0, viewportHeight: 0, label: "Test original")
    }
    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 160, height: 120), format: format).jpegData(withCompressionQuality: 0.95) { context in
            UIColor(white: 0.5, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
        }
    }
    private func pixel(_ image: CIImage) -> [Float] {
        var result = [Float](repeating: 0, count: 4)
        FujiImageProcessor.context.render(image, toBitmap: &result, rowBytes: 16,
            bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
            format: .RGBAf, colorSpace: FujiImageProcessor.linearSpace)
        return result
    }
}

private final class FujiTestDriver: FujiCaptureDriver, @unchecked Sendable {
    private let data: Data
    private let failure: FujiShootingError?
    private let lock = NSLock()
    private var captures = 0
    private var restores = 0
    var counts: (captures: Int, restores: Int) { lock.withLock { (captures, restores) } }
    init(data: Data, failure: FujiShootingError? = nil) { self.data = data; self.failure = failure }
    func beginFujiCapture(requiresRAW: Bool, requiresCustomExposure: Bool, requiresFocus: Bool) async throws -> FujiSensorSnapshot {
        .init(transactionID: UUID(), deviceID: "fake", exposure: .init(iso: 100, seconds: 1.0 / 125),
              isoRange: 50...6400, durationRange: (1.0 / 8000)...1, lensPosition: 0.5, supportsFocus: true, supportsRAW: false)
    }
    func prepareFujiFrame(transactionID: UUID, exposure: FujiExposure?, focusPosition: Double?) async throws {}
    func captureFujiFrame(transactionID: UUID, requiresRAW: Bool) async throws -> FujiCapturedFrame {
        lock.withLock { captures += 1 }
        if let failure { throw failure }
        return .init(processedData: data, rawData: nil, capturedAt: Date(), exposure: .init(iso: 100, seconds: 1.0 / 125), lensPosition: 0.5)
    }
    func endFujiCapture(transactionID: UUID) async throws { lock.withLock { restores += 1 } }
    func cancelFujiCapture() {}
}

@MainActor
private final class FujiTestSaver: PhotoSaving {
    let driver: FujiTestDriver
    let failSave: Bool
    private(set) var savedCount = 0
    private(set) var restoredBeforeEverySave = true
    private(set) var lastData: Data?
    init(driver: FujiTestDriver, failSave: Bool = false) { self.driver = driver; self.failSave = failSave }
    func save(image: UIImage, imageData: Data?, recipe: FilmRecipe, capturedAt: Date,
              completion: @escaping @MainActor (Result<Void, PhotoLibrarySaveError>) -> Void) {
        savedCount += 1; lastData = imageData
        restoredBeforeEverySave = restoredBeforeEverySave && driver.counts.restores > 0
        completion(failSave ? .failure(.accessDenied) : .success(()))
    }
}
