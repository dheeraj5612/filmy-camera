import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class PhotoOutputEncoderTests: XCTestCase {
    func testJPEGUsesMeasuredHighQualityContractWithoutChangingDimensions() throws {
        let image = try detailedFixture(width: 320, height: 240)
        let output = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: image,
            sourceData: Data(),
            capturedAt: Date(timeIntervalSince1970: 0),
            recipe: FilmRecipe.builtIns[0]
        ))
        let outputSource = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [String: Any]
        )
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(outputSource, 0, nil))
        let highQualityReference = try encodedJPEG(image, quality: 0.95)
        let referenceSource = try XCTUnwrap(
            CGImageSourceCreateWithData(highQualityReference as CFData, nil)
        )
        let referenceDecoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(referenceSource, 0, nil))
        let defaultQuality = try encodedJPEG(image, quality: nil)
        let defaultQualitySource = try XCTUnwrap(
            CGImageSourceCreateWithData(defaultQuality as CFData, nil)
        )
        let defaultQualityDecoded = try XCTUnwrap(
            CGImageSourceCreateImageAtIndex(defaultQualitySource, 0, nil)
        )

        XCTAssertEqual(PhotoOutputEncoder.jpegCompressionQuality, 0.95)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue, image.width)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue, image.height)
        let referencePixels = try rgbaPixels(image)
        let outputPixels = try rgbaPixels(decoded)
        XCTAssertEqual(
            meanAbsoluteRGBError(try rgbaPixels(referenceDecoded), outputPixels), 0, accuracy: 0.01,
            "Finished exports must retain the detail of an independent explicit-quality 0.95 encode"
        )
        let outputError = meanAbsoluteRGBError(referencePixels, outputPixels)
        let defaultQualityError = meanAbsoluteRGBError(
            referencePixels,
            try rgbaPixels(defaultQualityDecoded)
        )
        // ImageIO's undocumented default can change across OS versions. Keep
        // its comparison as evidence, rather than a portable pass threshold.
        let measurement = XCTAttachment(string:
            "quality=0.95 bytes=\(output.count) RGB_MAE=\(outputError) "
                + "defaultBytes=\(defaultQuality.count) defaultRGB_MAE=\(defaultQualityError)")
        measurement.name = "JPEG-quality-detail-and-size"
        measurement.lifetime = .keepAlways
        add(measurement)
    }

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

    private func detailedFixture(width: Int, height: Int) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // Dense alternating edges plus small glyph-like strokes make JPEG
        // detail loss measurable without relying on a private photograph.
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let dark = ((x / 4) + (y / 4)).isMultiple(of: 2)
                context.setFillColor(CGColor(gray: dark ? 0.12 : 0.88, alpha: 1))
                context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 3, height: 3))
            }
        }
        context.setFillColor(CGColor(red: 0.08, green: 0.24, blue: 0.78, alpha: 1))
        for x in stride(from: 7, to: width, by: 23) {
            context.fill(CGRect(x: CGFloat(x), y: 11, width: 1, height: CGFloat(height - 22)))
        }
        context.setFillColor(CGColor(red: 0.82, green: 0.16, blue: 0.08, alpha: 1))
        for y in stride(from: 13, to: height, by: 29) {
            context.fill(CGRect(x: 17, y: CGFloat(y), width: CGFloat(width - 34), height: 1))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func encodedJPEG(_ image: CGImage, quality: Double?) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let properties = quality.map {
            [kCGImageDestinationLossyCompressionQuality as String: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            )
        }
        return pixels
    }

    private func meanAbsoluteRGBError(_ reference: [UInt8], _ candidate: [UInt8]) -> Double {
        guard reference.count == candidate.count, !reference.isEmpty else { return .infinity }
        var error = 0.0
        var samples = 0
        for offset in stride(from: 0, to: reference.count, by: 4) {
            for channel in 0..<3 {
                error += abs(Double(reference[offset + channel]) - Double(candidate[offset + channel]))
                samples += 1
            }
        }
        return error / Double(samples)
    }
}
