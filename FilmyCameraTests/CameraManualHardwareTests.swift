import XCTest
@preconcurrency import AVFoundation
import ImageIO
@testable import FilmyCamera

/// Opt-in hardware acceptance through the production session and photo output.
/// Captures stay in this result bundle; this test does not write to Photos.
@MainActor
final class CameraManualHardwareTests: XCTestCase {
    func testPhysicalManualExposureMatchesSavedPhotoAndSurvivesSessionReuse() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Manual capture acceptance requires physical camera hardware")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PHOTOS_WRITE"] == "1",
            "Run the explicit device acceptance lane"
        )
        try XCTSkipUnless(
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            "Authorize camera access for the test host"
        )
        let wide = try XCTUnwrap(AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ))
        try XCTSkipUnless(wide.isExposureModeSupported(.custom), "Custom exposure unsupported")

        let camera = CameraService()
        defer { camera.resetManualControlsToAuto(); camera.stop() }
        camera.start()
        try await requireEventually("Camera starts") { camera.availability == .running }
        camera.setManualControlLens(id: wide.uniqueID)
        try await requireEventually("A physical wide camera exposes manual controls") {
            camera.manualControls.activeDeviceID == wide.uniqueID
                && camera.manualControls.manualExposureSupported
        }

        let bounds = camera.manualControls
        let iso1 = min(bounds.maximumISO, max(bounds.minimumISO, 100))
        let iso2 = min(bounds.maximumISO, max(bounds.minimumISO, 200))
        let duration1 = min(bounds.maximumExposureDurationSeconds,
                            max(bounds.minimumExposureDurationSeconds, 1.0 / 125))
        let duration2 = min(bounds.maximumExposureDurationSeconds,
                            max(bounds.minimumExposureDurationSeconds, 1.0 / 60))
        let photoOutput = try XCTUnwrap(camera.session.outputs.compactMap {
            $0 as? AVCapturePhotoOutput
        }.first)
        let canVerifyFlashPreference = camera.flashAvailability == .available
        var observations: [String] = []
        let runtimeErrors = StringBox()
        let runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: camera.session,
            queue: nil
        ) { notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            runtimeErrors.append(
                "runtimeError domain=\(error?.domain ?? "none") code=\(error?.code ?? 0) "
                    + "description=\(error?.localizedDescription ?? "none")"
            )
        }
        func recordFlash(_ phase: String) {
            let activeDevice = camera.session.inputs.compactMap {
                ($0 as? AVCaptureDeviceInput)?.device
            }.first
            observations.append("phase=\(phase) flashSelection=\(camera.flashMode) "
                + "availability=\(camera.flashAvailability) activeDevice=\(activeDevice?.deviceType.rawValue ?? "none") "
                + "deviceID=\(activeDevice?.uniqueID ?? "none") position=\(activeDevice?.position.rawValue ?? 0) "
                + "hasFlash=\(activeDevice?.hasFlash ?? false) hardwareAvailable=\(activeDevice?.isFlashAvailable ?? false) "
                + "supportedModes=\(photoOutput.supportedFlashModes.map(\.rawValue))")
        }
        func recordSession(_ phase: String) {
            let controls = camera.manualControls
            let activeDevice = camera.session.inputs.compactMap {
                ($0 as? AVCaptureDeviceInput)?.device
            }.first
            observations.append("phase=\(phase) publishedRunning=\(camera.isRunning) "
                + "sessionRunning=\(camera.session.isRunning) interrupted=\(camera.session.isInterrupted) "
                + "availability=\(camera.availability.rawValue) status=\(camera.statusMessage) "
                + "activeID=\(activeDevice?.uniqueID ?? "none") publicDeviceID=\(controls.activeDeviceID ?? "none") "
                + "publicExposure=\(controls.exposureMode.rawValue) publicWB=\(controls.whiteBalanceMode.rawValue) "
                + "publicFocus=\(controls.focusMode.rawValue) applying=\(controls.isApplying) "
                + "hardwareExposure=\(activeDevice?.exposureMode.rawValue ?? -1) "
                + "hardwareWB=\(activeDevice?.whiteBalanceMode.rawValue ?? -1) "
                + "hardwareFocus=\(activeDevice?.focusMode.rawValue ?? -1) "
                + "iso=\(activeDevice?.iso ?? 0) duration=\(activeDevice?.exposureDuration.seconds ?? 0) "
                + "lensPosition=\(activeDevice?.lensPosition ?? 0)")
        }
        recordFlash("initial-auto")
        var capturedISOs: [Double] = []
        defer {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
            recordFlash("final")
            observations.append(contentsOf: runtimeErrors.values)
            let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
            attachment.name = "Manual-capture-request-and-EXIF"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // Auto uses quality prioritization and can resolve the requested 48 MP
        // maximum. Prove that the production callback and encoded file agree;
        // a lower resolved size is AVFoundation's decision, not app resizing.
        camera.resetManualControlsToAuto()
        camera.setFlashMode(.off)
        try await requireEventually("Auto quality control capture is ready") {
            !camera.manualControls.isAnyManualModeEnabled
                && !camera.manualControls.isApplying
                && wide.exposureMode != .custom
                && camera.flashMode == .off
        }
        let requestedDimensions = photoOutput.maxPhotoDimensions
        let autoPhoto = try await capturePhoto(camera, description: "Auto quality photo")
        let autoProperties = try assertEncodedDimensions(
            of: autoPhoto,
            requestedMaximum: requestedDimensions,
            label: "Auto quality"
        )
        observations.append("capture=auto requested=\(requestedDimensions.width)x\(requestedDimensions.height) "
            + "resolved=\(autoPhoto.dimensions.width)x\(autoPhoto.dimensions.height) "
            + "encoded=\(autoProperties.width)x\(autoProperties.height)")
        let autoImage = XCTAttachment(data: autoPhoto.fileData, uniformTypeIdentifier: "public.jpeg")
        autoImage.name = "Auto-quality-resolution-control"
        autoImage.lifetime = .keepAlways
        add(autoImage)

        if canVerifyFlashPreference {
            camera.setFlashMode(.on)
            try await requireEventually("Remembered flash is On before manual exposure") {
                camera.flashMode == .on
            }
            recordFlash("initial-on")
        }

        let requests = [(iso1, duration1), (iso2, duration1), (iso2, duration2)]
        for (index, request) in requests.enumerated() {
            let (iso, duration) = request
            camera.setManualExposure(iso: iso, durationSeconds: duration)
            try await requireEventually("Hardware applies custom exposure \(index + 1)") {
                camera.manualControls.exposureMode == .manual
                    && !camera.manualControls.isApplying
                    && wide.exposureMode == .custom
                    && abs(Double(wide.iso - iso)) <= max(Double(iso) * 0.05, 1)
                    && abs(wide.exposureDuration.seconds - duration) <= max(duration * 0.05, 0.0001)
            }
            recordFlash("manual-\(index + 1)")
            let settledISO = wide.iso
            let settledDuration = wide.exposureDuration.seconds
            camera.focus(at: CGPoint(x: 0.35, y: 0.6))
            // A following queued capture also establishes that the tap request
            // has reached the session before metadata is evaluated.
            let photo = try await capturePhoto(camera, description: "Manual photo \(index + 1)")
            let decoded = try assertEncodedDimensions(
                of: photo,
                requestedMaximum: requestedDimensions,
                label: "Manual photo \(index + 1)"
            )
            let properties = decoded.properties
            observations.append("capture=\(index + 1) requested=\(requestedDimensions.width)x\(requestedDimensions.height) "
                + "resolved=\(photo.dimensions.width)x\(photo.dimensions.height) "
                + "encoded=\(decoded.width)x\(decoded.height)")
            let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String]
                as? [String: Any])
            let capturedISO = try XCTUnwrap((exif[kCGImagePropertyExifISOSpeedRatings as String]
                as? [NSNumber])?.first).doubleValue
            let capturedDuration = try XCTUnwrap(exif[kCGImagePropertyExifExposureTime as String]
                as? NSNumber).doubleValue
            observations.append("capture=\(index + 1) requestedISO=\(iso) sensorISO=\(settledISO) EXIFISO=\(capturedISO) "
                + "requestedSeconds=\(duration) sensorSeconds=\(settledDuration) EXIFSeconds=\(capturedDuration)")
            // Canonical ISO requests should remain close in the saved photo.
            // Low ISO requests on the reference iPad showed a small nominal
            // EXIF offset; retain that evidence separately, without rewriting it.
            XCTAssertGreaterThan(capturedISO, 0)
            XCTAssertEqual(capturedISO, Double(iso), accuracy: max(Double(iso) * 0.1, 1))
            capturedISOs.append(capturedISO)
            XCTAssertEqual(capturedDuration, duration, accuracy: max(duration * 0.1, 0.0001))
            XCTAssertFalse(photo.flashFired)
            XCTAssertEqual(wide.exposureMode, .custom, "Tap autofocus must preserve manual exposure")
            XCTAssertEqual(camera.manualControls.exposureMode, .manual)
            let image = XCTAttachment(data: photo.fileData, uniformTypeIdentifier: "public.jpeg")
            image.name = "Manual-exposure-\(index + 1)"
            image.lifetime = .keepAlways
            add(image)
        }
        // Vary ISO with shutter held fixed, then shutter with ISO held fixed.
        // A stuck/default ISO or coupling the two controls must fail.
        if capturedISOs.count == requests.count {
            for index in 1..<requests.count {
                let requestedRatio = Double(requests[index].0 / requests[index - 1].0)
                XCTAssertEqual(capturedISOs[index] / capturedISOs[index - 1], requestedRatio,
                               accuracy: requestedRatio * 0.05)
            }
        }

        var whiteBalanceBeforePause: AVCaptureDevice.WhiteBalanceGains?
        if camera.manualControls.manualWhiteBalanceSupported {
            let requestedGains = wide.deviceWhiteBalanceGains(for:
                AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: 4300, tint: 8)
            )
            camera.setManualWhiteBalance(kelvin: 4300, tint: 8)
            try await requireEventually("Sensor white balance locks") {
                camera.manualControls.whiteBalanceMode == .manual && !camera.manualControls.isApplying
                    && wide.whiteBalanceMode == .locked
            }
            let gains = wide.deviceWhiteBalanceGains
            for gain in [gains.redGain, gains.greenGain, gains.blueGain] {
                XCTAssertTrue(gain.isFinite)
                XCTAssertGreaterThanOrEqual(gain, 1)
                XCTAssertLessThanOrEqual(gain, wide.maxWhiteBalanceGain)
            }
            for (actual, requested) in zip(
                [gains.redGain, gains.greenGain, gains.blueGain],
                [requestedGains.redGain, requestedGains.greenGain, requestedGains.blueGain]
            ) {
                let expected = min(max(requested, 1), wide.maxWhiteBalanceGain)
                XCTAssertEqual(actual, expected, accuracy: max(expected * 0.03, 0.02),
                               "The requested temperature/tint must reach the sensor")
            }
            whiteBalanceBeforePause = gains
        }
        if camera.manualControls.manualFocusSupported {
            camera.setManualFocus(lensPosition: 0.55)
            try await requireEventually("Manual focus is applied") {
                camera.manualControls.focusMode == .manual && !camera.manualControls.isApplying
                    && wide.focusMode == .locked
                    && abs(wide.lensPosition - 0.55) < 0.03
            }
        }
        let beforePause = camera.manualControls
        recordSession("before-stop")
        camera.stop()
        recordSession("stop-requested")
        try await requireEventually("Camera stops", onTimeout: {
            recordSession("stop-timeout")
        }) { !camera.isRunning }
        recordSession("stopped")
        camera.start()
        recordSession("start-requested")
        try await requireEventually("Manual modes survive the reused session", onTimeout: {
            recordSession("start-timeout")
        }) {
            camera.isRunning && camera.manualControls.exposureMode == .manual
                && !camera.manualControls.isApplying
                && wide.exposureMode == .custom
                && camera.manualControls.whiteBalanceMode == beforePause.whiteBalanceMode
                && camera.manualControls.focusMode == beforePause.focusMode
        }
        recordSession("started")
        recordFlash("session-reused")
        XCTAssertEqual(wide.iso, iso2, accuracy: max(iso2 * 0.05, 1))
        XCTAssertEqual(wide.exposureDuration.seconds, duration2,
                       accuracy: max(duration2 * 0.05, 0.0001))
        if let savedGains = whiteBalanceBeforePause {
            XCTAssertEqual(wide.whiteBalanceMode, .locked)
            let restored = wide.deviceWhiteBalanceGains
            for (actual, saved) in zip(
                [restored.redGain, restored.greenGain, restored.blueGain],
                [savedGains.redGain, savedGains.greenGain, savedGains.blueGain]
            ) { XCTAssertEqual(actual, saved, accuracy: max(saved * 0.03, 0.02)) }
        }
        if beforePause.focusMode == .manual {
            XCTAssertEqual(wide.focusMode, .locked)
            XCTAssertEqual(wide.lensPosition, beforePause.lensPosition, accuracy: 0.03)
        }

        if camera.availableCameraPositions.contains(.front) {
            camera.setCameraPosition(.front)
            try await requireEventually("Front camera settles") {
                let input = camera.session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first
                return camera.cameraPosition == .front
                    && input?.device.position == .front
                    && camera.manualControls.activeDeviceID == input?.device.uniqueID
                    && !camera.manualControls.isApplying
            }
            recordFlash("front")
            camera.resetManualControlsToAuto()
            try await requireEventually("Reset on the front camera completes") {
                !camera.manualControls.isAnyManualModeEnabled && !camera.manualControls.isApplying
            }
            recordFlash("front-reset")
            camera.setCameraPosition(.back)
            try await requireEventually("Returning to the old physical lens restores actual Auto") {
                camera.cameraPosition == .back
                    && camera.manualControls.activeDeviceID == wide.uniqueID
                    && !camera.manualControls.isAnyManualModeEnabled
                    && !camera.manualControls.isApplying
                    && wide.exposureMode != .custom && wide.whiteBalanceMode != .locked
                    && (!beforePause.manualFocusSupported || wide.focusMode != .locked)
            }
        }

        recordFlash("back-auto")
        if canVerifyFlashPreference {
            try await requireEventually("Returning to the rear camera restores flash support and choice") {
                photoOutput.supportedFlashModes.contains(.on) && camera.flashMode == .on
            }
        }

        // Reset must supersede in-flight changes, including a setter callback
        // arriving after the subsequent Auto request on the session queue.
        camera.setManualExposure(iso: iso1, durationSeconds: duration1)
        camera.setManualExposure(iso: iso2, durationSeconds: duration2)
        camera.resetManualControlsToAuto()
        try await requireEventually("Reset returns every supported mode to automatic hardware") {
            camera.manualControls.exposureMode == .auto
                && !camera.manualControls.isApplying
                && camera.manualControls.whiteBalanceMode == .auto
                && camera.manualControls.focusMode == .auto
                && wide.exposureMode != .custom && wide.whiteBalanceMode != .locked
                && (!beforePause.manualFocusSupported || wide.focusMode != .locked)
        }
        recordFlash("rapid-reset")
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(camera.manualControls.exposureMode, .auto)
            XCTAssertFalse(camera.manualControls.isApplying)
            XCTAssertNotEqual(wide.exposureMode, .custom)
        }
        if canVerifyFlashPreference {
            try await requireEventually("Returning to Auto restores the remembered flash choice") {
                camera.flashMode == .on
            }
            try await requireEventually("Auto restores actual output support for flash On") {
                photoOutput.supportedFlashModes.contains(.on)
            }
        }
        #endif
    }

    private func requireEventually(
        _ description: String,
        timeout: TimeInterval = 15,
        onTimeout: (@MainActor () -> Void)? = nil,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        if !condition() { onTimeout?() }
        XCTAssertTrue(condition(), description)
        if !condition() { throw AcceptanceError.timeout }
    }

    private func capturePhoto(
        _ camera: CameraService,
        description: String
    ) async throws -> CameraService.CapturedPhoto {
        let delivered = expectation(description: description)
        let box = PhotoBox()
        camera.capturePhoto { photo in box.store(photo); delivered.fulfill() }
        await fulfillment(of: [delivered], timeout: 25)
        return try XCTUnwrap(box.photo, "\(description) must be delivered")
    }

    private func assertEncodedDimensions(
        of photo: CameraService.CapturedPhoto,
        requestedMaximum: CMVideoDimensions,
        label: String
    ) throws -> (properties: [String: Any], width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(photo.fileData as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        )
        let width = try XCTUnwrap(
            properties[kCGImagePropertyPixelWidth as String] as? NSNumber
        ).intValue
        let height = try XCTUnwrap(
            properties[kCGImagePropertyPixelHeight as String] as? NSNumber
        ).intValue
        let resolvedWidth = Int(photo.dimensions.width)
        let resolvedHeight = Int(photo.dimensions.height)
        XCTAssertGreaterThan(width, 0, "\(label) encoded width must be positive")
        XCTAssertGreaterThan(height, 0, "\(label) encoded height must be positive")
        XCTAssertGreaterThan(resolvedWidth, 0, "\(label) resolved width must be positive")
        XCTAssertGreaterThan(resolvedHeight, 0, "\(label) resolved height must be positive")
        XCTAssertLessThanOrEqual(resolvedWidth, Int(requestedMaximum.width))
        XCTAssertLessThanOrEqual(resolvedHeight, Int(requestedMaximum.height))
        XCTAssertEqual(width, resolvedWidth,
                       "\(label) JPEG width must match AVFoundation's resolved capture")
        XCTAssertEqual(height, resolvedHeight,
                       "\(label) JPEG height must match AVFoundation's resolved capture")
        return (properties, width, height)
    }

    private enum AcceptanceError: Error { case timeout }

    private final class PhotoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CameraService.CapturedPhoto?
        var photo: CameraService.CapturedPhoto? { lock.withLock { value } }
        func store(_ photo: CameraService.CapturedPhoto?) { lock.withLock { value = photo } }
    }

    private final class StringBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var values: [String] { lock.withLock { storage } }
        func append(_ value: String) { lock.withLock { storage.append(value) } }
    }
}
