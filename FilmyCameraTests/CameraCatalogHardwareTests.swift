import XCTest
@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import ImageIO
import UIKit
@testable import FilmyCamera

/// Explicit, sequential physical-camera endurance acceptance. Each catalog
/// entry gets its own production shutter request and fresh sensor photograph.
/// Original files, full-resolution finished JPEGs, and a manifest remain in
/// xcresult attachments; this test never adds images to the user's Photos.
@MainActor
final class CameraCatalogHardwareTests: XCTestCase {
    func testEveryCatalogRecipeWithOverOneHundredDistinctHardwareCaptures() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Catalog shutter acceptance requires a physical camera")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_CAPTURE_SHEET"] == "1",
            "Set FILMY_RUN_CAPTURE_SHEET=1 for the explicit 128-shutter device lane"
        )
        try XCTSkipUnless(
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            "Authorize camera access before running the catalog shutter lane"
        )

        let originalIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = originalIdleTimer }
        try await eventually("The physical capture host must be foregrounded") {
            UIApplication.shared.applicationState == .active
        }

        let recipes = FilmRecipe.builtIns
        XCTAssertGreaterThan(recipes.count, 100)
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count)
        let camera = CameraService()
        let frames = FrameCounter()
        let frameHandler = camera.installFrameHandler { _ in frames.record() }
        let errors = ErrorLog()
        let observer = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: camera.session,
            queue: nil
        ) { note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            errors.append(error?.localizedDescription ?? "Unknown camera runtime error")
        }
        var observations: [CaptureObservation] = []
        var requestCount = 0
        let startedAt = Date()
        defer {
            camera.removeFrameHandler(frameHandler)
            camera.stop()
            NotificationCenter.default.removeObserver(observer)
            let manifest = CaptureManifest(
                requestedShutterCount: requestCount,
                deliveredAndEncodedCount: observations.count,
                expectedRecipeIDs: recipes.map(\.id),
                startedAt: startedAt,
                finishedAt: Date(),
                runtimeErrors: errors.values,
                captures: observations
            )
            if let data = try? Self.jsonEncoder.encode(manifest) {
                attach(data, name: "catalog-hardware-capture-manifest", type: "public.json")
            }
        }

        camera.start()
        try await eventually("Camera starts") { camera.availability == .running }
        try await eventually("Fresh sensor frames arrive before metering settles") { frames.count >= 3 }
        camera.resetManualControlsToAuto()
        camera.setFlashMode(.off)
        try await eventually("Automatic rear-camera exposure is ready") {
            camera.cameraPosition == .back && camera.flashMode == .off
                && !camera.manualControls.isAnyManualModeEnabled && !camera.manualControls.isApplying
        }
        // Give metering time to settle on the actual scene. Flash/manual/lens
        // permutations have dedicated device suites; this lane isolates looks.
        try await Task.sleep(for: .seconds(1.5))
        var sourceDigests = Set<String>()
        var captureTimes = Set<Date>()

        for (index, recipe) in recipes.enumerated() {
            try await eventually("Ready for shutter \(index + 1): \(recipe.id)") {
                camera.availability == .running && !camera.manualControls.isApplying
                    && UIApplication.shared.applicationState == .active
            }
            let shutterStartedAt = Date()
            let delivered = expectation(description: "Fresh shutter \(index + 1): \(recipe.id)")
            let box = PhotoBox()
            requestCount += 1
            camera.capturePhoto { photo in
                box.store(photo)
                delivered.fulfill()
            }
            await fulfillment(of: [delivered], timeout: 30)
            let photo = try XCTUnwrap(box.photo, "\(recipe.id): \(camera.statusMessage)")
            XCTAssertGreaterThanOrEqual(photo.capturedAt, shutterStartedAt,
                                        "A previous capture must never be reused")
            XCTAssertTrue(captureTimes.insert(photo.capturedAt).inserted,
                          "Each recipe requires a distinct shutter timestamp")
            let sourceDigest = Self.digest(photo.fileData)
            XCTAssertTrue(sourceDigests.insert(sourceDigest).inserted,
                          "Each recipe requires a fresh sensor file, not a rerender of one shot")

            let observation = try autoreleasepool {
                try validateAndAttach(photo, recipe: recipe, index: index + 1,
                                      sourceDigest: sourceDigest, shutterStartedAt: shutterStartedAt)
            }
            observations.append(observation)
            print("CATALOG_CAPTURE index=\(index + 1)/\(recipes.count) recipe=\(recipe.id) "
                  + "sourceSHA256=\(sourceDigest) dimensions=\(observation.outputWidth)x\(observation.outputHeight) "
                  + "sourceLuma=\(observation.sourceStatistics.meanLuminance) "
                  + "filteredLuma=\(observation.filteredStatistics.meanLuminance) "
                  + "seconds=\(observation.elapsedSeconds)")

            // Bound GPU resources during the unusually long, full-resolution
            // catalog session without reducing actual capture/render dimensions.
            FilmRenderer.sharedContext.clearCaches()
            try await Task.sleep(for: .milliseconds(150))
        }

        XCTAssertEqual(requestCount, recipes.count)
        XCTAssertEqual(observations.map(\.recipe.id), recipes.map(\.id))
        XCTAssertEqual(sourceDigests.count, recipes.count)
        XCTAssertEqual(captureTimes.count, recipes.count)
        XCTAssertTrue(errors.values.isEmpty, errors.values.joined(separator: "\n"))
        #endif
    }

    private func validateAndAttach(
        _ photo: CameraService.CapturedPhoto,
        recipe: FilmRecipe,
        index: Int,
        sourceDigest: String,
        shutterStartedAt: Date
    ) throws -> CaptureObservation {
        let label = String(format: "%03d-%@", index, recipe.id)
        attach(photo.fileData, name: "\(label)-sensor-original", type: "public.jpeg")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(photo.fileData as CFData, nil), label)
        let sourceProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any], label)
        let sourceWidth = try XCTUnwrap(sourceProperties[kCGImagePropertyPixelWidth as String] as? Int)
        let sourceHeight = try XCTUnwrap(sourceProperties[kCGImagePropertyPixelHeight as String] as? Int)
        XCTAssertEqual(sourceWidth, Int(photo.dimensions.width), label)
        XCTAssertEqual(sourceHeight, Int(photo.dimensions.height), label)
        XCTAssertGreaterThan(min(sourceWidth, sourceHeight), 1000, "Hardware still must retain sensor resolution")
        let decoded = try XCTUnwrap(CIImage(data: photo.fileData, options: [.applyOrientationProperty: true]), label)
        let input = decoded.transformed(by: CGAffineTransform(
            translationX: -decoded.extent.minX, y: -decoded.extent.minY))
        let sourceStatistics = Self.statistics(input)
        XCTAssertGreaterThan(sourceStatistics.meanLuminance, 0.003,
                             "\(label): scene is black; uncover the camera and provide a lit, textured scene")
        XCTAssertGreaterThan(sourceStatistics.maximumLuminance, 0.025,
                             "\(label): sensor photograph contains no useful lit detail")

        let faces = recipe.filmBase == .compactDigital
            ? FilmRenderer.portraitSubjectRegions(in: input) : []
        let rendered = FilmRenderer.render(input, recipe: recipe, quality: .photo,
                                          captureContext: .init(flashFired: photo.flashFired, subjectRegions: faces),
                                          grainSeed: UInt32(index))
        XCTAssertEqual(rendered.extent, input.extent, label)
        let bitmap = try XCTUnwrap(FilmRenderer.outputCGImage(rendered), label)
        XCTAssertEqual(bitmap.width, Int(input.extent.width), label)
        XCTAssertEqual(bitmap.height, Int(input.extent.height), label)
        let output = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: bitmap, sourceData: photo.fileData, capturedAt: photo.capturedAt, recipe: recipe), label)
        attach(output, name: "\(label)-filtered", type: "public.jpeg")
        let encoded = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil), label)
        let encodedProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [String: Any], label)
        XCTAssertEqual(encodedProperties[kCGImagePropertyPixelWidth as String] as? Int, bitmap.width, label)
        XCTAssertEqual(encodedProperties[kCGImagePropertyPixelHeight as String] as? Int, bitmap.height, label)
        XCTAssertEqual(encodedProperties[kCGImagePropertyOrientation as String] as? Int, 1, label)
        XCTAssertNil(encodedProperties[kCGImagePropertyGPSDictionary as String], label)
        let exif = try XCTUnwrap(encodedProperties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let comment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        let metadata = try JSONDecoder().decode(PhotoOutputEncoder.RecipeProvenanceMetadata.self,
                                               from: Data(comment.utf8))
        XCTAssertEqual(metadata.recipeID, recipe.id, label)
        XCTAssertEqual(metadata.filmBase, recipe.filmBase, label)
        XCTAssertEqual(metadata.rendererVersion, FilmRecipe.rendererVersion, label)
        let redecoded = try XCTUnwrap(CIImage(data: output), "Finished JPEG must decode: \(label)")
        let filteredStatistics = Self.statistics(redecoded)
        XCTAssertTrue(filteredStatistics.allFinite, label)
        XCTAssertGreaterThan(filteredStatistics.meanLuminance, 0.002, "\(label): renderer produced a black JPEG")
        XCTAssertGreaterThan(filteredStatistics.maximumLuminance, 0.02, "\(label): rendered photograph lost lit detail")

        let observation = CaptureObservation(
            ordinal: index, recipe: recipe, capturedAt: photo.capturedAt,
            sourceSHA256: sourceDigest, filteredSHA256: Self.digest(output),
            sourceBytes: photo.fileData.count, filteredBytes: output.count,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            outputWidth: bitmap.width, outputHeight: bitmap.height,
            flashFired: photo.flashFired, detectedSubjectCount: faces.count,
            sourceStatistics: sourceStatistics, filteredStatistics: filteredStatistics,
            elapsedSeconds: Date().timeIntervalSince(shutterStartedAt)
        )
        attach(try Self.jsonEncoder.encode(observation), name: "\(label)-capture-evidence", type: "public.json")
        return observation
    }

    private func attach(_ data: Data, name: String, type: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: type)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func statistics(_ image: CIImage) -> PixelStatistics {
        let bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        let sample = image.transformed(by: CGAffineTransform(
            scaleX: bounds.width / image.extent.width, y: bounds.height / image.extent.height))
        var pixels = [Float](repeating: 0, count: 64 * 64 * 4)
        FilmRenderer.sharedContext.render(sample, toBitmap: &pixels,
                                          rowBytes: 64 * 4 * MemoryLayout<Float>.size,
                                          bounds: bounds, format: .RGBAf,
                                          colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var sum: Double = 0
        var minimum: Double = 1
        var maximum: Double = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let luma = Double(pixels[offset]) * 0.2126 + Double(pixels[offset + 1]) * 0.7152
                + Double(pixels[offset + 2]) * 0.0722
            sum += luma
            minimum = min(minimum, luma)
            maximum = max(maximum, luma)
        }
        return PixelStatistics(meanLuminance: sum / 4096, minimumLuminance: minimum,
                               maximumLuminance: maximum, allFinite: pixels.allSatisfy(\.isFinite))
    }

    private func eventually(_ label: String, condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition(), "\(label); appState=\(UIApplication.shared.applicationState.rawValue), idleTimerDisabled=\(UIApplication.shared.isIdleTimerDisabled)")
        if !condition() { throw AcceptanceError.timeout }
    }

    private final class FrameCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func record() { lock.lock(); value += 1; lock.unlock() }
    }

    private enum AcceptanceError: Error { case timeout }
    private struct PixelStatistics: Codable {
        let meanLuminance: Double
        let minimumLuminance: Double
        let maximumLuminance: Double
        let allFinite: Bool
    }
    private struct CaptureObservation: Codable {
        let ordinal: Int
        let recipe: FilmRecipe
        let capturedAt: Date
        let sourceSHA256: String
        let filteredSHA256: String
        let sourceBytes: Int
        let filteredBytes: Int
        let sourceWidth: Int
        let sourceHeight: Int
        let outputWidth: Int
        let outputHeight: Int
        let flashFired: Bool
        let detectedSubjectCount: Int
        let sourceStatistics: PixelStatistics
        let filteredStatistics: PixelStatistics
        let elapsedSeconds: Double
    }
    private struct CaptureManifest: Codable {
        let requestedShutterCount: Int
        let deliveredAndEncodedCount: Int
        let expectedRecipeIDs: [String]
        let startedAt: Date
        let finishedAt: Date
        let runtimeErrors: [String]
        let captures: [CaptureObservation]
    }
    private final class PhotoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: CameraService.CapturedPhoto?
        var photo: CameraService.CapturedPhoto? { lock.withLock { stored } }
        func store(_ value: CameraService.CapturedPhoto?) { lock.withLock { stored = value } }
    }
    private final class ErrorLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var values: [String] { lock.withLock { stored } }
        func append(_ value: String) { lock.withLock { stored.append(value) } }
    }
}
