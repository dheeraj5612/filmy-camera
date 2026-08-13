import XCTest
@testable import FilmyCamera

@MainActor
final class CameraServiceAvailabilityTests: XCTestCase {
    func testCameraStartsWithAnExplicitIdleAvailability() {
        let camera = CameraService()

        XCTAssertEqual(camera.availability, .idle)
        XCTAssertFalse(camera.isRunning)
        XCTAssertEqual(camera.statusMessage, "Camera is ready")
    }

    func testAvailabilityCasesHaveStablePersistenceValues() {
        let cases: [CameraService.Availability] = [
            .idle,
            .starting,
            .requestingPermission,
            .running,
            .paused,
            .simulator,
            .permissionDenied,
            .interrupted,
            .needsRecovery,
            .unavailable
        ]

        XCTAssertEqual(Set(cases.map(\.rawValue)).count, cases.count)
        XCTAssertEqual(CameraService.Availability.permissionDenied.rawValue, "permissionDenied")
        XCTAssertEqual(CameraService.Availability.needsRecovery.rawValue, "needsRecovery")
    }

    func testStalePreviewOwnerCannotRemoveNewerFrameHandler() {
        let camera = CameraService()
        let olderHandler = camera.installFrameHandler { _ in }
        let newerHandler = camera.installFrameHandler { _ in }

        camera.removeFrameHandler(olderHandler)
        XCTAssertNotNil(camera.onFrame)

        camera.removeFrameHandler(newerHandler)
        XCTAssertNil(camera.onFrame)
    }

    func testFlashDefaultsToSafeOffAndUnsupportedBeforeCameraConfiguration() {
        let camera = CameraService()

        XCTAssertEqual(camera.flashMode, .off)
        XCTAssertEqual(camera.flashAvailability, .unsupported)
        XCTAssertFalse(camera.lowLightBoostSupported)
        XCTAssertFalse(camera.isLowLightBoostEnabled)
        XCTAssertEqual(camera.exposureBias, 0)
    }

    func testExposureBiasClampsNonFiniteAndOutOfRangeValues() {
        XCTAssertEqual(CameraService.clampedExposureBias(.nan), 0)
        XCTAssertEqual(CameraService.clampedExposureBias(.infinity), 0)
        XCTAssertEqual(CameraService.clampedExposureBias(-5), -2)
        XCTAssertEqual(CameraService.clampedExposureBias(5), 2)
        XCTAssertEqual(
            CameraService.clampedExposureBias(5, lowerBound: -1, upperBound: 1),
            1
        )
        XCTAssertEqual(
            CameraService.clampedExposureBias(-5, lowerBound: 1, upperBound: -1),
            -1
        )
    }

    func testExposureBiasQuantizesToSymmetricThirdStops() {
        XCTAssertEqual(CameraService.quantizedExposureBias(0.3), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(CameraService.quantizedExposureBias(-0.3), -1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(CameraService.quantizedExposureBias(2.0 / 3.0 + 1.0 / 3.0), 1, accuracy: 0.0001)
        XCTAssertEqual(CameraService.quantizedExposureBias(.nan), 0)
    }

    func testFlashModesPreserveAVFoundationRawValuesAndCycleOrder() {
        XCTAssertEqual(CameraService.FlashMode.off.rawValue, 0)
        XCTAssertEqual(CameraService.FlashMode.on.rawValue, 1)
        XCTAssertEqual(CameraService.FlashMode.auto.rawValue, 2)
        XCTAssertEqual(
            CameraService.FlashMode.allCases,
            [.off, .auto, .on]
        )
    }

    func testFlashAvailabilitySeparatesUnsupportedAndTemporaryHardwareStates() {
        XCTAssertEqual(
            CameraService.resolveFlashAvailability(
                hasFlash: false,
                supportedModeRawValues: [0, 1, 2],
                flashAvailable: true
            ),
            .unsupported
        )
        XCTAssertEqual(
            CameraService.resolveFlashAvailability(
                hasFlash: true,
                supportedModeRawValues: [0],
                flashAvailable: true
            ),
            .unsupported
        )
        XCTAssertEqual(
            CameraService.resolveFlashAvailability(
                hasFlash: true,
                supportedModeRawValues: [0, 1, 2],
                flashAvailable: false
            ),
            .temporarilyUnavailable
        )
        XCTAssertEqual(
            CameraService.resolveFlashAvailability(
                hasFlash: true,
                supportedModeRawValues: [0, 1, 2],
                flashAvailable: true
            ),
            .available
        )
    }
}
