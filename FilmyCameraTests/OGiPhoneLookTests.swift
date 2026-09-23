import CoreGraphics
import CoreImage
import UIKit
import XCTest
@testable import FilmyCamera

/// Coverage for the "OG iPhone" first-generation phone camera look.
final class OGiPhoneLookTests: XCTestCase {
    private func recipe() throws -> FilmRecipe {
        try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "og-iphone" })
    }

    func testOGiPhoneLookExistsExactlyOnceAndUsesFirstPhoneBase() throws {
        let matches = FilmRecipe.builtIns.filter { $0.id == "og-iphone" }
        XCTAssertEqual(matches.count, 1)
        let look = try XCTUnwrap(matches.first)
        XCTAssertEqual(look.name, "OG iPhone")
        XCTAssertEqual(look.filmBase, .firstPhone)
        XCTAssertFalse(look.subtitle.isEmpty)
        XCTAssertTrue(look.provenance.disclaimer.contains("original"))
        XCTAssertTrue(look.provenance.disclaimer.contains("not affiliated"))
    }

    func testOGiPhoneRenderIsDeterministic() throws {
        let recipe = try recipe()
        let extent = CGRect(x: 0, y: 0, width: 40, height: 30)
        let input = Self.detailFixture(size: extent.size)

        let first = FilmRenderer.render(input, recipe: recipe, quality: .photo, grainSeed: 42)
        let second = FilmRenderer.render(input, recipe: recipe, quality: .photo, grainSeed: 42)
        let context = CIContext(options: FilmRenderer.testContextOptions)

        let firstPixels = try Self.pixels(first, extent: extent, context: context)
        let secondPixels = try Self.pixels(second, extent: extent, context: context)
        XCTAssertEqual(firstPixels, secondPixels)
    }

    func testOGiPhoneOutputExtentMatchesInputExtent() throws {
        let recipe = try recipe()
        let extent = CGRect(x: 0, y: 0, width: 2048, height: 1536)
        let input = Self.detailFixture(size: extent.size)
        let output = FilmRenderer.render(input, recipe: recipe, quality: .export)
        XCTAssertEqual(output.extent, extent)
    }

    func testOGiPhoneHasLowerHighFrequencyDetailThanNeutralRecipe() throws {
        let ogIPhone = try recipe()
        let neutral = FilmRecipe(id: "neutral-detail-control", name: "Neutral", subtitle: "Test control", filmBase: .standard)
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let input = Self.detailFixture(size: extent.size)
        let context = CIContext(options: FilmRenderer.testContextOptions)

        let ogPixels = try Self.pixels(
            FilmRenderer.render(input, recipe: ogIPhone, quality: .export),
            extent: extent, context: context
        )
        let neutralPixels = try Self.pixels(
            FilmRenderer.render(input, recipe: neutral, quality: .export),
            extent: extent, context: context
        )

        XCTAssertLessThan(
            Self.highFrequencyEnergy(ogPixels, width: Int(extent.width), height: Int(extent.height)),
            Self.highFrequencyEnergy(neutralPixels, width: Int(extent.width), height: Int(extent.height)),
            "OG iPhone should read softer/mushier than the neutral recipe"
        )
    }

    func testOGiPhoneBrightensMidtonesWithoutWashingOut() throws {
        let recipe = try recipe()
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let input = CIImage(color: CIColor(red: 0.46, green: 0.46, blue: 0.46, alpha: 1)).cropped(to: extent)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let pixels = try Self.pixels(FilmRenderer.render(input, recipe: recipe, quality: .photo), extent: extent, context: context)
        let luma = 0.2126 * Double(pixels[0]) + 0.7152 * Double(pixels[1]) + 0.0722 * Double(pixels[2])
        XCTAssertGreaterThan(luma, 0.46, "OG iPhone auto-exposure should lift midtones")
        XCTAssertLessThan(luma, 0.62, "OG iPhone must not wash midtones out toward white")
    }

    func testOGiPhoneClipsNearWhiteHighlights() throws {
        let recipe = try recipe()
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        // Build an explicit sRGB pixel. CIImage(color:) is a display-color
        // generator, and its implicit color space/premultiplication path has
        // produced a mid-gray sample on iOS 27 software rendering even when
        // initialized with 0.9 components.
        let input = try Self.nearWhiteFixture()
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let inputPixels = try Self.pixels(input, extent: extent, context: context)
        XCTAssertEqual(Double(inputPixels[0]), 0.9, accuracy: 0.02)
        let output = FilmRenderer.render(input, recipe: recipe, quality: .photo)
        let pixels = try Self.pixels(output, extent: extent, context: context)

        for channel in 0..<3 {
            XCTAssertEqual(Double(pixels[channel]), 1.0, accuracy: 0.05, "channel \(channel) did not clip near white")
        }
    }

    /// Renders a before/after PNG pair of the shared demo source image for
    /// visual review and prints the output directory path.
    // MARK: - Fixtures

    private static func detailFixture(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        guard let checkerboard = CIFilter(name: "CICheckerboardGenerator") else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        }
        checkerboard.setValue(CIVector(x: 0, y: 0), forKey: "inputCenter")
        checkerboard.setValue(CIColor(red: 0.92, green: 0.55, blue: 0.20, alpha: 1), forKey: "inputColor0")
        checkerboard.setValue(CIColor(red: 0.10, green: 0.25, blue: 0.60, alpha: 1), forKey: "inputColor1")
        checkerboard.setValue(2.0, forKey: "inputWidth")
        checkerboard.setValue(0.0, forKey: "inputSharpness")
        return (checkerboard.outputImage ?? CIImage(color: .gray)).cropped(to: extent)
    }

    private static func nearWhiteFixture() throws -> CIImage {
        var bytes: [UInt8] = [230, 230, 230, 255]
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = bytes.withUnsafeMutableBytes { rawBuffer -> CGImage? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        return CIImage(cgImage: try XCTUnwrap(image))
    }

    private static func pixels(_ image: CIImage, extent: CGRect, context: CIContext) throws -> [Float] {
        let width = Int(extent.width)
        let height = Int(extent.height)
        var buffer = [Float](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        buffer.withUnsafeMutableBytes { rawBuffer in
            context.render(
                image,
                toBitmap: rawBuffer.baseAddress!,
                rowBytes: width * 4 * MemoryLayout<Float>.stride,
                bounds: extent,
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        return buffer
    }

    /// A simple, deterministic proxy for perceived detail: the mean absolute
    /// luminance difference between horizontally adjacent pixels.
    private static func highFrequencyEnergy(_ pixels: [Float], width: Int, height: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let leftIndex = (y * width + x) * 4
                let rightIndex = (y * width + x + 1) * 4
                let leftLuma = Double(pixels[leftIndex]) * 0.2126 + Double(pixels[leftIndex + 1]) * 0.7152 + Double(pixels[leftIndex + 2]) * 0.0722
                let rightLuma = Double(pixels[rightIndex]) * 0.2126 + Double(pixels[rightIndex + 1]) * 0.7152 + Double(pixels[rightIndex + 2]) * 0.0722
                total += abs(rightLuma - leftLuma)
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }
}

/// Local visual review only: writes before/after PNGs of the demo source.
/// Runs in the fixtures lane because the source file is host-only.
final class OGiPhoneLookPreviewTests: XCTestCase {
    func testOGiPhoneRendersDemoSourceBeforeAfterPNG() throws {
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "og-iphone" })
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/app-store/screenshots/demo-source/cafe-original.png")
        guard let source = CIImage(contentsOf: sourceURL) else {
            throw XCTSkip("Demo source image not found at \(sourceURL.path)")
        }

        let rendered = FilmRenderer.render(source, recipe: recipe, quality: .export)
        guard let beforeCG = FilmRenderer.outputCGImage(source, from: source.extent),
              let afterCG = FilmRenderer.outputCGImage(rendered, from: rendered.extent) else {
            return XCTFail("Failed to materialize before/after images")
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("og-iphone-look-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let beforeURL = directory.appendingPathComponent("cafe-before.png")
        let afterURL = directory.appendingPathComponent("cafe-after-og-iphone.png")
        try UIImage(cgImage: beforeCG).pngData()?.write(to: beforeURL)
        try UIImage(cgImage: afterCG).pngData()?.write(to: afterURL)

        // Reference renders for side-by-side tone comparison.
        let references: [(String, FilmRecipe)] = [
            ("cafe-neutral.png", FilmRecipe(id: "neutral-preview", name: "Neutral", subtitle: "Preview control", filmBase: .standard))
        ] + FilmRecipe.builtIns.filter { $0.filmBase == .compactDigital }.prefix(1).map { ("cafe-compact-digital.png", $0) }
        for (name, reference) in references {
            let image = FilmRenderer.render(source, recipe: reference, quality: .export)
            if let cgImage = FilmRenderer.outputCGImage(image, from: image.extent) {
                try UIImage(cgImage: cgImage).pngData()?.write(to: directory.appendingPathComponent(name))
            }
        }

        print("OG iPhone before/after PNGs written to: \(directory.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: beforeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: afterURL.path))
    }
}
