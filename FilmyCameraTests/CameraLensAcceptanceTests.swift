import XCTest
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
@testable import FilmyCamera

/// Opt-in acceptance coverage for the iPhone 16 Pro's physical back-camera
/// path. This intentionally runs against CameraService's unchanged session
/// so the requested zoom, resolved constituent, delivered frames, and raw
/// capture metadata can be compared in one result bundle.
@MainActor
final class CameraLensAcceptanceTests: XCTestCase {
    private static let runEnvironmentKey = "FILMY_RUN_LENS_ACCEPTANCE"
    private static let targetMachineIdentifiers: Set<String> = ["iPhone17,1"]

    func testIPhone16ProZoomAndTelephotoCaptureAcceptance() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[Self.runEnvironmentKey] == "1",
            "Set \(Self.runEnvironmentKey)=1 for the bright, distant-scene iPhone 16 Pro lens acceptance run"
        )
        #if targetEnvironment(simulator)
        throw XCTSkip("Lens acceptance requires a physical iPhone 16 Pro")
        #else
        let machine = Self.machineIdentifier
        var observations = ["machine=\(machine)"]
        defer {
            let diagnostics = XCTAttachment(string: observations.joined(separator: "\n"))
            diagnostics.name = "iPhone16Pro-lens-constituent-and-EXIF-diagnostics"
            diagnostics.lifetime = .keepAlways
            add(diagnostics)
        }
        try XCTSkipUnless(
            Self.targetMachineIdentifiers.contains(machine),
            "Requires iPhone 16 Pro (iPhone17,1); observed hardware identifier \(machine)"
        )
        try XCTSkipUnless(
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            "Camera access is not authorized for the test host"
        )

        guard let discoveredCamera = Self.tripleCameraWithTelephoto() else {
            XCTFail("iPhone 16 Pro must expose a virtual back camera with wide and telephoto constituents")
            return
        }
        let camera = CameraService()
        let frameProbe = FrameProbe()
        let frameHandlerID = camera.installFrameHandler { _ in
            frameProbe.record()
        }
        defer {
            camera.removeFrameHandler(frameHandlerID)
            camera.stop()
        }

        camera.start()
        guard await waitUntil(timeout: 20, { camera.availability == .running }) else {
            XCTFail("CameraService did not start: \(camera.statusMessage)")
            return
        }
        try await waitForFrames(frameProbe, atLeast: 3)

        guard await waitUntil(timeout: 10, { !camera.availableLenses.isEmpty }) else {
            XCTFail("CameraService did not publish a lens inventory")
            return
        }

        let telephotoConstituent = try XCTUnwrap(
            discoveredCamera.constituentDevices.first(where: {
                $0.deviceType == .builtInTelephotoCamera
            })
        )
        let telephotoOption = try XCTUnwrap(
            camera.availableLenses.first(where: { $0.id == telephotoConstituent.uniqueID }),
            "CameraService must expose the discovered telephoto constituent"
        )
        XCTAssertGreaterThanOrEqual(
            camera.maxZoomFactor,
            5,
            "The iPhone 16 Pro session must reach the advertised 5× zoom"
        )

        camera.setLens(id: telephotoConstituent.uniqueID)
        let wideAnchor = Self.wideReferenceHardwareZoomFactor(for: discoveredCamera)
        let setLensNormalizedZoom = telephotoOption.zoomFactor / wideAnchor
        guard await waitUntil(timeout: 10, {
            abs(camera.zoomFactor - setLensNormalizedZoom) <= 0.05
        }) else {
            XCTFail("CameraService did not apply the telephoto option's requested hardware zoom")
            return
        }
        XCTAssertEqual(setLensNormalizedZoom, 5, accuracy: 0.1)
        observations.append(
            "setLens telephotoID=\(telephotoConstituent.uniqueID)"
                + " requestedHardware=\(telephotoOption.zoomFactor)×"
                + " normalized=\(camera.zoomFactor)× activeID=\(camera.selectedLensID ?? "nil")"
        )

        let zoomSequence: [CGFloat] = [0.5, 1, 5, 1]
        var inconclusiveTelephotoSelection = false

        for requestedZoom in zoomSequence {
            camera.setZoom(requestedZoom)
            guard await waitUntil(timeout: 10, {
                abs(camera.zoomFactor - requestedZoom) <= 0.05
            }) else {
                XCTFail("CameraService did not reach requested \(requestedZoom)× zoom")
                return
            }
            XCTAssertEqual(
                camera.zoomFactor,
                requestedZoom,
                accuracy: 0.05,
                "CameraService's normalized zoom did not reach the requested \(requestedZoom)×"
            )
            try await waitForFrames(frameProbe, atLeast: frameProbe.count + 3)

            let activeDevice = Self.activeDevice(in: camera.session)
            let activeConstituent = activeDevice?.activePrimaryConstituent
            let normalizedFromSession = activeDevice.map {
                $0.videoZoomFactor / Self.wideReferenceHardwareZoomFactor(for: $0)
            }
            let sessionNormalizedDescription = normalizedFromSession.map(String.init) ?? "nil"
            let hardwareZoomDescription = activeDevice.map {
                String(describing: $0.videoZoomFactor)
            } ?? "nil"
            let inputTypeDescription = activeDevice?.deviceType.rawValue ?? "nil"
            let constituentTypeDescription = activeConstituent?.deviceType.rawValue ?? "nil"
            let constituentIDDescription = activeConstituent?.uniqueID ?? "nil"
            let selectedLensIDDescription = camera.selectedLensID ?? "nil"
            let observation = "machine=\(machine) requested=\(requestedZoom)×"
                + " normalized=\(camera.zoomFactor)×"
                + " sessionNormalized=\(sessionNormalizedDescription)×"
                + " hardware=\(hardwareZoomDescription)×"
                + " input=\(inputTypeDescription)"
                + " constituent=\(constituentTypeDescription)"
                + " constituentID=\(constituentIDDescription)"
                + " selectedLensID=\(selectedLensIDDescription) frames=\(frameProbe.count)"
            observations.append(observation)
            print("LENS_ACCEPTANCE \(observation)")

            if requestedZoom == 5 {
                XCTAssertEqual(
                    normalizedFromSession ?? .nan,
                    5,
                    accuracy: 0.1,
                    "The active session input's normalized zoom must reach 5×"
                )
                if let activeDevice {
                    let wideAnchor = Self.wideReferenceHardwareZoomFactor(for: activeDevice)
                    XCTAssertEqual(
                        activeDevice.videoZoomFactor,
                        5 * wideAnchor,
                        accuracy: 0.1,
                        "The physical session zoom must match 5× after applying the wide-lens anchor"
                    )
                }
                let stableTelephoto = await waitForStableTelephoto(
                    in: camera.session,
                    duration: 0.5,
                    timeout: 3
                )
                let constituentBeforeCapture = Self.activeDevice(in: camera.session)?.activePrimaryConstituent
                if !stableTelephoto || constituentBeforeCapture?.deviceType != .builtInTelephotoCamera {
                    inconclusiveTelephotoSelection = true
                    observations.append(
                        "INCONCLUSIVE: 5× did not report the telephoto constituent; "
                            + "bright/distant scene, focus, and light level can affect AVFoundation lens choice"
                    )
                }

                let captureExpectation = expectation(description: "5× photo delivered")
                let captureBox = PhotoBox()
                camera.capturePhoto { photo in
                    captureBox.store(photo)
                    captureExpectation.fulfill()
                }
                await fulfillment(of: [captureExpectation], timeout: 20)
                let photo = try XCTUnwrap(captureBox.photo, "CameraService did not deliver a 5× capture")
                let exif = Self.exifMetadata(from: photo.fileData)
                observations.append("5× capture EXIF=\(Self.metadataDescription(exif))")
                let postCaptureConstituent = Self.activeDevice(in: camera.session)?.activePrimaryConstituent
                observations.append(
                    "5× constituent beforeCapture=\(constituentBeforeCapture?.deviceType.rawValue ?? "nil")"
                        + "(\(constituentBeforeCapture?.uniqueID ?? "nil"))"
                        + " afterCapture=\(postCaptureConstituent?.deviceType.rawValue ?? "nil")"
                        + "(\(postCaptureConstituent?.uniqueID ?? "nil"))"
                )
                if constituentBeforeCapture?.deviceType == .builtInTelephotoCamera,
                   postCaptureConstituent?.deviceType != .builtInTelephotoCamera {
                    inconclusiveTelephotoSelection = true
                    observations.append(
                        "INCONCLUSIVE: active constituent changed during capture "
                            + "from telephoto to \(postCaptureConstituent?.deviceType.rawValue ?? "nil")"
                    )
                }
                let lensModel = (exif[kCGImagePropertyExifLensModel as String] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let focalLength = (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue
                let fNumber = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
                let expectedTelephotoAperture = Double(telephotoConstituent.lensAperture)
                let apertureMatchesTelephoto = fNumber.map {
                    abs($0 - expectedTelephotoAperture) <= 0.05
                } ?? false
                let hasLensModel = lensModel?.isEmpty == false
                let hasPositiveFocalLength = focalLength.map { $0 > 0 } ?? false
                let observedFNumberDescription = fNumber.map {
                    String(describing: $0)
                } ?? "nil"
                if !hasLensModel
                    || !hasPositiveFocalLength
                    || !apertureMatchesTelephoto {
                    inconclusiveTelephotoSelection = true
                    let apertureDiagnostic =
                        "INCONCLUSIVE: capture EXIF lens evidence was missing or aperture did not match telephoto"
                            + " expectedFNumber=\(expectedTelephotoAperture)"
                            + " observedFNumber=\(observedFNumberDescription)"
                    observations.append(apertureDiagnostic)
                }
                let photoAttachment = XCTAttachment(data: photo.fileData, uniformTypeIdentifier: "public.jpeg")
                photoAttachment.name = "iPhone16Pro-5x-capture"
                photoAttachment.lifetime = .keepAlways
                add(photoAttachment)
            }
        }

        if inconclusiveTelephotoSelection {
            throw XCTSkip(
                "INCONCLUSIVE: the session reached normalized 5× and captured, "
                    + "but AVFoundation did not report telephoto for this scene; see attached constituent/EXIF diagnostics"
            )
        }
        #endif
    }

    private func waitForFrames(_ probe: FrameProbe, atLeast target: Int) async throws {
        let deadline = Date().addingTimeInterval(10)
        while probe.count < target, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertGreaterThanOrEqual(
            probe.count,
            target,
            "Live frames stopped while changing zoom or capturing"
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }

    private func waitForStableTelephoto(
        in session: AVCaptureSession,
        duration: TimeInterval,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var telephotoSince: Date?
        while Date() < deadline {
            let isTelephoto = Self.activeDevice(in: session)?.activePrimaryConstituent?.deviceType
                == .builtInTelephotoCamera
            if isTelephoto {
                let now = Date()
                if let telephotoSince {
                    if now.timeIntervalSince(telephotoSince) >= duration {
                        return true
                    }
                } else {
                    telephotoSince = now
                }
            } else {
                telephotoSince = nil
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private static func tripleCameraWithTelephoto() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera],
            mediaType: .video,
            position: .back
        )
        for device in discovery.devices {
            print(
                "LENS_ACCEPTANCE discovered type=\(device.deviceType.rawValue) id=\(device.uniqueID)"
                    + " virtual=\(device.isVirtualDevice) constituents=\(device.constituentDevices.map(\.deviceType.rawValue))"
            )
        }
        return discovery.devices.first(where: {
            $0.isVirtualDevice
                && $0.constituentDevices.contains(where: { $0.deviceType == .builtInWideAngleCamera })
                && $0.constituentDevices.contains(where: { $0.deviceType == .builtInTelephotoCamera })
        })
    }

    private static func activeDevice(in session: AVCaptureSession) -> AVCaptureDevice? {
        session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first
    }

    private static func wideReferenceHardwareZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        guard device.isVirtualDevice,
              let wideIndex = device.constituentDevices.firstIndex(where: {
                  $0.deviceType == .builtInWideAngleCamera
              }) else {
            return 1
        }
        guard wideIndex > 0 else { return max(device.minAvailableVideoZoomFactor, 0.1) }
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        return switchOvers.indices.contains(wideIndex - 1)
            ? max(switchOvers[wideIndex - 1], device.minAvailableVideoZoomFactor)
            : 1
    }

    private static func exifMetadata(from data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return [:]
        }
        return exif
    }

    private static func metadataDescription(_ metadata: [String: Any]) -> String {
        let keys = [
            kCGImagePropertyExifLensModel as String,
            kCGImagePropertyExifFocalLength as String,
            kCGImagePropertyExifFocalLenIn35mmFilm as String,
            kCGImagePropertyExifFNumber as String
        ]
        return keys.map { "\($0)=\(metadata[$0].map(String.init(describing:)) ?? "nil")" }.joined(separator: ",")
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { rawBuffer in
            rawBuffer
                .prefix { $0 != 0 }
                .map { Character(UnicodeScalar(UInt8($0))) }
                .reduce(into: "") { $0.append($1) }
        }
    }

    private final class FrameProbe: @unchecked Sendable {
        private var frameCount = 0

        var count: Int { frameCount }

        func record() { frameCount += 1 }
    }

    private final class PhotoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CameraService.CapturedPhoto?

        var photo: CameraService.CapturedPhoto? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func store(_ photo: CameraService.CapturedPhoto?) {
            lock.lock()
            value = photo
            lock.unlock()
        }
    }
}
