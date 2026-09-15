import XCTest
import CoreImage
import UIKit
@testable import FilmyCamera

final class FujiShootingTests: XCTestCase {
    func testDefaultsPreserveExistingCameraWorkflow() {
        let settings = FujiShootingSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertFalse(settings.needsRAW)
        XCTAssertFalse(settings.previewIsNatural)
        XCTAssertEqual(settings.cropFactor, 1)
        XCTAssertNil(settings.activeAutoISO)
        XCTAssertEqual(settings.qItems.count, 16)
        XCTAssertEqual(FujiShootingBank.empty.map(\.id), Array(1...7))
    }

    func testAutoISOPrefersLowISOInBrightLight() {
        let result = FujiAutoISOPlanner.resolve(meteredProduct: 0.1, profile: .init(), isoBounds: 50...6400, durationBounds: 0.0001...1)
        XCTAssertEqual(result.iso, 100)
        XCTAssertEqual(result.seconds, 0.001, accuracy: 0.00001)
        XCTAssertFalse(result.isLimited)
    }

    func testAutoISORaisesISOBeforeSlowingShutter() {
        let result = FujiAutoISOPlanner.resolve(meteredProduct: 8, profile: .init(), isoBounds: 50...6400, durationBounds: 0.0001...1)
        XCTAssertEqual(result.iso, 1000, accuracy: 0.1)
        XCTAssertEqual(result.seconds, 1 / 125, accuracy: 0.00001)
        let dark = FujiAutoISOPlanner.resolve(meteredProduct: 64, profile: .init(), isoBounds: 50...6400, durationBounds: 0.0001...1)
        XCTAssertEqual(dark.iso, 3200)
        XCTAssertEqual(dark.seconds, 0.02, accuracy: 0.00001)
    }

    func testAutoISOHonorsSensorBoundsAndReportsUnderexposure() {
        let result = FujiAutoISOPlanner.resolve(meteredProduct: 5000, profile: .init(), isoBounds: 64...800, durationBounds: 0.0001...0.5)
        XCTAssertEqual(result.iso, 800)
        XCTAssertEqual(result.seconds, 0.5)
        XCTAssertTrue(result.isLimited)
    }

    func testValidationBoundsUntrustedSettings() throws {
        var settings = FujiShootingSettings()
        settings.autoISOIndex = 99
        settings.autoISOProfiles = []
        settings.burstCount = Int.max
        settings.focusCount = -4
        settings.focusNear = 0.9
        settings.focusFar = 0.1
        settings.ndSeconds = .infinity
        settings.preShotCount = 99
        settings.qItems = [.raw, .raw, .drive]
        let valid = settings.validated()
        XCTAssertNil(valid.autoISOIndex)
        XCTAssertEqual(valid.autoISOProfiles.count, 3)
        XCTAssertEqual(valid.burstCount, 24)
        XCTAssertEqual(valid.focusCount, 2)
        XCTAssertEqual(valid.focusNear, 0.1)
        XCTAssertEqual(valid.focusFar, 0.9)
        XCTAssertEqual(valid.ndSeconds, 2)
        XCTAssertEqual(valid.preShotCount, 12)
        XCTAssertEqual(valid.qItems, [.raw, .drive])
        XCTAssertNoThrow(try JSONEncoder().encode(valid))
    }

    func testExposureBracketsAreCenteredDistinctAndOrdered() {
        XCTAssertEqual(FujiCapturePlanner.bracketOffsets(count: 7, step: 1), [0, -1, 1, -2, 2, -3, 3])
        var settings = FujiShootingSettings()
        settings.drive = .exposureBracket
        settings.dynamicRange = .dr200
        let steps = FujiCapturePlanner.steps(for: settings)
        XCTAssertEqual(steps.map(\.exposureEV), [0, -1, 1])
        XCTAssertTrue(steps.allSatisfy { $0.dynamicRange == .dr200 })
    }

    func testISOBracketsDoNotAlterRequestedDuration() {
        var settings = FujiShootingSettings()
        settings.drive = .isoBracket
        let steps = FujiCapturePlanner.steps(for: settings)
        XCTAssertEqual(steps.map(\.isoEV), [0, -1, 1])
        XCTAssertTrue(steps.allSatisfy { $0.exposureEV == 0 })
    }

    func testDRAndFocusPlans() {
        var settings = FujiShootingSettings()
        settings.drive = .dynamicRangeBracket
        XCTAssertTrue(settings.needsRAW)
        XCTAssertEqual(FujiCapturePlanner.steps(for: settings).map(\.dynamicRange), [.dr100, .dr200, .dr400])
        XCTAssertEqual(FujiDynamicRange.dr400.gain, 4)
        settings.drive = .focusBracket
        settings.focusCount = 3
        settings.focusNear = 0.2
        settings.focusFar = 0.8
        let steps = FujiCapturePlanner.steps(for: settings)
        XCTAssertEqual(steps.compactMap(\.lensPosition), [0.2, 0.5, 0.8])
    }

    func testFilmAndWBBracketsUseOneCapture() {
        var settings = FujiShootingSettings()
        for drive in [FujiDriveMode.filmBracket, .whiteBalanceBracket] {
            settings.drive = drive
            XCTAssertEqual(FujiCapturePlanner.steps(for: settings).count, 1)
        }
    }

    func testIntervalAndBurstAreBoundedAndSequential() {
        var settings = FujiShootingSettings()
        settings.drive = .interval
        settings.burstCount = 999
        settings.intervalSeconds = 4
        let steps = FujiCapturePlanner.steps(for: settings)
        XCTAssertEqual(steps.count, 24)
        XCTAssertEqual(steps.first?.delayBefore, 0)
        XCTAssertTrue(steps.dropFirst().allSatisfy { $0.delayBefore == 4 })
        settings.drive = .continuousLow
        XCTAssertEqual(FujiCapturePlanner.steps(for: settings)[1].delayBefore, 0.25)
        settings.drive = .continuousHigh
        XCTAssertEqual(FujiCapturePlanner.steps(for: settings)[1].delayBefore, 0)
    }

    func testPreShotDropsOldFramesAndNeverExceedsCapacity() {
        var buffer = FujiTimedBuffer<Int>(capacity: 3, maximumAge: 2)
        for index in 0..<100 { buffer.append(index, at: Double(index) * 0.1) }
        XCTAssertEqual(buffer.entries.count, 3)
        XCTAssertEqual(buffer.take(at: 10), [97, 98, 99])
        XCTAssertTrue(buffer.entries.isEmpty)
        buffer.append(1, at: 10)
        XCTAssertTrue(buffer.take(at: 13).isEmpty)
    }

    func testPreShotClearsOnClockRegressionAndInvalidInput() {
        var buffer = FujiTimedBuffer<Int>(capacity: 3, maximumAge: 2)
        buffer.append(1, at: 20)
        buffer.append(2, at: 1)
        XCTAssertEqual(buffer.take(at: 1), [2])
        buffer.append(3, at: .nan)
        XCTAssertTrue(buffer.entries.isEmpty)
    }

    func testDigitalPrimeCropsWithoutUpsampling() {
        let source = CIImage(color: .white).cropped(to: CGRect(x: 100, y: 200, width: 4000, height: 3000))
        let crop = FujiDevelopmentPipeline.centerCrop(source, factor: 2)
        XCTAssertEqual(crop.extent, CGRect(x: 0, y: 0, width: 2000, height: 1500))
        XCTAssertEqual(FujiPrimeMode.crop20.retainedPixelFraction, 0.25)
        XCTAssertEqual(FujiDevelopmentPipeline.centerCrop(source, factor: 2, aspectRatio: 1).extent.size,
                       CGSize(width: 1500, height: 1500))
    }

    func testLinearDRShoulderPreservesWhiteAndLiftsUnderexposedShadows() throws {
        XCTAssertTrue(FujiLinearDRFilter.isAvailable)
        let filter = FujiLinearDRFilter()
        filter.gain = 4
        let color = try XCTUnwrap(CIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1, colorSpace: FujiDevelopmentPipeline.linearColorSpace))
        filter.inputImage = CIImage(color: color)
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let output = try XCTUnwrap(filter.outputImage)
        let sample = linearPixel(output)
        XCTAssertEqual(sample[0], Float(0.2 / 1.15), accuracy: 0.01)
        filter.inputImage = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(linearPixel(try XCTUnwrap(filter.outputImage))[0], 1, accuracy: 0.01)
    }

    func testTemporalAverageOperatesInLinearLight() throws {
        let bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
        let black = CIImage(color: .black).cropped(to: bounds)
        let white = CIImage(color: .white).cropped(to: bounds)
        let average = try FujiDevelopmentPipeline.blend(black, white, count: 1, mode: .average)
        XCTAssertEqual(linearPixel(average)[0], 0.5, accuracy: 0.01)
        let brighter = try FujiDevelopmentPipeline.blend(black, white, count: 1, mode: .bright)
        XCTAssertEqual(linearPixel(brighter)[0], 1, accuracy: 0.01)
        let darker = try FujiDevelopmentPipeline.blend(black, white, count: 1, mode: .dark)
        XCTAssertEqual(linearPixel(darker)[0], 0, accuracy: 0.01)
    }

    func testProcessedPhotoCannotPretendToBeDR400RAW() {
        let frame = FujiSourceFrame(data: Data([1]), metadata: .init(capturedAt: Date(), sourceKind: .processedStill,
                                   deviceID: "test", dynamicRange: .dr400))
        XCTAssertThrowsError(try FujiDevelopmentPipeline.decode(frame)) { error in
            XCTAssertEqual(error as? FujiCaptureError, .rawUnavailable)
        }
    }

    func testOriginalIsImmutableAcrossDevelopmentEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FujiDevelopmentLibrary(root: root)
        let bytes = Data([1, 2, 3, 4])
        let frame = FujiSourceFrame(data: bytes, metadata: .init(capturedAt: Date(), sourceKind: .bayerRAW, deviceID: "test"))
        var record = try await library.store(frame, recipe: FilmRecipe.builtIns[0], groupID: UUID(), crop: 1, aspect: nil)
        record.adjustments.exposureEV = 2
        try await library.update(record)
        let reloaded = try await library.frame(for: record)
        XCTAssertEqual(reloaded.data, bytes)
        let records = try await library.list()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].adjustments.exposureEV, 2)
        try await library.delete(record)
        let empty = try await library.list()
        XCTAssertTrue(empty.isEmpty)
    }

    func testArchiveQuotaFailsWithoutDeletingOlderOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FujiDevelopmentLibrary(root: root, maximumBytes: 3)
        let frame = FujiSourceFrame(data: Data([1, 2, 3, 4]), metadata: .init(capturedAt: Date(), sourceKind: .processedStill, deviceID: "test"))
        do {
            _ = try await library.store(frame, recipe: FilmRecipe.builtIns[0], groupID: UUID(), crop: 1, aspect: nil)
            XCTFail("A full archive must not silently discard originals.")
        } catch { XCTAssertNotNil(error as? FujiCaptureError) }
    }

    @MainActor func testSettingsAndQMenuPersistAcrossInstances() {
        let name = "fuji-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = FujiShootingController(defaults: defaults)
        first.settings.enabled = true
        first.settings.drive = .focusStack
        first.settings.qItems = [.raw, .banks]
        let second = FujiShootingController(defaults: defaults)
        XCTAssertTrue(second.settings.enabled)
        XCTAssertEqual(second.settings.drive, .focusStack)
        XCTAssertEqual(second.settings.qItems, [.raw, .banks])
        XCTAssertEqual(second.banks.count, 7)
    }

    @MainActor func testUnreadablePreferencesAreBackedUp() {
        let name = "fuji-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let bytes = Data("not valid JSON".utf8)
        defaults.set(bytes, forKey: "fuji.shooting.v1")
        let controller = FujiShootingController(defaults: defaults)
        XCTAssertFalse(controller.settings.enabled)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(defaults.data(forKey: "fuji.shooting.v1.unreadable-backup"), bytes)
    }

    private func linearPixel(_ image: CIImage) -> [Float] {
        var pixel = [Float](repeating: 0, count: 4)
        FujiDevelopmentPipeline.linearContext.render(image, toBitmap: &pixel, rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: FujiDevelopmentPipeline.linearColorSpace)
        return pixel
    }
}
