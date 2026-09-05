import CoreGraphics
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class CameraViewModelRenderingTests: XCTestCase {
    private var defaultsSuites: [(defaults: UserDefaults, name: String)] = []

    override func tearDown() {
        for suite in defaultsSuites {
            suite.defaults.removePersistentDomain(forName: suite.name)
        }
        defaultsSuites.removeAll()
        super.tearDown()
    }

    @MainActor
    func testCancelledImportDoesNotPublishReviewOrErrorAndCanBeRetried() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        let data = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
        let model = try makeViewModel()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.importPhoto(data: data)
        }
        await task.value
        XCTAssertNil(model.reviewImage)
        XCTAssertNil(model.toastMessage)
        XCTAssertFalse(model.isImporting)
        await model.importPhoto(data: data)
        XCTAssertNotNil(model.reviewImage)
    }

    @MainActor
    func testImportedPhotoKeepsItsFramingAndSelectedRecipe() async throws {
        let sourceSize = CGSize(width: 80, height: 40)
        let image = UIGraphicsImageRenderer(size: sourceSize).image { context in
            UIColor(red: 0.72, green: 0.28, blue: 0.16, alpha: 1).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: sourceSize))
        }
        let sourceData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let viewModel = try makeViewModel()
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first(where: { $0.id == "classic-chrome" }))
        viewModel.select(recipe: recipe)

        await viewModel.importPhoto(data: sourceData)

        let reviewImage = try XCTUnwrap(viewModel.reviewImage)
        XCTAssertEqual(reviewImage.size.width / reviewImage.size.height, 2, accuracy: 0.01)
        XCTAssertEqual(viewModel.reviewRecipe?.id, recipe.id)
        XCTAssertEqual(viewModel.reviewSource, .photoLibrary)
        XCTAssertFalse(viewModel.isImporting)
    }

    @MainActor
    func testInvalidImportedPhotoDoesNotCreateAReview() async throws {
        let viewModel = try makeViewModel()

        await viewModel.importPhoto(data: Data("not an image".utf8))

        XCTAssertNil(viewModel.reviewImage)
        XCTAssertEqual(viewModel.toastStyle, .error)
        XCTAssertFalse(viewModel.isImporting)
    }

    @MainActor
    func testImportedPhotoAppliesEXIFRotationAndMirroringBeforeEncoding() async throws {
        let cases: [(
            orientation: Int,
            expectedWidth: Int,
            expectedHeight: Int,
            expectedQuadrants: [QuadrantColor]
        )] = [
            (1, 80, 40, [.red, .green, .blue, .yellow]),
            (2, 80, 40, [.green, .red, .yellow, .blue]),
            (3, 80, 40, [.yellow, .blue, .green, .red]),
            (4, 80, 40, [.blue, .yellow, .red, .green]),
            (5, 40, 80, [.red, .blue, .green, .yellow]),
            (6, 40, 80, [.blue, .red, .yellow, .green]),
            (7, 40, 80, [.yellow, .green, .blue, .red]),
            (8, 40, 80, [.green, .yellow, .red, .blue])
        ]

        for testCase in cases {
            let sourceData = try orientedQuadrantJPEG(orientation: testCase.orientation)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(sourceData as CFData, nil))
            let sourceProperties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            )
            XCTAssertEqual(
                (sourceProperties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue,
                testCase.orientation
            )

            let viewModel = try makeViewModel()
            let recipe = try XCTUnwrap(
                FilmRecipe.builtIns.first(where: { $0.id == "provia-standard" })
            )
            viewModel.select(recipe: recipe)
            await viewModel.importPhoto(data: sourceData)

            let saver = ControlledPhotoSaver()
            viewModel.saveReview(photoLibrary: saver)
            let outputData = try XCTUnwrap(saver.requests.last?.imageData)
            let outputSource = try XCTUnwrap(CGImageSourceCreateWithData(outputData as CFData, nil))
            let outputProperties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [String: Any]
            )
            let outputImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(outputSource, 0, nil))

            XCTAssertEqual(outputImage.width, testCase.expectedWidth)
            XCTAssertEqual(outputImage.height, testCase.expectedHeight)
            XCTAssertEqual(
                (outputProperties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue,
                1
            )
            XCTAssertEqual(
                try quadrantColors(in: outputImage),
                testCase.expectedQuadrants,
                "EXIF orientation \(testCase.orientation) used the wrong rotation or mirror direction"
            )
            XCTAssertEqual(viewModel.reviewSource, .photoLibrary)
            XCTAssertTrue(viewModel.reviewIsFullResolution)
            saver.completeLast(with: .success(()))
        }
    }

    func testOversizedImportIsBoundedWithoutChangingFraming() {
        let sourceExtent = CGRect(x: 0, y: 0, width: 10_000, height: 5_000)
        let source = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7))
            .cropped(to: sourceExtent)

        let bounded = CameraViewModel.boundedImportInput(source)
        XCTAssertEqual(bounded.extent.origin, .zero)
        XCTAssertLessThan(bounded.extent.width, sourceExtent.width)
        XCTAssertLessThan(bounded.extent.height, sourceExtent.height)
        XCTAssertLessThanOrEqual(
            bounded.extent.width * bounded.extent.height,
            CameraViewModel.importPixelBudget
        )
        XCTAssertGreaterThanOrEqual(
            bounded.extent.width * bounded.extent.height,
            CameraViewModel.importPixelBudget * 0.999
        )
        XCTAssertEqual(
            bounded.extent.width / bounded.extent.height,
            sourceExtent.width / sourceExtent.height,
            accuracy: 0.001
        )
    }

    func testImportAtOrBelowBudgetPreservesExtentIncludingNonzeroOrigin() {
        let extents = [
            CGRect(x: 17, y: 29, width: 8_000, height: 5_000),
            CGRect(x: 31, y: 47, width: 6_000, height: 4_000)
        ]

        for extent in extents {
            let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
                .cropped(to: extent)

            XCTAssertEqual(CameraViewModel.boundedImportInput(source).extent, extent)
        }
    }

    func testScaledGrainPhasePreservesValuesBeyondSeedBitRange() {
        let seed = UInt32(0x1FF) | (UInt32(0x1FF) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            grainSize: 1,
            previewSize: CGSize(width: 300, height: 600),
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 2044, accuracy: 0.001)
        XCTAssertEqual(phase.y, 2044, accuracy: 0.001)
    }

    func testScaledGrainPhaseUsesClampedRendererScaleForLargeGrain() {
        let phase = CameraViewModel.scaledGrainPhase(
            10 | (UInt32(20) << 9),
            grainSize: 2.5,
            previewSize: CGSize(width: 1080, height: 1080),
            stillSize: CGSize(width: 4320, height: 4320)
        )

        // Preview scale = 2.5; capture scale = min(2.5 * 4, 8) = 8.
        XCTAssertEqual(phase.x, 32, accuracy: 0.001)
        XCTAssertEqual(phase.y, 64, accuracy: 0.001)
        XCTAssertNotEqual(phase.x, 40, accuracy: 0.001)
        XCTAssertNotEqual(phase.y, 80, accuracy: 0.001)
    }

    func testScaledGrainPhaseFallsBackToPreviewPhaseForInvalidSizes() {
        let seed = UInt32(17) | (UInt32(29) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            grainSize: 1,
            previewSize: .zero,
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 17, accuracy: 0.001)
        XCTAssertEqual(phase.y, 29, accuracy: 0.001)
    }

    @MainActor
    private func makeViewModel() throws -> CameraViewModel {
        let suiteName = "CameraViewModelRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaultsSuites.append((defaults, suiteName))
        return CameraViewModel(defaults: defaults)
    }

    private func orientedQuadrantJPEG(orientation: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 80, height: 40),
            format: format
        ).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            UIColor.green.setFill()
            context.fill(CGRect(x: 40, y: 0, width: 40, height: 20))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 20, width: 40, height: 20))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 40, y: 20, width: 40, height: 20))
        }
        let sourceImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(
            try quadrantColors(in: sourceImage),
            [.red, .green, .blue, .yellow],
            "The raw fixture and sampling helper must agree before the app import path runs"
        )
        let sourceData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            sourceData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            sourceImage,
            [kCGImagePropertyOrientation as String: orientation] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return sourceData as Data
    }

    private func quadrantColors(in image: CGImage) throws -> [QuadrantColor] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }

        return [
            (image.width / 4, image.height / 4),
            (image.width * 3 / 4, image.height / 4),
            (image.width / 4, image.height * 3 / 4),
            (image.width * 3 / 4, image.height * 3 / 4)
        ].map { x, y in
            let offset = (y * image.width + x) * 4
            return QuadrantColor(
                red: pixels[offset],
                green: pixels[offset + 1],
                blue: pixels[offset + 2]
            )
        }
    }

    private enum QuadrantColor: Equatable {
        case red
        case green
        case blue
        case yellow

        init(red: UInt8, green: UInt8, blue: UInt8) {
            let red = Double(red)
            let green = Double(green)
            let blue = Double(blue)
            if blue > red * 1.2, blue > green * 1.2 {
                self = .blue
            } else if green > red * 1.2, green > blue * 1.2 {
                self = .green
            } else if red > green * 1.3, red > blue * 1.2 {
                self = .red
            } else {
                self = .yellow
            }
        }
    }
}
