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
    '''    /// A point-based exposure lock should meter once before freezing exposure.
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
''',
    '''    /// A point-based exposure lock should meter once before freezing exposure.
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

    /// A configured session without an active device is structurally broken.
    /// Reusing it would leave every later Resume action in needsRecovery.
    static func shouldRebuildConfiguredSessionGraph(
        isConfigured: Bool,
        hasActiveDevice: Bool
    ) -> Bool {
        isConfigured && !hasActiveDevice
    }

    /// A failed input swap is recoverable only when the previous input was
    /// restored. Otherwise the remaining outputs belong to an unusable graph.
    static func shouldResetSessionGraphAfterFailedInputReplacement(
        restoredPreviousInput: Bool
    ) -> Bool {
        !restoredPreviousInput
    }

    private static func exposureBiasBounds(
'''
)

replace_once(
    "FilmyCamera/Services/CameraService.swift",
    '''        // A stopped session keeps its inputs and outputs. Reuse the existing
        // graph when returning from background or another tab instead of
        // trying to add duplicate AVFoundation objects.
        if isConfigured {
            guard let device = activeDevice() else {
                resetCaptureCapabilitiesOnQueue()
                publishRunning(false)
                publishAvailability(.needsRecovery)
                publishStatus("Camera needs to be reopened.")
                return
            }
            refreshCaptureCapabilitiesOnQueue(for: device)
            configureOrientation()
            session.startRunning()
            let running = session.isRunning
            publishRunning(running)
            publishAvailability(running ? .running : .unavailable)
            publishStatus(running ? "Camera ready" : "Camera could not start.")
            return
        }
''',
    '''        // A stopped session keeps its inputs and outputs. Reuse the existing
        // graph when returning from background or another tab. If AVFoundation
        // lost its input, tear down the incomplete graph and rebuild below.
        if isConfigured, let device = activeDevice() {
            refreshCaptureCapabilitiesOnQueue(for: device)
            configureOrientation()
            session.startRunning()
            let running = session.isRunning
            publishRunning(running)
            publishAvailability(running ? .running : .unavailable)
            publishStatus(running ? "Camera ready" : "Camera could not start.")
            return
        }
        if Self.shouldRebuildConfiguredSessionGraph(
            isConfigured: isConfigured,
            hasActiveDevice: activeDevice() != nil
        ) {
            resetSessionGraphOnQueue(
                pendingCaptureStatus: "Camera needs to be reopened."
            )
        }
'''
)

replace_once(
    "FilmyCamera/Services/CameraService.swift",
    '''        guard replaceCameraInputOnQueue(with: desiredDevice) else {
            publishStatus("The \\(position.title.lowercased()) camera is unavailable right now.")
            return
        }
''',
    '''        guard replaceCameraInputOnQueue(with: desiredDevice) else {
            if isConfigured {
                publishStatus("The \\(position.title.lowercased()) camera is unavailable right now.")
            } else {
                publishRunning(false)
                publishAvailability(.needsRecovery)
                publishStatus("Camera needs to be reopened.")
            }
            return
        }
'''
)

replace_once(
    "FilmyCamera/Services/CameraService.swift",
    '''        guard replaceCameraInputOnQueue(with: alternateDevice) else {
            publishStatus("That lens is unavailable right now.")
            return
        }
''',
    '''        guard replaceCameraInputOnQueue(with: alternateDevice) else {
            if isConfigured {
                publishStatus("That lens is unavailable right now.")
            } else {
                publishRunning(false)
                publishAvailability(.needsRecovery)
                publishStatus("Camera needs to be reopened.")
            }
            return
        }
'''
)

replace_once(
    "FilmyCamera/Services/CameraService.swift",
    '''    private func replaceCameraInputOnQueue(with device: AVCaptureDevice) -> Bool {
        guard let newInput = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        let oldInput = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first
        session.beginConfiguration()
        if let oldInput {
            session.removeInput(oldInput)
        }

        guard session.canAddInput(newInput) else {
            if let oldInput, session.canAddInput(oldInput) {
                session.addInput(oldInput)
            }
            session.commitConfiguration()
            return false
        }

        session.addInput(newInput)
        configurePhotoDimensions(for: device)
        configureOrientation()
        session.commitConfiguration()
        installRotationCoordinatorOnQueue(for: device)
        return true
    }
''',
    '''    private func replaceCameraInputOnQueue(with device: AVCaptureDevice) -> Bool {
        guard let newInput = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        let oldInput = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first
        session.beginConfiguration()
        if let oldInput {
            session.removeInput(oldInput)
        }

        guard session.canAddInput(newInput) else {
            let restoredPreviousInput: Bool
            if let oldInput, session.canAddInput(oldInput) {
                session.addInput(oldInput)
                restoredPreviousInput = true
            } else {
                restoredPreviousInput = false
            }
            session.commitConfiguration()

            if Self.shouldResetSessionGraphAfterFailedInputReplacement(
                restoredPreviousInput: restoredPreviousInput
            ) {
                resetSessionGraphOnQueue(
                    pendingCaptureStatus: "Camera needs to be reopened."
                )
            }
            return false
        }

        session.addInput(newInput)
        configurePhotoDimensions(for: device)
        configureOrientation()
        session.commitConfiguration()
        installRotationCoordinatorOnQueue(for: device)
        return true
    }

    private func resetSessionGraphOnQueue(pendingCaptureStatus: String) {
        cancelPendingPhotoOnQueue(status: pendingCaptureStatus)
        activeConstituentObservation?.invalidate()
        activeConstituentObservation = nil
        observedVirtualDeviceID = nil

        let rotationToken = UUID()
        rotationCoordinatorToken = rotationToken
        rotationCoordinatorDeviceID = nil
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.rotationCoordinatorToken == rotationToken else {
                return
            }
            self.previewRotationObservation?.invalidate()
            self.captureRotationObservation?.invalidate()
            self.previewRotationObservation = nil
            self.captureRotationObservation = nil
            self.rotationCoordinator = nil
            self.activeRotationToken = nil
            self.rotationDevice = nil
        }

        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        session.commitConfiguration()

        isConfigured = false
        configuredPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
        focusExposureLocked = false
        publishFocusExposureLocked(false)
        resetCaptureCapabilitiesOnQueue()
    }
'''
)

replace_once(
    "FilmyCameraTests/CameraServiceAvailabilityTests.swift",
    '''    func testExposureLockFallsBackToLockedAndFailsClosedWithoutSupport() {
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
''',
    '''    func testExposureLockFallsBackToLockedAndFailsClosedWithoutSupport() {
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

    func testConfiguredSessionGraphRebuildsOnlyWhenItsInputIsMissing() {
        XCTAssertTrue(
            CameraService.shouldRebuildConfiguredSessionGraph(
                isConfigured: true,
                hasActiveDevice: false
            )
        )
        XCTAssertFalse(
            CameraService.shouldRebuildConfiguredSessionGraph(
                isConfigured: true,
                hasActiveDevice: true
            )
        )
        XCTAssertFalse(
            CameraService.shouldRebuildConfiguredSessionGraph(
                isConfigured: false,
                hasActiveDevice: false
            )
        )
    }

    func testFailedInputReplacementResetsOnlyWhenPreviousInputWasLost() {
        XCTAssertFalse(
            CameraService.shouldResetSessionGraphAfterFailedInputReplacement(
                restoredPreviousInput: true
            )
        )
        XCTAssertTrue(
            CameraService.shouldResetSessionGraphAfterFailedInputReplacement(
                restoredPreviousInput: false
            )
        )
    }

}
'''
)
