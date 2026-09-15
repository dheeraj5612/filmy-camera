import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class ProCaptureTests: XCTestCase {
    func testResolutionSelectionNeverUsesDeferredProxyOrUpscales() {
        let d12 = PhotoResolutionPolicy.Dimensions(width: 4032, height: 3024)
        let d24 = PhotoResolutionPolicy.Dimensions(width: 5712, height: 4284)
        let d48 = PhotoResolutionPolicy.Dimensions(width: 8064, height: 6048)
        XCTAssertEqual(PhotoResolutionPolicy.captureDimensions(for: .mp12, supported: [d48, d24, d12]), d12)
        XCTAssertEqual(PhotoResolutionPolicy.captureDimensions(for: .mp24, supported: [d24, d48]), d48)
        XCTAssertNil(PhotoResolutionPolicy.captureDimensions(for: .mp24, supported: [d12, d24]))
        XCTAssertEqual(PhotoResolutionPolicy.availableResolutions(supported: [d12]), [.mp12])
        XCTAssertEqual(PhotoResolutionPolicy.outputScale(sourcePixels: 8_000_000, resolution: .mp12), 1)
        XCTAssertLessThan(PhotoResolutionPolicy.outputScale(sourcePixels: Double(d48.pixels), resolution: .mp24), 1)
        XCTAssertEqual(PhotoResolutionPolicy.outputScale(sourcePixels: .nan, resolution: .mp24), 1)
    }

    func testAllCaptureCombinationsAreExplicitlyClassified() {
        for format in ProCaptureSettings.Format.allCases {
            for resolution in ProCaptureSettings.Resolution.allCases {
                for range in ProCaptureSettings.DynamicRange.allCases {
                    for live in [false, true] {
                        var settings = ProCaptureSettings()
                        settings.format = format
                        settings.resolution = resolution
                        settings.dynamicRange = range
                        settings.livePhoto = live
                        let invalid = (format == .jpeg && range == .hdr)
                            || (live && (format.retainsRAW || resolution != .mp12 || range == .hdr))
                        XCTAssertEqual(settings.incompatibility != nil, invalid)
                    }
                }
            }
        }
    }

    func testPreferencesRoundTripAndCorruptDataFallback() throws {
        var settings = ProCaptureSettings()
        settings.format = .proRAW
        settings.resolution = .mp48
        settings.dynamicRange = .hdr
        XCTAssertEqual(ProCaptureSettings.restored(from: try JSONEncoder().encode(settings)), settings)
        XCTAssertEqual(ProCaptureSettings.restored(from: Data("broken".utf8)), ProCaptureSettings())
        XCTAssertEqual(ProCaptureSettings.restored(from: nil), ProCaptureSettings())
    }

    func testMissingCapabilitiesDoNotSilentlyDowngradeRequests() {
        var capabilities = ProCaptureCapabilities()
        capabilities.resolutions = [.mp12]
        capabilities.formats = [.heif]
        var settings = ProCaptureSettings()
        XCTAssertNil(capabilities.unavailableReason(for: settings))
        settings.resolution = .mp48
        XCTAssertNotNil(capabilities.unavailableReason(for: settings))
        settings.resolution = .mp12
        settings.format = .proRAW
        XCTAssertNotNil(capabilities.unavailableReason(for: settings))
        XCTAssertFalse(capabilities.variableApertureSupported)
    }

    func testRAWAssemblyWaitsForBothCallbacksInEitherOrder() {
        var settings = ProCaptureSettings()
        settings.format = .proRAW
        for rawFirst in [false, true] {
            var capture = PhotoCaptureAssembly(uniqueID: 4, settings: settings)
            if rawFirst { capture.raw = Data([1]) } else { capture.processed = Data([2]) }
            XCTAssertFalse(capture.isComplete)
            capture.raw = Data([1])
            capture.processed = Data([2])
            XCTAssertTrue(capture.isComplete)
            capture.failed = true
            XCTAssertFalse(capture.isComplete)
        }
    }

    func testLiveAssemblyWaitsForMovieAndRejectsEmptyStill() {
        var settings = ProCaptureSettings()
        settings.livePhoto = true
        var capture = PhotoCaptureAssembly(uniqueID: 8, settings: settings)
        capture.processed = Data([2])
        XCTAssertFalse(capture.isComplete)
        capture.liveMovieURL = URL(fileURLWithPath: "/test.mov")
        XCTAssertTrue(capture.isComplete)
        capture.processed = Data()
        XCTAssertFalse(capture.isComplete)
    }

    func testFocusCoordinateTransformsRoundTripAcrossRotationsAndMirrors() {
        for angle: CGFloat in [0, 90, 180, 270] {
            for mirrored in [false, true] {
                let point = CGPoint(x: 0.17, y: 0.81)
                let display = CameraService.rotatedPreviewPoint(fromDevicePoint: point, rotationAngle: angle, mirrored: mirrored)
                let recovered = CameraService.captureDevicePoint(fromRotatedPreviewPoint: display, rotationAngle: angle, mirrored: mirrored)
                XCTAssertEqual(point.x, recovered.x, accuracy: 0.00001)
                XCTAssertEqual(point.y, recovered.y, accuracy: 0.00001)
            }
        }
    }

    func testLoupeIsClampedAtEachCornerAndRejectsInvalidExtent() {
        let extent = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        for x: CGFloat in [0, 0.5, 1] {
            for y: CGFloat in [0, 0.5, 1] {
                let crop = CameraService.loupeCrop(extent: extent, topLeftPoint: CGPoint(x: x, y: y))
                XCTAssertTrue(extent.contains(crop))
                XCTAssertEqual(crop.width, 270)
                XCTAssertEqual(crop.height, 270)
            }
        }
        XCTAssertEqual(CameraService.loupeCrop(extent: .zero, topLeftPoint: .zero), .zero)
    }

    func testTrackerUsesTappedSubjectRatherThanUnrelatedFace() {
        let face = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let body = CGRect(x: 0, y: 0, width: 0.6, height: 0.9)
        XCTAssertEqual(SubjectFocusTracker.seedRectangle(near: CGPoint(x: 0.2, y: 0.2), candidates: [body, face]), face)
        XCTAssertFalse(SubjectFocusTracker.isUsable(rectangle: face, confidence: 0.1))
        XCTAssertFalse(SubjectFocusTracker.isUsable(rectangle: .infinite, confidence: 1))
        let elsewhere = SubjectFocusTracker.seedRectangle(near: CGPoint(x: 0.9, y: 0.9), candidates: [face])
        XCTAssertTrue(elsewhere.contains(CGPoint(x: 0.9, y: 0.9)))
    }

    func testPersistentOriginalsSurviveReloadAndVersionChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let bytes = try fixture()
        var settings = ProCaptureSettings()
        settings.format = .jpeg
        let document = try await store.create(processed: bytes, raw: nil, liveMovieURL: nil, capturedAt: .distantPast,
            geometry: geometry, recipe: FilmRecipe.builtIns[0], finish: .photo, settings: settings)
        let first = try XCTUnwrap(document.currentRevision)
        let updated = try await store.addRevision(document.id, expectedRevisionID: first.id, recipe: FilmRecipe.builtIns[1],
            finish: .photo, settings: settings, renderedData: bytes)
        XCTAssertEqual(updated.revisions.count, 2)
        let reopened = FilmyPhotoStore(root: root)
        let original = try await reopened.originalData(document.id)
        XCTAssertEqual(original, bytes)
        let inventory = try await reopened.inventory()
        XCTAssertEqual(inventory.documents.count, 1)
        XCTAssertEqual(inventory.unreadableCount, 0)
        do {
            _ = try await store.addRevision(document.id, expectedRevisionID: first.id, recipe: FilmRecipe.builtIns[0],
                finish: .photo, settings: settings, renderedData: bytes)
            XCTFail("Stale edits must not overwrite the current version")
        } catch { XCTAssertTrue(error is FilmyPhotoStore.StoreError) }
        let originalAfterConflict = try await reopened.originalData(document.id)
        XCTAssertEqual(originalAfterConflict, bytes)
    }

    func testRAWAndLiveOriginalResourcesAreCopiedNotMoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: movie) }
        try Data([4, 5, 6]).write(to: movie)
        let store = FilmyPhotoStore(root: root)
        let bytes = try fixture()
        var rawSettings = ProCaptureSettings()
        rawSettings.format = .bayerRAW
        let rawDocument = try await store.create(processed: bytes, raw: Data([1, 2, 3]), liveMovieURL: nil,
            capturedAt: .distantPast, geometry: geometry, recipe: FilmRecipe.builtIns[0], finish: .photo, settings: rawSettings)
        let rawURL = try await store.originalURL(rawDocument.id, raw: true)
        XCTAssertEqual(try Data(contentsOf: rawURL), Data([1, 2, 3]))
        var liveSettings = ProCaptureSettings()
        liveSettings.livePhoto = true
        let liveDocument = try await store.create(processed: bytes, raw: nil, liveMovieURL: movie,
            capturedAt: .distantPast, geometry: geometry, recipe: FilmRecipe.builtIns[0], finish: .photo, settings: liveSettings)
        let retainedURL = try await store.liveMovieURL(liveDocument.id)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(retainedURL)), Data([4, 5, 6]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path))
    }

    func testIncompleteCaptureDoesNotPublishDocument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        var settings = ProCaptureSettings()
        settings.format = .proRAW
        do {
            _ = try await store.create(processed: fixture(), raw: nil, liveMovieURL: nil, capturedAt: .distantPast,
                geometry: geometry, recipe: FilmRecipe.builtIns[0], finish: .photo, settings: settings)
            XCTFail("A selected RAW original must be present")
        } catch { XCTAssertTrue(error is FilmyPhotoStore.StoreError) }
        let inventory = try await store.inventory()
        XCTAssertTrue(inventory.documents.isEmpty)
    }

    func testOutputProfilesAndMetadataMatchActualJPEGBytes() throws {
        var settings = ProCaptureSettings()
        settings.format = .jpeg
        settings.colorGamut = .displayP3
        let image = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        let data = try XCTUnwrap(ProPhotoOutput.encode(image, sourceData: Data(), capturedAt: .distantPast,
            recipe: FilmRecipe.builtIns[0], settings: settings))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 48)
        XCTAssertEqual(decoded.colorSpace?.name, CGColorSpace.displayP3)
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertNil(metadata[kCGImagePropertyGPSDictionary as String])
    }

    func testHDRHeadroomKernelProducesExtendedPixelsWithoutInventingSDRHighlights() throws {
        let extent = CGRect(x: 0, y: 0, width: 2, height: 2)
        let film = CIImage(color: CIColor(red: 0.9, green: 0.9, blue: 0.9)).cropped(to: extent)
        let sdr = CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.8)).cropped(to: extent)
        let hdr = CIImage(color: CIColor(red: 1.6, green: 1.6, blue: 1.6)).cropped(to: extent)
        let extended = try XCTUnwrap(ProPhotoOutput.preservingHeadroom(film: film, sourceSDR: sdr, sourceHDR: hdr))
        let standard = try XCTUnwrap(ProPhotoOutput.preservingHeadroom(film: film, sourceSDR: sdr, sourceHDR: sdr))
        XCTAssertGreaterThan(try firstChannel(extended), 1)
        XCTAssertEqual(try firstChannel(standard), 0.9, accuracy: 0.02)
    }

    private var geometry: FilmyRenderGeometry {
        .init(viewportWidth: 300, viewportHeight: 400, previewWidth: 600, previewHeight: 800, grainSeed: 7, flashFired: false)
    }

    private func fixture() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        return try XCTUnwrap(PhotoOutputEncoder.jpegData(for: XCTUnwrap(context.makeImage()), sourceData: Data(),
            capturedAt: .distantPast, recipe: FilmRecipe.builtIns[0]))
    }

    private func firstChannel(_ image: CIImage) throws -> Float {
        var pixels = [Float](repeating: 0, count: 16)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedSRGB))
        pixels.withUnsafeMutableBytes { buffer in
            ProPhotoOutput.context.render(image, toBitmap: buffer.baseAddress!, rowBytes: 32,
                bounds: CGRect(x: 0, y: 0, width: 2, height: 2), format: .RGBAf, colorSpace: space)
        }
        return pixels[0]
    }
}
