import XCTest
@preconcurrency import AVFoundation
@testable import FilmyCamera

/// Device-only flash checks. They talk to real hardware and skip on
/// Simulator, on devices without a flash, and when camera access is denied.
///
/// The plain AVFoundation variants bisect the capture graph: a photo-only
/// session, one with a video data output (the live viewfinder), and one that
/// also caps the frame rate and requests the largest photo dimensions, which
/// is the app's configuration. `AVCaptureResolvedPhotoSettings.isFlashEnabled`
/// reports whether the flash actually fired for that request.
final class FlashHardwareDeviceTests: XCTestCase {
    private final class PhotoSink: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
        let finished = XCTestExpectation(description: "photo delivered")
        private let lock = NSLock()
        private var flashFiredValue = false
        private var errorDescription: String?
        private var dimensions = CMVideoDimensions(width: 0, height: 0)

        var flashFired: Bool { lock.withLock { flashFiredValue } }
        var failure: String? { lock.withLock { errorDescription } }
        var photoDimensions: CMVideoDimensions { lock.withLock { dimensions } }

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            lock.withLock {
                flashFiredValue = photo.resolvedSettings.isFlashEnabled
                errorDescription = error.map { String(describing: $0) }
                dimensions = photo.resolvedSettings.photoDimensions
            }
            finished.fulfill()
        }
    }

    private struct Variant {
        let name: String
        let preset: AVCaptureSession.Preset
        let addVideoOutput: Bool
        let capFrameRate: Bool
        let maximumPhotoDimensions: Bool
    }

    private func backCameraWithFlash() throws -> AVCaptureDevice {
        #if targetEnvironment(simulator)
        throw XCTSkip("Flash hardware requires a physical iPhone or iPad")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw XCTSkip("Camera access is not authorized for the test host")
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
                .builtInUltraWideCamera
            ],
            mediaType: .video,
            position: .back
        )
        for device in discovery.devices {
            print(
                "FLASHDIAG device=\(device.deviceType.rawValue) hasFlash=\(device.hasFlash)"
                + " flashAvailable=\(device.isFlashAvailable) hasTorch=\(device.hasTorch)"
                + " constituents=\(device.constituentDevices.map(\.deviceType.rawValue))"
            )
        }
        guard let device = discovery.devices.first(where: { $0.hasFlash }) else {
            throw XCTSkip("No back camera with a flash on this device")
        }
        return device
        #endif
    }

    private func captureWithFlash(_ variant: Variant, device: AVCaptureDevice) throws -> Bool {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let photoOutput = AVCapturePhotoOutput()
        let videoOutput = AVCaptureVideoDataOutput()
        let videoQueue = DispatchQueue(label: "flash-diag-video")

        session.beginConfiguration()
        if session.canSetSessionPreset(variant.preset) {
            session.sessionPreset = variant.preset
        }
        XCTAssertTrue(session.canAddInput(input), variant.name)
        session.addInput(input)
        if variant.addVideoOutput {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(nil, queue: videoQueue)
            XCTAssertTrue(session.canAddOutput(videoOutput), variant.name)
            session.addOutput(videoOutput)
        }
        XCTAssertTrue(session.canAddOutput(photoOutput), variant.name)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        if variant.maximumPhotoDimensions,
           let maximum = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
               Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
           }) {
            photoOutput.maxPhotoDimensions = maximum
        }
        session.commitConfiguration()

        if variant.capFrameRate {
            let target = CMTime(value: 1, timescale: 30)
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                CMTimeCompare(target, $0.minFrameDuration) >= 0 && CMTimeCompare(target, $0.maxFrameDuration) <= 0
            }) {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = target
                device.activeVideoMaxFrameDuration = target
                device.unlockForConfiguration()
            }
        }

        session.startRunning()
        defer { session.stopRunning() }
        // Let auto exposure and the flash subsystem settle on the live scene.
        Thread.sleep(forTimeInterval: 1.5)

        let supported = photoOutput.supportedFlashModes.map(\.rawValue)
        print(
            "FLASHDIAG variant=\(variant.name) running=\(session.isRunning)"
            + " supportedFlashModes=\(supported) flashAvailable=\(device.isFlashAvailable)"
            + " format=\(device.activeFormat.formatDescription.dimensions.width)x\(device.activeFormat.formatDescription.dimensions.height)"
            + " maxPhoto=\(photoOutput.maxPhotoDimensions.width)x\(photoOutput.maxPhotoDimensions.height)"
            + " fps=\(device.activeVideoMinFrameDuration.timescale)/\(device.activeVideoMinFrameDuration.value)"
        )
        guard supported.contains(AVCaptureDevice.FlashMode.on.rawValue) else {
            print("FLASHDIAG variant=\(variant.name) flash .on unsupported for this graph")
            return false
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .on
        settings.photoQualityPrioritization = .quality
        if variant.maximumPhotoDimensions {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }
        let sink = PhotoSink()
        photoOutput.capturePhoto(with: settings, delegate: sink)
        wait(for: [sink.finished], timeout: 20)
        print(
            "FLASHDIAG variant=\(variant.name) flashFired=\(sink.flashFired)"
            + " dims=\(sink.photoDimensions.width)x\(sink.photoDimensions.height)"
            + " error=\(sink.failure ?? "none")"
        )
        XCTAssertNil(sink.failure, variant.name)
        return sink.flashFired
    }

    func testPhotoOutputFiresFlashAcrossCaptureGraphVariants() throws {
        let device = try backCameraWithFlash()
        let variants = [
            Variant(name: "photo-only", preset: .photo, addVideoOutput: false, capFrameRate: false, maximumPhotoDimensions: false),
            Variant(name: "photo+video", preset: .photo, addVideoOutput: true, capFrameRate: false, maximumPhotoDimensions: false),
            Variant(name: "app-graph", preset: .photo, addVideoOutput: true, capFrameRate: true, maximumPhotoDimensions: true)
        ]
        var results: [String: Bool] = [:]
        for variant in variants {
            results[variant.name] = try captureWithFlash(variant, device: device)
        }
        print("FLASHDIAG results=\(results)")
        XCTAssertEqual(results["photo-only"], true, "A plain photo session must fire the flash when asked")
        XCTAssertEqual(results["app-graph"], true, "The app's capture graph must fire the flash when asked")
    }

    /// End-to-end through the app's own service: start, select flash On,
    /// capture, and require the delivered photo to report a fired flash.
    @MainActor
    func testCameraServiceFiresFlashWhenFlashIsOn() throws {
        _ = try backCameraWithFlash()
        let camera = CameraService()
        camera.start()
        defer { camera.stop() }

        let running = expectation(for: NSPredicate { _, _ in
            MainActor.assumeIsolated { camera.availability == .running }
        }, evaluatedWith: nil)
        wait(for: [running], timeout: 20)
        print(
            "FLASHDIAG service availability=\(camera.availability.rawValue)"
            + " flashAvailability=\(camera.flashAvailability.rawValue) flashMode=\(camera.flashMode)"
            + " lens=\(camera.selectedLensID ?? "nil") position=\(camera.cameraPosition)"
        )
        guard camera.flashAvailability != .unsupported else {
            throw XCTSkip("The service reports no flash support on the active camera")
        }

        camera.setFlashMode(.on)
        let flashOn = expectation(for: NSPredicate { _, _ in
            MainActor.assumeIsolated { camera.flashMode == .on }
        }, evaluatedWith: nil)
        wait(for: [flashOn], timeout: 5)
        // Give auto exposure a moment on the live scene before firing.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))

        let delivered = expectation(description: "photo delivered")
        let box = PhotoBox()
        camera.capturePhoto { photo in
            box.store(photo)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 20)
        let photo = box.photo
        print(
            "FLASHDIAG service photo=\(photo != nil) flashFired=\(photo?.flashFired ?? false)"
            + " status=\(camera.statusMessage) flashAvailability=\(camera.flashAvailability.rawValue)"
        )
        XCTAssertNotNil(photo, "The service must deliver a photo")
        XCTAssertEqual(photo?.flashFired, true, "Flash On must fire the flash: \(camera.statusMessage)")
    }

    private final class PhotoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: CameraService.CapturedPhoto?
        var photo: CameraService.CapturedPhoto? { lock.withLock { stored } }
        func store(_ photo: CameraService.CapturedPhoto?) { lock.withLock { stored = photo } }
    }
}
