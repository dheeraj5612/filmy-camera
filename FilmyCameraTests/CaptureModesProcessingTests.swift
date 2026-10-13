import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class CaptureModesProcessingTests: XCTestCase {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let width = 128, height = 96
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        // Deterministic, asymmetric texture gives Vision more than a constant field.
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = UInt8((x * 13 + y * 7) % 220 + 20)
                pixels[index + 1] = UInt8((x * 3 + y * 19) % 220 + 20)
                pixels[index + 2] = UInt8((x * 11 + y * 5) % 220 + 20)
            }
        }
        let data = Data(pixels)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testThumbnailBoundsAndReferencePreparation() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let thumbnail = try CaptureImageProcessor.thumbnail(url, maximum: 64)
        XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), 64)
        let reference = try CaptureReference.prepare(Data(contentsOf: url))
        XCTAssertGreaterThan(reference.jpeg.count, 0)
        XCTAssertEqual(reference.image.width, 128)
        XCTAssertEqual(reference.image.height, 96)
    }

    func testInvalidImageFailsInsteadOfCreatingAPlaceholder() {
        XCTAssertThrowsError(try CaptureReference.prepare(Data([0, 1, 2, 3])))
    }

    /// The 128x96 texture as a JPEG carrying an EXIF orientation tag (PNG orientation support is unreliable).
    private func taggedFixture(orientation: Int) throws -> URL {
        let png = try fixture()
        defer { try? FileManager.default.removeItem(at: png) }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation,
                                                        kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testFusionNeedsThreeFrames() {
        XCTAssertThrowsError(try CaptureImageProcessor.fuseNight([]))
        XCTAssertThrowsError(try CaptureImageProcessor.stitchPanorama([]))
    }

    func testNightIdentityRegistrationKeepsFiniteUsefulBounds() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try CaptureImageProcessor.fuseNight([url, url, url])
        XCTAssertEqual(result.accepted, 3)
        XCTAssertGreaterThan(result.image.extent.width, 120)
        XCTAssertGreaterThan(result.image.extent.height, 88)
        XCTAssertLessThanOrEqual(result.image.extent.width, 128)
        XCTAssertLessThanOrEqual(result.image.extent.height, 96)
        XCTAssertEqual(result.image.extent.minX, 0)
        XCTAssertEqual(result.image.extent.minY, 0)
    }

    func testNightBakesTheOrientationTagUpright() throws {
        let portrait = try (0..<3).map { _ in try taggedFixture(orientation: 6) }
        let landscape = try (0..<3).map { _ in try taggedFixture(orientation: 1) }
        defer { (portrait + landscape).forEach { try? FileManager.default.removeItem(at: $0) } }
        let upright = try CaptureImageProcessor.fuseNight(portrait)
        XCTAssertEqual(upright.accepted, 3)
        XCTAssertGreaterThan(upright.image.extent.width, 88)
        XCTAssertLessThanOrEqual(upright.image.extent.width, 96)
        XCTAssertGreaterThan(upright.image.extent.height, 120)
        XCTAssertLessThanOrEqual(upright.image.extent.height, 128)
        let flat = try CaptureImageProcessor.fuseNight(landscape)
        XCTAssertGreaterThan(flat.image.extent.width, 120)
        XCTAssertLessThanOrEqual(flat.image.extent.width, 128)
        XCTAssertGreaterThan(flat.image.extent.height, 88)
        XCTAssertLessThanOrEqual(flat.image.extent.height, 96)
    }

    func testNightDropsFramesWhoseTagChangedMidSequence() throws {
        let flat = try taggedFixture(orientation: 1)
        let upright = try taggedFixture(orientation: 6)
        defer { [flat, upright].forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertThrowsError(try CaptureImageProcessor.fuseNight([flat, upright, flat])) { error in
            guard case CaptureModesError.insufficientFrames(let accepted) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(accepted, 2)
        }
    }

    func testStillEncodeKeepsSourceTagAndPixelSize() throws {
        let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        try XCTSkipUnless(types.contains(UTType.heic.identifier), "HEIC encoding is unavailable")
        let source = try taggedFixture(orientation: 6)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".heic")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        let image = try XCTUnwrap(CIImage(contentsOf: source, options: [.applyOrientationProperty: false]))
        XCTAssertEqual(image.extent.width, 128)
        XCTAssertEqual(image.extent.height, 96)
        try CaptureImageProcessor.encode(image, to: output, metadataSource: source)
        let result = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(result, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 128)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 96)
    }

    func testPanoramaDoesNotPretendRepeatedStillFramesAreASweep() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try CaptureImageProcessor.stitchPanorama([url, url, url]))
    }

    func testMediaStorePreventsTraversalAndKeepsRecipeIndependentFromExport() throws {
        let id = UUID()
        defer { try? CaptureMediaStore.delete(id) }
        XCTAssertThrowsError(try CaptureMediaStore.file("../escape", in: id))
        var media = CaptureMedia(id: id, mode: .portrait, createdAt: Date(), recipeName: "Test")
        media.originals = ["original-000.heic"]
        try CaptureMediaStore.persist(media)
        XCTAssertEqual(try CaptureMediaStore.load(id).status, .originalsOnly)
        media.outputs = ["filmy-000.heic"]
        media.status = .ready
        try CaptureMediaStore.persist(media)
        XCTAssertEqual(try CaptureMediaStore.load(id).originals, ["original-000.heic"])
    }

    func testReadPathsDoNotResurrectADeletedCaptureFolder() throws {
        let id = UUID()
        let media = CaptureMedia(id: id, mode: .photo, createdAt: Date(), recipeName: "Test")
        try CaptureMediaStore.persist(media)
        try CaptureMediaStore.delete(id)
        XCTAssertThrowsError(try CaptureMediaStore.recoverableOriginals(media))
        XCTAssertThrowsError(try CaptureMediaStore.load(id))
        XCTAssertThrowsError(try CaptureMediaStore.loadRecipe(in: id))
        XCTAssertNoThrow(try CaptureMediaStore.delete(id))
        let folder = try CaptureMediaStore.root().appendingPathComponent(id.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testRecoverableOriginalsSkipsEmptyAndNonOriginalFilesInNameOrder() throws {
        let id = UUID()
        defer { try? CaptureMediaStore.delete(id) }
        let bytes = Data([1, 2, 3])
        try bytes.write(to: CaptureMediaStore.file("original-001.heic", in: id))
        try bytes.write(to: CaptureMediaStore.file("original-000.heic", in: id))
        try bytes.write(to: CaptureMediaStore.file("filmy-000.heic", in: id))
        try Data().write(to: CaptureMediaStore.file("original-002.heic", in: id))
        let media = CaptureMedia(id: id, mode: .burst, createdAt: Date(), recipeName: "Test")
        let names = try CaptureMediaStore.recoverableOriginals(media).map(\.lastPathComponent)
        XCTAssertEqual(names, ["original-000.heic", "original-001.heic"])
    }

    func testRecentToleratesADamagedSiblingManifest() throws {
        let good = UUID()
        let bad = UUID()
        defer { try? CaptureMediaStore.delete(good); try? CaptureMediaStore.delete(bad) }
        try CaptureMediaStore.persist(CaptureMedia(id: good, mode: .photo, createdAt: Date(), recipeName: "Test"))
        try Data("not json".utf8).write(to: CaptureMediaStore.file("capture.json", in: bad))
        let ids = try CaptureMediaStore.recent().map(\.id)
        XCTAssertTrue(ids.contains(good))
        XCTAssertFalse(ids.contains(bad))
    }

    func testRecipeSidecarRoundTrips() throws {
        let id = UUID()
        defer { try? CaptureMediaStore.delete(id) }
        let recipe = FilmRecipe.builtIns[0]
        try CaptureMediaStore.saveRecipe(recipe, in: id)
        let loaded = try CaptureMediaStore.loadRecipe(in: id)
        XCTAssertEqual(loaded.id, recipe.id)
        XCTAssertEqual(loaded.name, recipe.name)
    }

    func testUnfinalizedMoviesAreNotPromotedToDevelopedOrSpatial() async throws {
        for mode in [CaptureMode.filmVideo, .spatialVideo] {
            let id = UUID()
            defer { try? CaptureMediaStore.delete(id) }
            var media = CaptureMedia(id: id, mode: mode, createdAt: Date(), recipeName: "Test")
            media.originals = ["original-video.mov"]
            let url = try CaptureMediaStore.file("original-video.mov", in: id)
            try Data([0, 1, 2, 3]).write(to: url)
            try CaptureMediaStore.persist(media)
            do {
                _ = try await CaptureImageProcessor.process(media, recipe: FilmRecipe.builtIns[0])
                XCTFail("An unfinished movie must not become a developed capture")
            } catch {
                XCTAssertEqual(try CaptureMediaStore.load(id).status, .originalsOnly)
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    func testMovieRecoverabilityRequiresFileAndPlayableVideo() {
        func ok(size: Int64 = 10, playable: Bool = true, video: Bool = true, seconds: Double = 1) -> Bool {
            CaptureModesEngine.isRecoverableMovie(fileSize: size, isPlayable: playable,
                                                  hasVideoTrack: video, durationSeconds: seconds)
        }
        XCTAssertTrue(ok())
        XCTAssertFalse(ok(size: 0))
        XCTAssertFalse(ok(playable: false))
        XCTAssertFalse(ok(video: false))
        XCTAssertFalse(ok(seconds: 0))
        XCTAssertFalse(ok(seconds: .nan))
    }
}
