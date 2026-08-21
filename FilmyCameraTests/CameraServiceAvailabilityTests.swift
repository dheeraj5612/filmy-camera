import XCTest
@preconcurrency import AVFoundation
@testable import FilmyCamera

@MainActor
final class CameraServiceAvailabilityTests: XCTestCase {
    func testCameraStartsWithAnExplicitIdleAvailability() {
        let camera = CameraService()

        XCTAssertEqual(camera.availability, .idle)
        XCTAssertFalse(camera.isRunning)
        XCTAssertEqual(camera.statusMessage, "Camera is ready")
    }

    func testVideoRotationUsesTheFullInterfaceOrientation() {
        let portraitSize = CGSize(width: 390, height: 844)

        XCTAssertEqual(CameraService.videoRotationAngle(for: .portrait, fallbackViewSize: portraitSize), 90)
        XCTAssertEqual(CameraService.videoRotationAngle(for: .portraitUpsideDown, fallbackViewSize: portraitSize), 270)
        XCTAssertEqual(CameraService.videoRotationAngle(for: .landscapeLeft, fallbackViewSize: portraitSize), 0)
        XCTAssertEqual(CameraService.videoRotationAngle(for: .landscapeRight, fallbackViewSize: portraitSize), 180)
        XCTAssertEqual(CameraService.videoRotationAngle(for: nil, fallbackViewSize: portraitSize), 90)
        XCTAssertEqual(
            CameraService.videoRotationAngle(
                for: .unknown,
                fallbackViewSize: CGSize(width: 844, height: 390)
            ),
            0
        )
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

    func testStoppingPreservesDeniedAuthorizationBeforeHardwareFallback() {
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .denied,
                hasCameraDevice: false,
                previousAvailability: .starting
            ),
            .permissionDenied
        )
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .restricted,
                hasCameraDevice: false,
                previousAvailability: .paused
            ),
            .permissionDenied
        )
    }

    func testStoppingPreservesUnavailableRecoveryStateForAuthorizedCamera() {
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .authorized,
                hasCameraDevice: true,
                previousAvailability: .unavailable
            ),
            .unavailable
        )
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .authorized,
                hasCameraDevice: true,
                previousAvailability: .needsRecovery
            ),
            .needsRecovery
        )
    }

    func testStoppingUsesLifecycleStateForAvailableCameraAndSimulator() {
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .authorized,
                hasCameraDevice: true,
                previousAvailability: .running
            ),
            .paused
        )
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .authorized,
                hasCameraDevice: false,
                previousAvailability: .running
            ),
            .simulator
        )
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .notDetermined,
                hasCameraDevice: true,
                previousAvailability: .starting
            ),
            .idle
        )
    }

    func testNotDeterminedAuthorizationWithoutHardwareResolvesToSimulatorState() {
        XCTAssertEqual(
            CameraService.availabilityAfterStopping(
                authorizationStatus: .notDetermined,
                hasCameraDevice: false,
                previousAvailability: .starting
            ),
            .simulator
        )
    }

    func testPhotoCallbackMustMatchPendingCaptureIdentity() {
        XCTAssertTrue(
            CameraService.acceptsPhotoCallback(
                pendingUniqueID: 12,
                callbackUniqueID: 12
            )
        )
        XCTAssertFalse(
            CameraService.acceptsPhotoCallback(
                pendingUniqueID: 12,
                callbackUniqueID: 13
            )
        )
        XCTAssertFalse(
            CameraService.acceptsPhotoCallback(
                pendingUniqueID: nil,
                callbackUniqueID: 12
            )
        )
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

    func testCameraHardwareSelectionDefaultsToSafePreviewState() {
        let camera = CameraService()

        XCTAssertEqual(camera.cameraPosition, .back)
        XCTAssertEqual(camera.availableCameraPositions, [])
        XCTAssertEqual(camera.availableLenses, [])
        XCTAssertNil(camera.selectedLensID)
        XCTAssertEqual(camera.minZoomFactor, 1)
        XCTAssertEqual(camera.maxZoomFactor, 1)
    }

    func testCameraHardwareMetadataIsStableAndHashable() {
        let wide = CameraService.LensOption(
            id: "wide",
            title: "1×",
            detail: "Wide",
            zoomFactor: 1,
            position: .back
        )
        let sameWide = CameraService.LensOption(
            id: "wide",
            title: "1×",
            detail: "Wide",
            zoomFactor: 1,
            position: .back
        )

        XCTAssertEqual(CameraService.CameraPosition.allCases, [.back, .front])
        XCTAssertEqual(wide, sameWide)
        XCTAssertEqual(Set([wide]).count, 1)
        XCTAssertEqual(CameraService.CameraPosition.front.title, "Front")
    }

    func testPreviewPixelFormatPrefersNativeBiPlanarVideoBuffers() {
        XCTAssertEqual(
            CameraService.preferredPreviewPixelFormat(
                available: [
                    kCVPixelFormatType_32BGRA,
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ]
            ),
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        )
        XCTAssertEqual(
            CameraService.preferredPreviewPixelFormat(
                available: [
                    kCVPixelFormatType_32BGRA,
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
            ),
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        )
    }

    func testPreviewPixelFormatFallsBackToBGRAWhenYUVIsUnavailable() {
        XCTAssertEqual(
            CameraService.preferredPreviewPixelFormat(available: [kCVPixelFormatType_32BGRA]),
            kCVPixelFormatType_32BGRA
        )
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

    func testVirtualLensSelectionUsesSwitchOverThresholdsAndActiveHardware() {
        XCTAssertEqual(
            CameraService.selectedVirtualLensIndex(
                zoomFactor: 1.6,
                switchOverZoomFactors: [2, 4],
                constituentCount: 3
            ),
            0
        )
        XCTAssertEqual(
            CameraService.selectedVirtualLensIndex(
                zoomFactor: 2,
                switchOverZoomFactors: [2, 4],
                constituentCount: 3
            ),
            1
        )
        XCTAssertEqual(
            CameraService.selectedVirtualLensIndex(
                zoomFactor: 1,
                switchOverZoomFactors: [2, 4],
                constituentCount: 3,
                activeConstituentIndex: 2
            ),
            2
        )
    }

    func testSavedLensOriginOnlyRestoresStandaloneInputs() {
        XCTAssertTrue(
            CameraService.shouldRestoreStandaloneLens(origin: .standalone)
        )
        XCTAssertFalse(
            CameraService.shouldRestoreStandaloneLens(origin: .virtual)
        )
        XCTAssertFalse(
            CameraService.shouldRestoreStandaloneLens(origin: nil)
        )
    }

    func testVirtualZoomNormalizationAnchorsWideConstituentAtOneTimes() {
        XCTAssertEqual(
            CameraService.normalizedUserZoomFactor(
                hardwareZoomFactor: 2,
                wideReferenceHardwareZoomFactor: 2
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CameraService.normalizedUserZoomFactor(
                hardwareZoomFactor: 4,
                wideReferenceHardwareZoomFactor: 2
            ),
            2,
            accuracy: 0.0001
        )

        let telephotoTitleMagnification = CameraService.normalizedUserZoomFactor(
            hardwareZoomFactor: 4,
            wideReferenceHardwareZoomFactor: 2
        )
        XCTAssertEqual(telephotoTitleMagnification, 2.0, accuracy: 0.0001)

        XCTAssertEqual(
            CameraService.normalizedUserZoomFactor(
                hardwareZoomFactor: .nan,
                wideReferenceHardwareZoomFactor: 2
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CameraService.normalizedUserZoomFactor(
                hardwareZoomFactor: 2,
                wideReferenceHardwareZoomFactor: 0
            ),
            2,
            accuracy: 0.0001
        )
    }

    func testStandaloneLensMagnificationUsesFieldOfViewRelationships() {
        let magnification = CameraService.standaloneLensMagnification(
            wideFieldOfView: 70,
            lensFieldOfView: 35
        )

        XCTAssertNotNil(magnification)
        XCTAssertGreaterThan(magnification ?? 0, 1.5)
        XCTAssertLessThan(magnification ?? .infinity, 3)
        XCTAssertNil(
            CameraService.standaloneLensMagnification(
                wideFieldOfView: 0,
                lensFieldOfView: 35
            )
        )
    }

    func testStandaloneZoomConversionsPreserveOpticalScale() {
        XCTAssertEqual(
            CameraService.standaloneUserFacingZoomFactor(
                hardwareZoomFactor: 1,
                opticalMagnification: 2
            ),
            2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CameraService.standaloneHardwareZoomFactor(
                userFacingZoomFactor: 3,
                opticalMagnification: 2
            ),
            1.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CameraService.standaloneUserFacingZoomFactor(
                hardwareZoomFactor: 1,
                opticalMagnification: 0.5
            ),
            0.5,
            accuracy: 0.0001
        )
    }

    func testStandaloneLensReselectionResetsToItsAdvertisedOpticalMagnification() {
        let advertisedMagnification: CGFloat = 2
        let hardwareZoom = CameraService.standaloneHardwareZoomFactor(
            userFacingZoomFactor: advertisedMagnification,
            opticalMagnification: advertisedMagnification
        )

        XCTAssertEqual(hardwareZoom, 1, accuracy: 0.0001)
        XCTAssertEqual(
            CameraService.standaloneUserFacingZoomFactor(
                hardwareZoomFactor: hardwareZoom,
                opticalMagnification: advertisedMagnification
            ),
            advertisedMagnification,
            accuracy: 0.0001
        )
    }


    func testCameraActivityPolicyStartsOnlyForVisibleCameraWithoutReview() {
        XCTAssertEqual(
            CameraActivityPolicy.action(
                hasReview: false,
                sceneIsActive: true,
                isCameraTabActive: true,
                availability: .paused
            ),
            .start
        )
        XCTAssertEqual(
            CameraActivityPolicy.action(
                hasReview: true,
                sceneIsActive: true,
                isCameraTabActive: true,
                availability: .running
            ),
            .stop
        )
        XCTAssertEqual(
            CameraActivityPolicy.action(
                hasReview: false,
                sceneIsActive: false,
                isCameraTabActive: true,
                availability: .running
            ),
            .stop
        )
        XCTAssertEqual(
            CameraActivityPolicy.action(
                hasReview: false,
                sceneIsActive: true,
                isCameraTabActive: false,
                availability: .running
            ),
            .stop
        )
    }

    func testCameraActivityPolicyHoldsAnActiveInterruptedSessionForObserverRecovery() {
        XCTAssertEqual(
            CameraActivityPolicy.action(
                hasReview: false,
                sceneIsActive: true,
                isCameraTabActive: true,
                availability: .interrupted
            ),
            .hold
        )
    }

    func testCaptureDevicePointUndoesCardinalPreviewRotations() {
        let previewPoint = CGPoint(x: 0.2, y: 0.3)
        let zero = CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: previewPoint,
            rotationAngle: 0,
            mirrored: false
        )
        let ninety = CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: previewPoint,
            rotationAngle: 90,
            mirrored: false
        )
        let oneEighty = CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: previewPoint,
            rotationAngle: 180,
            mirrored: false
        )
        let twoSeventy = CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: previewPoint,
            rotationAngle: 270,
            mirrored: false
        )

        XCTAssertEqual(zero.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(zero.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(ninety.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(ninety.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(oneEighty.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(oneEighty.y, 0.7, accuracy: 0.0001)
        XCTAssertEqual(twoSeventy.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(twoSeventy.y, 0.2, accuracy: 0.0001)
    }

    func testCaptureDevicePointUndoesPreviewMirroringBeforeRotation() {
        let point = CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: CGPoint(x: 0.2, y: 0.3),
            rotationAngle: 90,
            mirrored: true
        )

        XCTAssertEqual(point.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.2, accuracy: 0.0001)
    }

    func testCaptureDevicePointNormalizesAnglesAndInvalidCoordinates() {
        let negativeAngle = CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: CGPoint(x: 0.2, y: 0.3),
            rotationAngle: -90,
            mirrored: false
        )
        let invalidPoint = CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
            rotationAngle: CGFloat.nan,
            mirrored: false
        )

        XCTAssertEqual(negativeAngle.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(negativeAngle.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(invalidPoint, CGPoint(x: 0.5, y: 0.5))
    }

    func testFocusLockPrefersOneShotAutofocusBeforeFreezingLensState() {
        XCTAssertEqual(
            CameraService.preferredFocusLockMode(
                supportsAutoFocus: true,
                supportsLocked: true
            ),
            .autoFocus
        )
        XCTAssertEqual(
            CameraService.preferredFocusLockMode(
                supportsAutoFocus: true,
                supportsLocked: false
            ),
            .autoFocus
        )
    }

    func testFocusLockFallsBackToLockedAndFailsClosedWithoutSupport() {
        XCTAssertEqual(
            CameraService.preferredFocusLockMode(
                supportsAutoFocus: false,
                supportsLocked: true
            ),
            .locked
        )
        XCTAssertNil(
            CameraService.preferredFocusLockMode(
                supportsAutoFocus: false,
                supportsLocked: false
            )
        )
    }

    func testExposureLockPrefersOneShotAutoExposureBeforeFreezingState() {
        XCTAssertEqual(
            CameraService.preferredExposureLockMode(
                supportsAutoExpose: true,
                supportsLocked: true
            ),
            .autoExpose
        )
        XCTAssertEqual(
            CameraService.preferredExposureLockMode(
                supportsAutoExpose: true,
                supportsLocked: false
            ),
            .autoExpose
        )
    }

    func testExposureLockFallsBackToLockedAndFailsClosedWithoutSupport() {
        XCTAssertEqual(
            CameraService.preferredExposureLockMode(
                supportsAutoExpose: false,
                supportsLocked: true
            ),
            .locked
        )
        XCTAssertNil(
            CameraService.preferredExposureLockMode(
                supportsAutoExpose: false,
                supportsLocked: false
            )
        )
    }

}
