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
