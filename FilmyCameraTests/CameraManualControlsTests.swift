import AVFoundation
import XCTest
@testable import FilmyCamera

final class CameraManualControlsTests: XCTestCase {
    func testExposureRequestClampsBothSensorValuesAndUsesLiveFallbacks() {
        let bounded = CameraManualControls.sanitizedExposureRequest(
            iso: 10_000,
            durationSeconds: 2,
            currentISO: 320,
            currentDurationSeconds: 1.0 / 120.0,
            isoRange: 50...1_600,
            durationRange: (1.0 / 8_000.0)...0.5
        )
        XCTAssertEqual(bounded.iso, 1_600)
        XCTAssertEqual(bounded.durationSeconds, 0.5, accuracy: 0.000_001)

        let liveFallback = CameraManualControls.sanitizedExposureRequest(
            iso: .nan,
            durationSeconds: .infinity,
            currentISO: 320,
            currentDurationSeconds: 1.0 / 120.0,
            isoRange: 50...1_600,
            durationRange: (1.0 / 8_000.0)...0.5
        )
        XCTAssertEqual(liveFallback.iso, 320)
        XCTAssertEqual(liveFallback.durationSeconds, 1.0 / 120.0, accuracy: 0.000_001)

        let fullyInvalid = CameraManualControls.sanitizedExposureRequest(
            iso: .nan,
            durationSeconds: .nan,
            currentISO: .infinity,
            currentDurationSeconds: -.infinity,
            isoRange: 50...1_600,
            durationRange: (1.0 / 8_000.0)...0.5
        )
        XCTAssertEqual(fullyInvalid.iso, 50)
        XCTAssertEqual(fullyInvalid.durationSeconds, 1.0 / 8_000.0, accuracy: 0.000_000_1)
    }

    func testWhiteBalanceAndFocusInputsNeverEscapeAdvertisedRanges() {
        let whiteBalance = CameraManualControls.sanitizedWhiteBalanceRequest(
            kelvin: 40_000,
            tint: -900,
            currentKelvin: 5_600,
            currentTint: 8
        )
        XCTAssertEqual(whiteBalance.kelvin, 10_000)
        XCTAssertEqual(whiteBalance.tint, -150)

        let invalidWhiteBalance = CameraManualControls.sanitizedWhiteBalanceRequest(
            kelvin: .nan,
            tint: .infinity,
            currentKelvin: .nan,
            currentTint: -.infinity
        )
        XCTAssertEqual(invalidWhiteBalance.kelvin, 2_500)
        XCTAssertEqual(invalidWhiteBalance.tint, -150)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(-4, current: 0.7), 0)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(4, current: 0.7), 1)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(.nan, current: 0.7), 0.7)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(.nan, current: .nan), 0)
    }

    func testUnsupportedHardwareCannotPublishAnEnabledManualMode() {
        XCTAssertEqual(
            CameraManualControls.resolvedMode(requested: .manual, supported: false),
            .auto
        )
        XCTAssertEqual(
            CameraManualControls.resolvedMode(requested: .manual, supported: true),
            .manual
        )
        XCTAssertEqual(
            CameraManualControls.resolvedMode(requested: .auto, supported: true),
            .auto
        )
        XCTAssertEqual(CameraManualControls.unavailable.exposureMode, .auto)
        XCTAssertFalse(CameraManualControls.unavailable.manualExposureSupported)
        XCTAssertFalse(CameraManualControls.unavailable.isApplying)
        XCTAssertFalse(CameraManualControls.unavailable.flashRequiresAutoExposure)
    }

    func testWhiteBalanceGainsAreFiniteAndWithinDeviceBounds() {
        let gains = CameraService.clampedWhiteBalanceGains(
            AVCaptureDevice.WhiteBalanceGains(
                redGain: .nan,
                greenGain: 0.2,
                blueGain: 99
            ),
            maximumGain: 8
        )
        XCTAssertEqual(gains.redGain, 1)
        XCTAssertEqual(gains.greenGain, 1)
        XCTAssertEqual(gains.blueGain, 8)

        let invalidMaximum = CameraService.clampedWhiteBalanceGains(
            AVCaptureDevice.WhiteBalanceGains(redGain: 2, greenGain: 3, blueGain: 4),
            maximumGain: .nan
        )
        XCTAssertEqual(invalidMaximum.redGain, 1)
        XCTAssertEqual(invalidMaximum.greenGain, 1)
        XCTAssertEqual(invalidMaximum.blueGain, 1)
    }

    func testManualFrameDurationKeepsExactThirtyFPSAndAccommodatesLongShutter() {
        let fastShutter = CameraService.manualFrameDuration(
            for: CMTime(value: 1, timescale: 8_000)
        )
        XCTAssertEqual(CMTimeCompare(fastShutter, CMTime(value: 1, timescale: 30)), 0)

        let longShutter = CameraService.manualFrameDuration(
            for: CMTime(value: 1, timescale: 4)
        )
        XCTAssertEqual(CMTimeCompare(longShutter, CMTime(value: 1, timescale: 4)), 0)

        let invalid = CameraService.manualFrameDuration(for: .invalid)
        XCTAssertEqual(CMTimeCompare(invalid, CMTime(value: 1, timescale: 30)), 0)
    }

    func testExposureDurationConversionCannotRoundOutsideHardwareRationals() throws {
        let minimum = CMTime(value: 1, timescale: 2_000_000_001)
        let maximum = CMTime(value: 1, timescale: 2)
        let clampedMinimum = try XCTUnwrap(
            CameraService.clampedManualExposureDuration(
                requestedSeconds: CMTimeGetSeconds(minimum),
                fallback: CMTime(value: 1, timescale: 60),
                minimum: minimum,
                maximum: maximum
            )
        )
        XCTAssertGreaterThanOrEqual(CMTimeCompare(clampedMinimum, minimum), 0)

        let clampedMaximum = try XCTUnwrap(
            CameraService.clampedManualExposureDuration(
                requestedSeconds: 5,
                fallback: CMTime(value: 1, timescale: 60),
                minimum: minimum,
                maximum: maximum
            )
        )
        XCTAssertEqual(CMTimeCompare(clampedMaximum, maximum), 0)

        XCTAssertNil(
            CameraService.clampedManualExposureDuration(
                requestedSeconds: 0.01,
                fallback: .invalid,
                minimum: maximum,
                maximum: minimum
            )
        )
    }

    func testManualExposureUsesCapturePriorityThatHonorsSensorSettings() {
        XCTAssertEqual(
            CameraService.photoQualityPrioritization(manualExposureEnabled: true),
            .speed
        )
        XCTAssertEqual(
            CameraService.photoQualityPrioritization(manualExposureEnabled: false),
            .quality
        )
    }

    func testLensOptionAdvertisesOnlyRealSupportedControls() {
        let exposureOnly = CameraManualControls.PhysicalLensOption(
            id: "wide",
            title: "1×",
            detail: "Wide",
            supportsManualExposure: true,
            supportsManualWhiteBalance: false,
            supportsManualFocus: false,
            isActive: false
        )
        let unsupported = CameraManualControls.PhysicalLensOption(
            id: "virtual",
            title: "Smart",
            detail: "Smart camera",
            supportsManualExposure: false,
            supportsManualWhiteBalance: false,
            supportsManualFocus: false,
            isActive: true
        )
        XCTAssertTrue(exposureOnly.supportsAnyManualControl)
        XCTAssertFalse(unsupported.supportsAnyManualControl)
    }
}


final class CaptureWorkflowPolicyTests: XCTestCase {
    func testCountdownRejectsDuplicateAndUnsupportedStarts() throws {
        var state = CaptureTimerState()
        for seconds in [-1, 0, 1, 4, 30] { XCTAssertNil(state.begin(seconds: seconds)) }
        _ = try XCTUnwrap(state.begin(seconds: 3))
        XCTAssertNil(state.begin(seconds: 5)); XCTAssertEqual(state.remaining, 3)
    }
    func testTimerCannotFireBeforeDeadlineOrMoreThanOnce() throws {
        var state = CaptureTimerState()
        let id = try XCTUnwrap(state.begin(seconds: 3))
        XCTAssertFalse(state.consume(id))
        XCTAssertFalse(state.tick(id)); XCTAssertFalse(state.tick(id)); XCTAssertTrue(state.tick(id))
        XCTAssertTrue(state.consume(id)); XCTAssertFalse(state.consume(id)); XCTAssertFalse(state.isActive)
    }
    func testCancelledCountdownCannotConsumeANewerCountdown() throws {
        var state = CaptureTimerState()
        let stale = try XCTUnwrap(state.begin(seconds: 3)); state.cancel()
        let current = try XCTUnwrap(state.begin(seconds: 5))
        XCTAssertFalse(state.tick(stale)); XCTAssertFalse(state.consume(stale))
        XCTAssertEqual(state.operationID, current); XCTAssertEqual(state.remaining, 5)
    }
    func testAllSupportedDurationsCountDownExactly() throws {
        for duration in [3, 5, 10] {
            var state = CaptureTimerState()
            let id = try XCTUnwrap(state.begin(seconds: duration))
            for tick in 1...duration { XCTAssertEqual(state.tick(id), tick == duration) }
            XCTAssertTrue(state.consume(id)); XCTAssertFalse(state.tick(id))
        }
    }
    func testPreviewHistogramCountsBlackWhiteAndSingleChannelClipping() throws {
        let rgba: [UInt8] = [0,0,0,255, 255,255,255,255, 255,0,0,255, 128,128,128,255]
        let result = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: rgba, width: 4, height: 1, zebras: false, peaking: false))
        XCTAssertEqual(result.histogram.reduce(0,+), 4)
        XCTAssertEqual(result.histogram[0], 1); XCTAssertEqual(result.histogram[63], 1)
        XCTAssertEqual(result.clippedPixels, 2)
        XCTAssertTrue(result.overlayRGBA.allSatisfy { $0 == 0 })
    }
    func testPreviewAnalysisRejectsInvalidAndUnboundedInputs() {
        for size in [(-1,1),(0,1),(1,0),(193,1),(1,193),(Int.max,Int.max)] {
            XCTAssertNil(PreviewAnalysisMath.analyze(rgba: [], width: size.0, height: size.1, zebras: true, peaking: true))
        }
        XCTAssertNil(PreviewAnalysisMath.analyze(rgba: [1], width: 1, height: 1, zebras: true, peaking: true))
    }
    func testFlatFieldHasNoFocusPeakingAndOpaqueChannelsStayPremultiplied() throws {
        var gray = [UInt8](repeating: 128, count: 8 * 8 * 4)
        for offset in stride(from: 3, to: gray.count, by: 4) { gray[offset] = 255 }
        let result = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: gray, width: 8, height: 8, zebras: false, peaking: true))
        XCTAssertTrue(result.overlayRGBA.allSatisfy { $0 == 0 })
        let white = [UInt8](repeating: 255, count: 8 * 8 * 4)
        let zebras = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: white, width: 8, height: 8, zebras: true, peaking: false))
        XCTAssertEqual(zebras.clippedPixels, 64)
        XCTAssertTrue(zebras.overlayRGBA.contains { $0 > 0 })
        for p in stride(from: 0, to: zebras.overlayRGBA.count, by: 4) {
            for c in 0...2 { XCTAssertLessThanOrEqual(zebras.overlayRGBA[p+c], zebras.overlayRGBA[p+3]) }
        }
    }
    func testPeakingFindsContrastEdgesButNotTheBorder() throws {
        var rgba = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<8 {
                let offset = (y*8+x)*4
                for c in 0...2 { rgba[offset+c] = x < 4 ? 60 : 190 }
            }
        }
        let result = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: rgba, width: 8, height: 8, zebras: false, peaking: true))
        XCTAssertTrue(result.overlayRGBA.contains { $0 > 0 })
        for x in 0..<8 { XCTAssertEqual(result.overlayRGBA[x*4+3], 0) }
    }
    func testLevelHandlesEveryOrientationAndRejectsFlatOrNonfiniteGravity() throws {
        for vector in [(0.0,-1.0),(1.0,0.0),(0.0,1.0),(-1.0,0.0)] {
            XCTAssertEqual(try XCTUnwrap(PreviewAnalysisMath.horizonDegrees(x: vector.0, y: vector.1)), 0, accuracy: 0.0001)
        }
        XCTAssertEqual(try XCTUnwrap(PreviewAnalysisMath.horizonDegrees(x: sin(.pi/18), y: -cos(.pi/18))), 10, accuracy: 0.0001)
        XCTAssertNil(PreviewAnalysisMath.horizonDegrees(x: 0, y: 0))
        XCTAssertNil(PreviewAnalysisMath.horizonDegrees(x: .nan, y: -1))
        XCTAssertNil(PreviewAnalysisMath.horizonDegrees(x: .infinity, y: 0))
    }
    func testExactAspectFramesFitPortraitLandscapeAndTinyWindows() {
        for size in [CGSize(width: 390,height: 500), CGSize(width: 700,height: 250), CGSize(width: 800,height: 1100)] {
            for aspect in CaptureAspect.allCases where aspect != .viewfinder {
                for landscape in [true, false] {
                    let result = ViewfinderLayout.size(available: size, isLandscape: landscape, aspect: aspect)
                    XCTAssertLessThanOrEqual(result.width, size.width + 0.001)
                    XCTAssertLessThanOrEqual(result.height, size.height + 0.001)
                    XCTAssertEqual(result.width/result.height, CGFloat(aspect.ratio(isLandscape: landscape)!), accuracy: 0.0001)
                }
            }
        }
    }
    func testInvalidViewfinderSizeCannotPublishNaN() {
        XCTAssertEqual(ViewfinderLayout.size(available: CGSize(width: CGFloat.nan,height: 2), isLandscape: false), .zero)
        XCTAssertEqual(ViewfinderLayout.size(available: .zero, isLandscape: true, aspect: .square), .zero)
    }
}
