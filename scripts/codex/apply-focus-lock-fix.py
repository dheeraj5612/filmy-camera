from pathlib import Path


def replace_once(relative_path: str, old: str, new: str) -> None:
    path = Path(relative_path)
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{relative_path}: expected one replacement target, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "FilmyCamera/Services/CameraService.swift",
    '''                let canLockFocus = device.isFocusModeSupported(.locked)
                let canLockExposure = device.isExposureModeSupported(.locked)
                guard canLockFocus || canLockExposure else {
                    self.publishStatus("Focus lock is unavailable right now.")
                    return
                }

                if canLockFocus {
                    device.focusMode = .locked
                }
                if canLockExposure {
                    device.exposureMode = .locked
                }
                self.focusExposureLocked = true
                self.publishFocusExposureLocked(true)
                self.publishStatus("Focus and exposure locked")
''',
    '''                let focusMode = Self.preferredFocusLockMode(
                    supportsAutoFocus: device.isFocusModeSupported(.autoFocus),
                    supportsLocked: device.isFocusModeSupported(.locked)
                )
                let exposureMode = Self.preferredExposureLockMode(
                    supportsAutoExpose: device.isExposureModeSupported(.autoExpose),
                    supportsLocked: device.isExposureModeSupported(.locked)
                )
                guard focusMode != nil || exposureMode != nil else {
                    self.publishStatus("Focus lock is unavailable right now.")
                    return
                }

                // One-shot autofocus and autoexposure meter at the selected
                // point before AVFoundation transitions them to locked. A
                // direct `.locked` assignment would freeze the preexisting
                // lens and exposure state, potentially before the tap-driven
                // adjustment has completed.
                if let focusMode {
                    device.focusMode = focusMode
                }
                if let exposureMode {
                    device.exposureMode = exposureMode
                    self.applyExposureBiasOnQueue(to: device)
                }
                self.focusExposureLocked = true
                self.publishFocusExposureLocked(true)
                self.publishStatus("Focus and exposure locked")
'''
)

replace_once(
    "FilmyCamera/Services/CameraService.swift",
    '''    /// Snaps camera compensation to real one-third-stop increments so repeated
    /// touch adjustments stay symmetric and always return cleanly to neutral.
    public static func quantizedExposureBias(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return (value * 3).rounded() / 3
    }

    private static func exposureBiasBounds(
''',
    '''    /// Snaps camera compensation to real one-third-stop increments so repeated
    /// touch adjustments stay symmetric and always return cleanly to neutral.
    public static func quantizedExposureBias(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return (value * 3).rounded() / 3
    }

    /// A point-based lock should meter once before freezing the lens. Prefer
    /// `.autoFocus`, which performs one adjustment and then locks, while
    /// retaining `.locked` as a fallback for devices with narrower support.
    static func preferredFocusLockMode(
        supportsAutoFocus: Bool,
        supportsLocked: Bool
    ) -> AVCaptureDevice.FocusMode? {
        if supportsAutoFocus { return .autoFocus }
        if supportsLocked { return .locked }
        return nil
    }

    /// A point-based exposure lock should meter once before freezing exposure.
    /// Prefer `.autoExpose`, which performs one adjustment and then locks,
    /// while retaining `.locked` as a fallback for unusual capture devices.
    static func preferredExposureLockMode(
        supportsAutoExpose: Bool,
        supportsLocked: Bool
    ) -> AVCaptureDevice.ExposureMode? {
        if supportsAutoExpose { return .autoExpose }
        if supportsLocked { return .locked }
        return nil
    }

    private static func exposureBiasBounds(
'''
)

replace_once(
    "FilmyCameraTests/CameraServiceAvailabilityTests.swift",
    '''    func testCaptureDevicePointNormalizesAnglesAndInvalidCoordinates() {
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

}
''',
    '''    func testCaptureDevicePointNormalizesAnglesAndInvalidCoordinates() {
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
'''
)
