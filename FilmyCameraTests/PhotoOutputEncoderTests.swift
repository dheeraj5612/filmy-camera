import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class PhotoOutputEncoderTests: XCTestCase {
    func testFilteredJPEGKeepsCaptureProvenanceAndStripsGPS() throws {
        let recipe = FilmRecipe.builtIns[3]
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 4,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.76, green: 0.36, blue: 0.18, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let image = try XCTUnwrap(context.makeImage())

        let sourceData = NSMutableData()
        let sourceDestination = try XCTUnwrap(CGImageDestinationCreateWithData(
            sourceData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let sourceProperties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 41.88,
                kCGImagePropertyGPSLongitude as String: -87.63
            ],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFArtist as String: "source-artist-should-not-leak"
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifLensModel as String: "source-lens-should-not-leak"
            ],
            kCGImagePropertyMakerAppleDictionary as String: [
                "source-device-field": "source-maker-apple-should-not-leak"
            ]
        ]
        CGImageDestinationAddImage(sourceDestination, image, sourceProperties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sourceDestination))

        let capturedAt = Date(timeIntervalSince1970: 1_786_557_600)
        let output = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: image,
            sourceData: sourceData as Data,
            capturedAt: capturedAt,
            recipe: recipe
        ))
        let outputSource = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [String: Any]
        )
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])

        XCTAssertEqual(tiff[kCGImagePropertyTIFFSoftware as String] as? String, "Filmy Camera")
        XCTAssertEqual(
            tiff[kCGImagePropertyTIFFImageDescription as String] as? String,
            "Filmy Camera • \(recipe.name)"
        )
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2026:08:12 18:00:00")
        XCTAssertEqual((exif[kCGImagePropertyExifPixelXDimension as String] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((exif[kCGImagePropertyExifPixelYDimension as String] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((exif[kCGImagePropertyExifColorSpace as String] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(properties[kCGImagePropertyColorModel as String] as? String, kCGImagePropertyColorModelRGB as String)
        XCTAssertEqual(properties[kCGImagePropertyProfileName as String] as? String, PhotoOutputEncoder.outputProfileName)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertNil(tiff[kCGImagePropertyTIFFArtist as String])
        XCTAssertNil(exif[kCGImagePropertyExifLensModel as String])
        XCTAssertNil(properties[kCGImagePropertyMakerAppleDictionary as String])
        XCTAssertEqual(CGImageSourceGetType(outputSource) as String?, UTType.jpeg.identifier)

        let userComment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        let userCommentData = try XCTUnwrap(userComment.data(using: .utf8))
        let metadata = try JSONDecoder().decode(
            PhotoOutputEncoder.RecipeProvenanceMetadata.self,
            from: userCommentData
        )
        XCTAssertEqual(metadata.format, PhotoOutputEncoder.recipeMetadataFormat)
        XCTAssertEqual(metadata.metadataVersion, 1)
        XCTAssertEqual(metadata.recipeID, recipe.id)
        XCTAssertEqual(metadata.recipeName, recipe.name)
        XCTAssertEqual(metadata.filmBase, recipe.filmBase)
        XCTAssertEqual(metadata.recipeSchemaVersion, recipe.schemaVersion)
        XCTAssertEqual(metadata.rendererVersion, recipe.provenance.rendererVersion)
        XCTAssertEqual(metadata.provenance, recipe.provenance)
    }

    func testJPEGProvenancePreservesUserModifiedDisclosure() throws {
        var recipe = FilmRecipe.builtIns[0]
        recipe.markUserModified(parentRecipeID: recipe.id)

        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let output = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: image,
            sourceData: try sourceJPEG(for: image),
            capturedAt: Date(timeIntervalSince1970: 0),
            recipe: recipe
        ))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let comment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        let data = try XCTUnwrap(comment.data(using: .utf8))
        let metadata = try JSONDecoder().decode(PhotoOutputEncoder.RecipeProvenanceMetadata.self, from: data)

        XCTAssertEqual(metadata.provenance.source, .userModified)
        XCTAssertEqual(metadata.provenance.parentRecipeID, recipe.id)
        XCTAssertEqual(metadata.provenance.calibration, .notCalibratedToFujifilmHardware)
    }

    func testJPEGProvenancePreservesG7XCanonBoundary() throws {
        var recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        recipe.markUserModified(parentRecipeID: recipe.id)

        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let output = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: image,
            sourceData: try sourceJPEG(for: image),
            capturedAt: Date(timeIntervalSince1970: 0),
            recipe: recipe
        ))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let comment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        let data = try XCTUnwrap(comment.data(using: .utf8))
        let metadata = try JSONDecoder().decode(PhotoOutputEncoder.RecipeProvenanceMetadata.self, from: data)

        XCTAssertEqual(metadata.recipeID, "g7x-compact")
        XCTAssertEqual(metadata.filmBase, .compactDigital)
        XCTAssertEqual(metadata.provenance.source, .userModified)
        XCTAssertEqual(metadata.provenance.calibration, .notCalibratedToCanonHardware)
        XCTAssertEqual(metadata.provenance.references, FilmRecipe.g7XPublicReferences)
        XCTAssertTrue(metadata.provenance.isComplete)
    }

    private func sourceJPEG(for image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
