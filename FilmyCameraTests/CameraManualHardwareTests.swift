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
        let canVerifyFlashPreference = camera.flashAvailability == .available
        if canVerifyFlashPreference {
            camera.setFlashMode(.on)
            try await requireEventually("Remembered flash is On before manual exposure") {
                camera.flashMode == .on
            }
        }

        let bounds = camera.manualControls
        let iso1 = min(bounds.maximumISO, max(bounds.minimumISO, 100))
        let iso2 = min(bounds.maximumISO, max(bounds.minimumISO, 200))
        let duration1 = min(bounds.maximumExposureDurationSeconds,
                            max(bounds.minimumExposureDurationSeconds, 1.0 / 125))
        let duration2 = min(bounds.maximumExposureDurationSeconds,
                            max(bounds.minimumExposureDurationSeconds, 1.0 / 60))
        var observations: [String] = []
        var capturedISOs: [Double] = []
        defer {
            let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
            attachment.name = "Manual-capture-request-and-EXIF"
            attachment.lifetime = .keepAlways
            add(attachment)
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
            let settledISO = wide.iso
            let settledDuration = wide.exposureDuration.seconds
            camera.focus(at: CGPoint(x: 0.35, y: 0.6))
            // A following queued capture also establishes that the tap request
            // has reached the session before metadata is evaluated.
            let delivered = expectation(description: "Manual photo \(index + 1)")
            let box = PhotoBox()
            camera.capturePhoto { photo in box.store(photo); delivered.fulfill() }
            await fulfillment(of: [delivered], timeout: 25)
            let photo = try XCTUnwrap(box.photo, "Manual photo must be delivered")
            let source = try XCTUnwrap(CGImageSourceCreateWithData(photo.fileData as CFData, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [String: Any])
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
        camera.stop()
        try await requireEventually("Camera stops") { !camera.isRunning }
        camera.start()
        try await requireEventually("Manual modes survive the reused session") {
            camera.isRunning && camera.manualControls.exposureMode == .manual
                && !camera.manualControls.isApplying
                && wide.exposureMode == .custom
                && camera.manualControls.whiteBalanceMode == beforePause.whiteBalanceMode
                && camera.manualControls.focusMode == beforePause.focusMode
        }
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
                camera.cameraPosition == .front && !camera.manualControls.isApplying
            }
            camera.resetManualControlsToAuto()
            try await requireEventually("Reset on the front camera completes") {
                !camera.manualControls.isAnyManualModeEnabled && !camera.manualControls.isApplying
            }
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
        }
        #endif
    }

    private func requireEventually(
        _ description: String,
        timeout: TimeInterval = 15,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition(), description)
        if !condition() { throw AcceptanceError.timeout }
    }

    private enum AcceptanceError: Error { case timeout }

    private final class PhotoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CameraService.CapturedPhoto?
        var photo: CameraService.CapturedPhoto? { lock.withLock { value } }
        func store(_ photo: CameraService.CapturedPhoto?) { lock.withLock { value = photo } }
    }
}
