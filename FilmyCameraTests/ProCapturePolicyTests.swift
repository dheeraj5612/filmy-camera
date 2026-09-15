import CoreGraphics
import Foundation
import XCTest
@testable import FilmyCamera

final class ProCapturePolicyTests: XCTestCase {
    func testOpticalApertureRejectsFixedOrInvalidRangesAndClampsWithoutInventingStops() {
        XCTAssertNil(OpticalAperturePolicy.clamped(2.8, minimum: 1.8, maximum: 1.8))
        XCTAssertNil(OpticalAperturePolicy.clamped(.nan, minimum: 1.48, maximum: 4))
        XCTAssertNil(OpticalAperturePolicy.clamped(2.8, minimum: 0, maximum: 4))
        XCTAssertNil(OpticalAperturePolicy.clamped(2.8, minimum: 1.48, maximum: .infinity))
        XCTAssertEqual(OpticalAperturePolicy.clamped(1, minimum: 1.48, maximum: 4), 1.48)
        XCTAssertEqual(OpticalAperturePolicy.clamped(8, minimum: 1.48, maximum: 4), 4)
        XCTAssertEqual(OpticalAperturePolicy.clamped(2.37, minimum: 1.48, maximum: 4), 2.37)
    }

    private var fullCapabilities: ProCaptureCapabilities {
        var capabilities = ProCaptureCapabilities()
        capabilities.dimensions = [.init(width: 4032, height: 3024), .init(width: 5712, height: 4284), .init(width: 8064, height: 6048)]
        capabilities.supportsHEIF = true
        capabilities.supportsBayerRAW = true
        capabilities.supportsProRAW = true
        capabilities.supportsLivePhoto = true
        capabilities.supportsHDRExport = true
        return capabilities
    }
    func testAllCaptureCombinationsResolveToSafeContracts() {
        for resolution in ProCaptureOptions.Resolution.allCases {
            for codec in ProCaptureOptions.Codec.allCases {
                for raw in ProCaptureOptions.RawFormat.allCases {
                    for live in [false, true] {
                        for hdr in [false, true] {
                            for manual in [false, true] {
                                var options = ProCaptureOptions()
                                options.resolution = resolution; options.codec = codec; options.raw = raw
                                options.livePhoto = live; options.hdr = hdr
                                let result = ProCapturePolicy.resolve(options, capabilities: fullCapabilities, manualExposure: manual)
                                XCTAssertTrue(fullCapabilities.dimensions.contains(result.dimensions!))
                                XCTAssertFalse(result.options.livePhoto && (result.options.raw != .off || manual))
                                XCTAssertFalse(result.options.hdr && result.options.codec != .heif)
                                if manual || result.options.raw == .bayer || result.options.livePhoto {
                                    XCTAssertEqual(result.options.resolution, .mp12)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func testUnsupportedFeaturesHaveExplicitFallbacks() {
        var options = ProCaptureOptions()
        options.raw = .appleProRAW; options.codec = .heif; options.livePhoto = true; options.hdr = true; options.resolution = .mp48
        let result = ProCapturePolicy.resolve(options, capabilities: ProCaptureCapabilities(), manualExposure: false)
        XCTAssertEqual(result.options, ProCaptureOptions())
        XCTAssertNil(result.dimensions)
        XCTAssertGreaterThanOrEqual(result.notices.count, 4)
    }
    func test24MPNeverInventsAnUnsupportedCaptureDimension() {
        var options = ProCaptureOptions(); options.resolution = .mp24
        let result = ProCapturePolicy.resolve(options, capabilities: fullCapabilities, manualExposure: false)
        XCTAssertEqual(result.dimensions, .init(width: 8064, height: 6048))
        XCTAssertTrue(result.notices.contains { $0.contains("downsampled") })
        var twelveOnly = fullCapabilities
        twelveOnly.dimensions = [.init(width: 4032, height: 3024)]
        XCTAssertFalse(twelveOnly.resolutions.contains(.mp24))
        XCTAssertEqual(ProCapturePolicy.resolve(options, capabilities: twelveOnly, manualExposure: false).options.resolution, .mp12)
    }
    func testOutputPolicyNeverUpscalesOrUsesInvalidGeometry() {
        for resolution in ProCaptureOptions.Resolution.allCases {
            XCTAssertEqual(ProCapturePolicy.outputScale(width: 640, height: 480, resolution: resolution), 1)
            XCTAssertEqual(ProCapturePolicy.outputScale(width: .nan, height: 480, resolution: resolution), 1)
        }
        let scale = ProCapturePolicy.outputScale(width: 8064, height: 6048, resolution: .mp24)
        XCTAssertLessThan(scale, 1)
        XCTAssertEqual(8064 * 6048 * scale * scale, 24_000_000, accuracy: 1)
    }
    func testShutterPriorityKeepsShutterAndMetersISOInCorrectDirection() throws {
        let request = try XCTUnwrap(ExposurePriorityPolicy.next(mode: .shutter, fixedValue: 1.0 / 125,
            iso: 100, duration: 1.0 / 125, offset: -1, isoRange: 50...1600, durationRange: 0.000125...1))
        XCTAssertEqual(request.duration, 1.0 / 125, accuracy: 0.0000001)
        XCTAssertGreaterThan(request.iso, 100)
        XCTAssertLessThan(request.iso, 130, "Feedback is damped and step-limited, not a one-stop jump")
        XCTAssertFalse(request.reachedLimit)
    }
    func testISOPriorityKeepsISOAndShortensShutterWhenTooBright() throws {
        let request = try XCTUnwrap(ExposurePriorityPolicy.next(mode: .iso, fixedValue: 200,
            iso: 200, duration: 0.1, offset: 1, isoRange: 50...1600, durationRange: 0.000125...1))
        XCTAssertEqual(request.iso, 200)
        XCTAssertLessThan(request.duration, 0.1)
        XCTAssertGreaterThan(request.duration, 0.07)
    }
    func testPriorityDeadbandLimitsAndNonFiniteValues() throws {
        let deadband = try XCTUnwrap(ExposurePriorityPolicy.next(mode: .shutter, fixedValue: 0.01,
            iso: 200, duration: 0.01, offset: 0.08, isoRange: 50...1600, durationRange: 0.000125...1))
        XCTAssertEqual(deadband.iso, 200)
        let limited = try XCTUnwrap(ExposurePriorityPolicy.next(mode: .shutter, fixedValue: 0.01,
            iso: 1600, duration: 0.01, offset: -3, isoRange: 50...1600, durationRange: 0.000125...1))
        XCTAssertEqual(limited.iso, 1600)
        XCTAssertTrue(limited.reachedLimit)
        XCTAssertNil(ExposurePriorityPolicy.next(mode: .iso, fixedValue: .nan, iso: 100, duration: 0.01,
            offset: 0, isoRange: 50...1600, durationRange: 0.000125...1))
    }
    func testFeedbackConvergesWithoutOscillationInAModeledScene() throws {
        var iso: Float = 100
        for _ in 0..<40 {
            let offset = Float(log2(Double(iso) / 400))
            let request = try XCTUnwrap(ExposurePriorityPolicy.next(mode: .shutter, fixedValue: 0.01,
                iso: iso, duration: 0.01, offset: offset, isoRange: 50...1600, durationRange: 0.000125...1))
            XCTAssertGreaterThanOrEqual(request.iso, iso)
            XCTAssertLessThanOrEqual(request.iso, 400)
            iso = request.iso
        }
        XCTAssertLessThan(abs(log2(Double(iso) / 400)), 0.11)
    }
    func testRAWCallbacksCanArriveInEitherOrderAndIgnoreOtherRequests() {
        var options = ProCaptureOptions(); options.raw = .bayer
        for rawFirst in [false, true] {
            var capture = ProCaptureAccumulator(id: 7, options: options)
            capture.accept(data: Data([9]), isRaw: false, id: 8)
            XCTAssertFalse(capture.isComplete)
            capture.accept(data: Data([1]), isRaw: rawFirst, id: 7)
            XCTAssertFalse(capture.isComplete)
            capture.accept(data: Data([2]), isRaw: !rawFirst, id: 7)
            XCTAssertTrue(capture.isComplete)
        }
    }
    func testCaptureFailureDoesNotReportPartialRAWAsComplete() {
        var options = ProCaptureOptions(); options.raw = .appleProRAW
        var capture = ProCaptureAccumulator(id: 7, options: options)
        capture.accept(data: Data([1]), isRaw: false, id: 7)
        capture.accept(data: nil, isRaw: true, id: 7)
        XCTAssertFalse(capture.isComplete)
    }
    func testLiveCaptureWaitsForMovieAndOwnsTemporaryFileLifetime() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1, 2, 3]).write(to: url)
        var options = ProCaptureOptions(); options.livePhoto = true
        var capture: ProCaptureAccumulator? = ProCaptureAccumulator(id: 4, options: options)
        capture?.accept(data: Data([4]), isRaw: false, id: 4)
        XCTAssertFalse(capture!.isComplete)
        capture?.movie = CaptureMovieResource(url: url)
        XCTAssertTrue(capture!.isComplete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        capture = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testFocusCoordinatesRoundTripAndEdgeSeedsRemainInBounds() {
        let seed = FocusAssistGeometry.seed(at: CGPoint(x: 0.35, y: 0.65))
        let point = FocusAssistGeometry.displayPoint(seed)
        XCTAssertEqual(point.x, 0.35, accuracy: 0.00001)
        XCTAssertEqual(point.y, 0.65, accuracy: 0.00001)
        let rect = FocusAssistGeometry.displayRect(seed, size: CGSize(width: 300, height: 400))
        XCTAssertEqual(rect.midX, 105, accuracy: 0.00001)
        XCTAssertEqual(rect.midY, 260, accuracy: 0.00001)
        for point in [CGPoint.zero, CGPoint(x: 1, y: 1), CGPoint(x: -4, y: 9), CGPoint(x: CGFloat.nan, y: CGFloat.infinity)] {
            let box = FocusAssistGeometry.seed(at: point)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(box))
        }
    }
}
