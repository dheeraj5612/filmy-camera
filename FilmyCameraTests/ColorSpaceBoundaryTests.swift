import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class ColorSpaceBoundaryTests: XCTestCase {
    func testRendererMaterializesWideGamutInputAsDisplayReferredSRGB() throws {
        let inputColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let sRGBColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let sourceComponents: [CGFloat] = [0.72, 0.38, 0.24, 1]
        let sourceColor = try XCTUnwrap(
            CGColor(colorSpace: inputColorSpace, components: sourceComponents)
        )
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: inputColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(sourceColor)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let input = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(try XCTUnwrap(input.colorSpace).model, .rgb)

        let neutralRecipe = FilmRecipe(
            id: "color-space-neutral",
            name: "Color space neutral",
            subtitle: "Test"
        )
        let rendered = FilmRenderer.render(
            CIImage(cgImage: input),
            recipe: neutralRecipe,
            quality: .photo
        )
        let output = try XCTUnwrap(FilmRenderer.outputCGImage(rendered))
        let materializedColorSpace = try XCTUnwrap(output.colorSpace)
        let expectedColor = try XCTUnwrap(
            sourceColor.converted(
                to: sRGBColorSpace,
                intent: .relativeColorimetric,
                options: nil
            )
        )
        let expectedComponents = try XCTUnwrap(expectedColor.components)

        var outputPixel = [Float](repeating: 0, count: 4)
        outputPixel.withUnsafeMutableBytes { bytes in
            CIContext(options: FilmRenderer.testContextOptions).render(
                CIImage(cgImage: output),
                toBitmap: bytes.baseAddress!,
                rowBytes: 4 * MemoryLayout<Float>.stride,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf,
                colorSpace: sRGBColorSpace
            )
        }

        XCTAssertEqual(materializedColorSpace.model, .rgb)
        XCTAssertEqual(materializedColorSpace.name, sRGBColorSpace.name)
        XCTAssertEqual(output.width, 2)
        XCTAssertEqual(output.height, 2)
        XCTAssertGreaterThan(
            abs(expectedComponents[0] - sourceComponents[0]),
            0.03,
            "The fixture must distinguish color conversion from relabeling P3 values as sRGB"
        )
        for channel in 0..<3 {
            XCTAssertEqual(
                CGFloat(outputPixel[channel]),
                expectedComponents[channel],
                accuracy: 0.015,
                "P3 to sRGB conversion drifted in channel \(channel)"
            )
        }
    }

    // These are real multi-component tests: Core Image -> finish compositor ->
    // materialized sRGB pixels -> ImageIO JPEG -> decoder, without Photos access.
    func testNeutralSRGBColorSurvivesTheFinishedJPEGRoundTrip() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let samples: [[CGFloat]] = [[0.12, 0.36, 0.68, 1], [0.72, 0.38, 0.24, 1], [0.5, 0.5, 0.5, 1]]
        for components in samples {
            let color = try XCTUnwrap(CGColor(colorSpace: colorSpace, components: components))
            let source = CIImage(color: CIColor(cgColor: color)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
            let data = try pipelineExport(source, recipe: neutralExportRecipe)
            let (decoded, _) = try readExport(data)
            let pixel = try exportPixel(decoded, x: 32, y: 24)
            for channel in 0..<3 {
                XCTAssertEqual(pixel[channel], components[channel], accuracy: 0.025, "channel=\(channel)")
            }
        }
    }

    func testP3ConversionIsStillCorrectAfterJPEGEncodingAndDecoding() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let color = try XCTUnwrap(CGColor(colorSpace: p3, components: [0.72, 0.38, 0.24, 1]))
        let expected = try XCTUnwrap(color.converted(to: sRGB, intent: .relativeColorimetric, options: nil)?.components)
        let source = CIImage(color: CIColor(cgColor: color)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let (decoded, _) = try readExport(pipelineExport(source, recipe: neutralExportRecipe))
        let actual = try exportPixel(decoded, x: 32, y: 32)
        XCTAssertGreaterThan(abs(expected[0] - 0.72), 0.03, "Fixture must expose profile relabeling")
        for channel in 0..<3 { XCTAssertEqual(actual[channel], expected[channel], accuracy: 0.025) }
    }

    func testEveryAspectAndFinishExportsTruthfulCanvasAndExifDimensions() throws {
        for size in [CGSize(width: 96, height: 64), CGSize(width: 64, height: 96),
                     CGSize(width: 64, height: 64), CGSize(width: 128, height: 72)] {
            let source = exportFixture(size: size)
            for finish in PhotoFinish.allCases {
                let layout = try XCTUnwrap(PhotoPrintCompositor.layout(for: source.extent, finish: finish))
                let (decoded, properties) = try readExport(pipelineExport(source, recipe: neutralExportRecipe, finish: finish))
                let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
                XCTAssertEqual(decoded.width, Int(layout.canvasExtent.width))
                XCTAssertEqual(decoded.height, Int(layout.canvasExtent.height))
                XCTAssertEqual(exif[kCGImagePropertyExifPixelXDimension as String] as? Int, decoded.width)
                XCTAssertEqual(exif[kCGImagePropertyExifPixelYDimension as String] as? Int, decoded.height)
                XCTAssertEqual(ReviewComparisonGeometry.supportsSplit(
                    original: size, edited: CGSize(width: decoded.width, height: decoded.height), finish: finish), finish == .photo)
            }
        }
    }

    func testInstantPrintPaperAndImageRemainDistinctAfterJPEGCompression() throws {
        let source = exportFixture(size: CGSize(width: 128, height: 96))
        let layout = try XCTUnwrap(PhotoPrintCompositor.layout(for: source.extent, finish: .instantPrint))
        let (decoded, _) = try readExport(pipelineExport(source, recipe: neutralExportRecipe, finish: .instantPrint))
        let paper = try exportPixel(decoded, x: decoded.width / 2, y: Int(layout.bottomMargin / 2))
        let center = try exportPixel(decoded, x: Int(layout.imageFrame.midX), y: Int(layout.imageFrame.midY))
        for channel in 0..<3 { XCTAssertEqual(paper[channel], 0.98, accuracy: 0.035) }
        XCTAssertGreaterThan(paper[0] - center[0], 0.5, "Print border must not replace the photograph")
        XCTAssertGreaterThan(center[2] - center[0], 0.3, "Photograph must retain the fixture's blue color")
    }

    func testTransparentInstantPrintIsFlattenedAgainstPaperBeforeEncoding() throws {
        let source = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        let (decoded, _) = try readExport(pipelineExport(source, recipe: neutralExportRecipe, finish: .instantPrint))
        let center = try exportPixel(decoded, x: decoded.width / 2, y: decoded.height / 2)
        for channel in 0..<3 { XCTAssertEqual(center[channel], 0.98, accuracy: 0.035) }
        XCTAssertEqual(center[3], 1, accuracy: 0.001)
    }

    func testOffsetCropDoesNotExportTheUncroppedSourceDimensions() throws {
        let crop = CGRect(x: 31, y: -47, width: 79, height: 53)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7)).cropped(to: crop)
        let (decoded, properties) = try readExport(pipelineExport(source, recipe: neutralExportRecipe))
        XCTAssertEqual(decoded.width, 79)
        XCTAssertEqual(decoded.height, 53)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 79)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 53)
    }

    func testRepresentativeColorAndMonochromeRecipesKeepTheirOwnProvenance() throws {
        for id in ["g7x-compact", "provia-standard", "classic-chrome", "acros-neutral-filter"] {
            let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == id }, "Required recipe missing: \(id)")
            for finish in PhotoFinish.allCases {
                let data = try pipelineExport(exportFixture(), recipe: recipe, finish: finish)
                let metadata = try exportProvenance(data)
                XCTAssertEqual(metadata, PhotoOutputEncoder.RecipeProvenanceMetadata(
                    recipe: recipe, appVersion: "test-version", appBuild: "test-build"))
                _ = try readExport(data)
            }
        }
    }

    func testMalformedCaptureMetadataCannotPreventAnOtherwiseValidExport() throws {
        for sourceData in [Data(), Data([0xff, 0xd8, 0xff]), Data("not an image".utf8)] {
            let data = try pipelineExport(exportFixture(), recipe: neutralExportRecipe, sourceData: sourceData)
            let (_, properties) = try readExport(data)
            let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
            XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "1970:01:01 00:00:00")
            XCTAssertEqual(exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String, "+00:00")
            XCTAssertEqual(try exportProvenance(data).recipeID, neutralExportRecipe.id)
        }
    }

    func testPrivateSourceMetadataDoesNotCrossTheCompleteExportPipeline() throws {
        let source = exportFixture()
        let pixels = try XCTUnwrap(FilmRenderer.outputCGImage(source))
        let metadata: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: ["Latitude": 40.7, "LatitudeRef": "N", "Longitude": 74.0, "LongitudeRef": "W"],
            kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFArtist as String: "PRIVATE-OWNER",
                                                       kCGImagePropertyTIFFMake as String: "PRIVATE-CAMERA"],
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifUserComment as String: "PRIVATE-COMMENT",
                                                       kCGImagePropertyExifExposureTime as String: 0.008,
                                                       kCGImagePropertyExifISOSpeedRatings as String: [400]]
        ]
        let sourceData = try metadataJPEG(pixels, properties: metadata)
        let (_, sourceProperties) = try readExport(sourceData, requireOutputContract: false)
        let sourceTIFF = try XCTUnwrap(sourceProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        XCTAssertEqual(sourceTIFF[kCGImagePropertyTIFFArtist as String] as? String, "PRIVATE-OWNER")
        XCTAssertNotNil(sourceProperties[kCGImagePropertyGPSDictionary as String], "Fixture must actually contain GPS")
        let sourceExif = try XCTUnwrap(sourceProperties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(sourceExif[kCGImagePropertyExifUserComment as String] as? String, "PRIVATE-COMMENT")
        let data = try pipelineExport(source, recipe: neutralExportRecipe, finish: .instantPrint, sourceData: sourceData)
        let (_, output) = try readExport(data)
        XCTAssertNil(output[kCGImagePropertyGPSDictionary as String])
        let tiff = try XCTUnwrap(output[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        XCTAssertNil(tiff[kCGImagePropertyTIFFArtist as String])
        XCTAssertNil(tiff[kCGImagePropertyTIFFMake as String])
        let exif = try XCTUnwrap(output[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(exif[kCGImagePropertyExifExposureTime as String] as? Double), 0.008, accuracy: 0.00001)
        XCTAssertEqual(exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], [400])
        XCTAssertEqual(try exportProvenance(data).recipeID, neutralExportRecipe.id)
        XCTAssertFalse((exif[kCGImagePropertyExifUserComment as String] as? String ?? "").contains("PRIVATE-"))
    }

    func testReimportAndReexportReplacePriorRecipeMetadataWithoutDoubleRotation() throws {
        let first = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "classic-chrome" })
        let second = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let original = try pipelineExport(exportFixture(size: CGSize(width: 48, height: 64)), recipe: first)
        let (decoded, _) = try readExport(original)
        let updated = try pipelineExport(CIImage(cgImage: decoded), recipe: second, finish: .instantPrint, sourceData: original)
        let (reimported, properties) = try readExport(updated)
        let expected = try XCTUnwrap(PhotoPrintCompositor.layout(for: CGRect(x: 0, y: 0, width: 48, height: 64), finish: .instantPrint))
        XCTAssertEqual(reimported.width, Int(expected.canvasExtent.width))
        XCTAssertEqual(reimported.height, Int(expected.canvasExtent.height))
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
        XCTAssertEqual(try exportProvenance(original).recipeID, first.id, "Existing exported bytes must remain unchanged")
        XCTAssertEqual(try exportProvenance(updated).recipeID, second.id)
    }

    func testSourceOrientationMetadataCannotRotateAlreadyFinishedPixelsAgain() throws {
        let source = exportFixture(size: CGSize(width: 48, height: 64))
        let pixels = try XCTUnwrap(FilmRenderer.outputCGImage(source))
        for orientation in 1...8 {
            let capture = try metadataJPEG(pixels, properties: [kCGImagePropertyOrientation as String: orientation])
            let (output, properties) = try readExport(pipelineExport(source, recipe: neutralExportRecipe, sourceData: capture))
            XCTAssertEqual(output.width, 48, "orientation=\(orientation)")
            XCTAssertEqual(output.height, 64, "orientation=\(orientation)")
            XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
        }
    }

    func testFinishedPhotoSurvivesAtomicDiskWriteReloadAndProvenanceDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FilmyExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("owned-fixture.jpg")
        let data = try pipelineExport(exportFixture(), recipe: neutralExportRecipe, finish: .instantPrint)
        try data.write(to: url, options: .atomic)
        let reloaded = try Data(contentsOf: url)
        XCTAssertEqual(reloaded, data)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(try exportProvenance(reloaded).recipeID, neutralExportRecipe.id)
    }

    func testLegacyProvenanceDefaultsOnlyTheOptionalAppVersionFields() throws {
        let data = try pipelineExport(exportFixture(), recipe: neutralExportRecipe)
        let metadata = try exportProvenance(data)
        let encoded = try JSONEncoder().encode(metadata)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "appVersion")
        legacy.removeValue(forKey: "appBuild")
        let decoded = try JSONDecoder().decode(PhotoOutputEncoder.RecipeProvenanceMetadata.self,
                                               from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.appVersion, "unknown")
        XCTAssertEqual(decoded.appBuild, "unknown")
        XCTAssertEqual(decoded.provenance, metadata.provenance)
        XCTAssertEqual(decoded.recipeID, metadata.recipeID)
        for required in ["format", "metadataVersion", "recipeID", "recipeName", "filmBase", "recipeSchemaVersion", "rendererVersion", "provenance"] {
            var malformed = legacy
            malformed.removeValue(forKey: required)
            let payload = try JSONSerialization.data(withJSONObject: malformed)
            XCTAssertThrowsError(try JSONDecoder().decode(PhotoOutputEncoder.RecipeProvenanceMetadata.self, from: payload), required)
        }
    }

    private var neutralExportRecipe: FilmRecipe {
        FilmRecipe(id: "pipeline-neutral", name: "Pipeline neutral", subtitle: "Owned synthetic fixture")
    }

    private func exportFixture(size: CGSize = CGSize(width: 64, height: 48)) -> CIImage {
        CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func pipelineExport(_ input: CIImage, recipe: FilmRecipe, finish: PhotoFinish = .photo,
                                sourceData: Data = Data()) throws -> Data {
        let rendered = FilmRenderer.render(input, recipe: recipe, quality: .photo)
        let finished = try XCTUnwrap(PhotoPrintCompositor.composedImage(rendered, finish: finish))
        let output = try XCTUnwrap(FilmRenderer.outputCGImage(finished))
        return try XCTUnwrap(PhotoOutputEncoder.jpegData(for: output, sourceData: sourceData,
            capturedAt: Date(timeIntervalSince1970: 0), recipe: recipe, appVersion: "test-version", appBuild: "test-build"))
    }

    private func readExport(_ data: Data, requireOutputContract: Bool = true) throws -> (CGImage, [String: Any]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        if requireOutputContract {
            XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
            XCTAssertEqual(properties[kCGImagePropertyProfileName as String] as? String, PhotoOutputEncoder.outputProfileName)
            let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
            XCTAssertEqual(exif[kCGImagePropertyExifColorSpace as String] as? Int, 1)
        }
        return (image, properties)
    }

    private func exportProvenance(_ data: Data) throws -> PhotoOutputEncoder.RecipeProvenanceMetadata {
        let (_, properties) = try readExport(data)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let comment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        return try JSONDecoder().decode(PhotoOutputEncoder.RecipeProvenanceMetadata.self, from: Data(comment.utf8))
    }

    private func exportPixel(_ image: CGImage, x: Int, y: Int) throws -> [CGFloat] {
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            CIContext(options: FilmRenderer.testContextOptions).render(CIImage(cgImage: image), toBitmap: bytes.baseAddress!,
                rowBytes: 4 * MemoryLayout<Float>.stride, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: sRGB)
        }
        return pixel.map { CGFloat($0) }
    }

    private func metadataJPEG(_ image: CGImage, properties: [String: Any]) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

}
