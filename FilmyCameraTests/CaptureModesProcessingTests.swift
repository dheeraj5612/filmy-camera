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
}
