import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Metal
import XCTest
@testable import FilmyCamera

/// Pixel-level regressions for the red-speckle report. Use float buffers rather
/// than image-wide averages: a few bad pixels can disappear in an average.
final class HalationArtifactRegressionTests: XCTestCase {
    private let context = CIContext(options: FilmRenderer.testContextOptions)
    private var colorSpace: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
    private let qualities: [FilmRenderer.Quality] = [.preview, .photo, .export]

    func testHalationIsIdentityForNoisyShadowsAndMidtones() {
        let image = neutralDetail()
        let original = pixels(image)
        for amount in [0.02, 0.5, 1.0] {
            for quality in qualities {
                var recipe = FilmRecipe(id: "halation-mask", name: "Mask", subtitle: "Test")
                recipe.halation = amount
                let result = FilmRenderer.applyHalation(to: image, recipe: recipe, quality: quality)
                assertRGBEqual(pixels(result), original, tolerance: 0.0005, "amount=\(amount), \(quality)")
            }
        }
    }

    func testUniformHighlightMatchesBoundedScreenEquationIncludingImageEdges() {
        // Keep the existing transfer function, but clamp it BEFORE spatial
        // filtering. At 0.75 its value is negative; at 0.80 it is only 0.07.
        // An alpha mask accidentally interpreted as white fails this oracle.
        for level: Float in [0, 0.25, 0.70, 0.75, 0.78, 0.80, 0.85, 0.95, 1] {
            for amount in [0.02, 1.0] {
                let image = fixture(width: 48, height: 32) { _, _ in [level, level, level, 1] }
                var recipe = FilmRecipe(id: "uniform-highlight", name: "Highlight", subtitle: "Test")
                recipe.halation = amount
                let result = pixels(FilmRenderer.applyHalation(to: image, recipe: recipe, quality: .photo))
                let mask = min(max((level - 0.5) * 2.4 + 0.5 - 1.15, 0), 1)
                let opacity = Float(amount * 0.24) * mask
                let tint: [Float] = [1, 0.10, 0.035]
                var maximumError: Float = 0
                for index in stride(from: 0, to: result.count, by: 4) {
                    for channel in 0..<3 {
                        let expected = level + (1 - level) * tint[channel] * opacity
                        maximumError = max(maximumError, abs(result[index + channel] - expected))
                    }
                    maximumError = max(maximumError, abs(result[index + 3] - 1))
                }
                XCTAssertLessThanOrEqual(maximumError, 0.001, "level=\(level), amount=\(amount)")
            }
        }
    }

    func testTrueHighlightsStillProduceLocalizedRedGlow() {
        let width = 192
        let image = fixture(width: width, height: 96) { x, _ in
            let level: Float = (80..<112).contains(x) ? 1 : 0.20
            return [level, level, level, 1]
        }
        let original = pixels(image)
        for amount in [0.02, 1.0] {
            var recipe = FilmRecipe(id: "highlight-edge", name: "Edge", subtitle: "Test")
            recipe.halation = amount
            let result = pixels(FilmRenderer.applyHalation(to: image, recipe: recipe, quality: .photo))
            let near = (48 * width + 79) * 4
            let far = (48 * width + 16) * 4
            let redLift = result[near] - original[near]
            let greenLift = result[near + 1] - original[near + 1]
            XCTAssertGreaterThan(redLift, 0.00001, "Halation was disabled instead of repaired")
            XCTAssertGreaterThan(redLift, greenLift * 2, "The intended warm highlight glow must survive")
            for channel in 0..<3 {
                XCTAssertEqual(result[far + channel], original[far + channel], accuracy: 0.0005)
            }
            // A positive light-scattering effect must not subtract light from
            // nearby dark pixels, even when the old mask would be negative.
            var maximumDarkening: Float = 0
            for index in stride(from: 0, to: result.count, by: 4) {
                for channel in 0..<3 {
                    maximumDarkening = max(maximumDarkening, original[index + channel] - result[index + channel])
                }
            }
            XCTAssertLessThanOrEqual(maximumDarkening, 0.0005)
        }
    }

    func testZeroHalationIsAnExactNoOp() {
        let image = neutralDetail()
        let recipe = FilmRecipe(id: "no-halation", name: "None", subtitle: "Test")
        XCTAssertEqual(recipe.halation, 0)
        for quality in qualities {
            let result = FilmRenderer.applyHalation(to: image, recipe: recipe, quality: quality)
            XCTAssertEqual(result.extent, image.extent)
            XCTAssertEqual(pixels(result), pixels(image))
        }
    }

    func testBuiltInVividSlideDoesNotAddRedSpecklesAtAnyQuality() throws {
        let recipe = try vividSlide()
        XCTAssertEqual(recipe.grain, 0, "This fixture must exercise the reported grain-free built-in")
        XCTAssertGreaterThan(recipe.halation, 0, "Do not fix the report by disabling the recipe's halation")
        try assertVividSubthresholdIdentity(context: context)
    }

    func testBuiltInVividSlideDoesNotAddRedSpecklesOnMetal() throws {
        let device = try XCTUnwrap(FilmRenderer.metalDevice, "A Metal device is required for this GPU regression")
        var options = FilmRenderer.testContextOptions
        options[.useSoftwareRenderer] = false
        let metalContext = CIContext(mtlDevice: device, options: options)
        try assertVividSubthresholdIdentity(context: metalContext)
    }

    func testVividSlidePreviewPhotoAndExportRemainPixelAligned() throws {
        let image = highlightScene()
        var recipe = try vividSlide()
        for grain in [0.0, 0.5, 1.0] {
            recipe.grain = grain
            let preview = pixels(FilmRenderer.render(image, recipe: recipe, quality: .preview, grainSeed: 7919))
            for quality in [FilmRenderer.Quality.photo, .export] {
                let result = FilmRenderer.render(image, recipe: recipe, quality: quality, grainSeed: 7919)
                assertRGBEqual(pixels(result), preview, tolerance: 0.0005, "grain=\(grain), \(quality)")
            }
        }
    }

    func testGrainRemainsAchromaticAfterHalation() throws {
        let image = fixture(width: 128, height: 96) { _, _ in [0.35, 0.35, 0.35, 1] }
        let cleanRecipe = try vividSlide()
        var grainRecipe = cleanRecipe
        grainRecipe.grain = 1
        let clean = pixels(FilmRenderer.render(image, recipe: cleanRecipe, quality: .photo, grainSeed: 42))
        let textured = pixels(FilmRenderer.render(image, recipe: grainRecipe, quality: .photo, grainSeed: 42))
        var maximumChromaDelta: Float = 0
        var maximumTexture: Float = 0
        for index in stride(from: 0, to: textured.count, by: 4) {
            let red = textured[index] - clean[index]
            let green = textured[index + 1] - clean[index + 1]
            let blue = textured[index + 2] - clean[index + 2]
            maximumChromaDelta = max(maximumChromaDelta, abs(red - green), abs(red - blue))
            maximumTexture = max(maximumTexture, abs(red))
        }
        XCTAssertLessThanOrEqual(maximumChromaDelta, 0.001)
        XCTAssertGreaterThan(maximumTexture, 0.001, "Disabling grain must not make this regression pass")
    }

    func testTransparencyAndTranslatedExtentsSurviveVividSlideFinishing() throws {
        let image = fixture(width: 96, height: 64) { x, _ in
            let alpha: Float = [0, 0.25, 0.5, 1][x / 24]
            return [0.35 * alpha, 0.35 * alpha, 0.35 * alpha, alpha]
        }.transformed(by: CGAffineTransform(translationX: -17, y: 9))
        let source = pixels(image)
        let recipe = try vividSlide()
        for quality in qualities {
            let result = FilmRenderer.render(image, recipe: recipe, quality: quality)
            XCTAssertEqual(result.extent, image.extent)
            let rendered = pixels(result)
            var alphaError: Float = 0
            var transparentRGB: Float = 0
            for index in stride(from: 0, to: rendered.count, by: 4) {
                alphaError = max(alphaError, abs(rendered[index + 3] - source[index + 3]))
                if source[index + 3] == 0 {
                    transparentRGB = max(transparentRGB, abs(rendered[index]), abs(rendered[index + 1]), abs(rendered[index + 2]))
                }
            }
            XCTAssertLessThanOrEqual(alphaError, 0.0005)
            XCTAssertLessThanOrEqual(transparentRGB, 0.0005)
        }
    }

    func testExtendedRangeSaturatedEdgesRemainFiniteAndBounded() throws {
        let colors: [[Float]] = [
            [-0.1, 0.01, 0.01, 1], [1.2, 0.01, 0.01, 1],
            [0.01, 1.2, 0.01, 1], [0.01, 0.01, 1.2, 1], [4, 4, 4, 1]
        ]
        let image = fixture(width: 100, height: 48) { x, _ in colors[x / 20] }
        var recipe = try vividSlide()
        recipe.halation = 1
        recipe.sharpness = 1
        recipe.clarity = 1
        for quality in qualities {
            let result = pixels(FilmRenderer.render(image, recipe: recipe, quality: quality))
            XCTAssertTrue(result.allSatisfy { $0 >= -0.0005 && $0 <= 1.0005 }, "\(quality)")
        }
    }

    func testFinishedJPEGRoundTripDoesNotBakeInRedSpeckles() throws {
        let image = neutralDetail()
        let recipe = try vividSlide()
        var noHalation = recipe
        noHalation.halation = 0
        let expected = try finishedJPEG(image, recipe: noHalation)
        let actual = try finishedJPEG(image, recipe: recipe)
        XCTAssertEqual(actual.extent, expected.extent)
        assertRGBEqual(pixels(actual), pixels(expected), tolerance: 1.0 / 255, "Finished Photos-ready JPEG")
    }

    func testRendererVersionInvalidatesPreFixThumbnailCache() {
        // Cached PNGs otherwise keep displaying the old artifact after an
        // app update, even though the live pipeline has been repaired.
        XCTAssertNotEqual(FilmRecipe.rendererVersion, "core-image-parametric-v9")
    }

    private func assertVividSubthresholdIdentity(context renderContext: CIContext) throws {
        let image = neutralDetail()
        let recipe = try vividSlide()
        var noHalation = recipe
        noHalation.halation = 0
        for quality in qualities {
            let expected = FilmRenderer.render(image, recipe: noHalation, quality: quality, grainSeed: 42)
            let actual = FilmRenderer.render(image, recipe: recipe, quality: quality, grainSeed: 42)
            assertRGBEqual(
                pixels(actual, using: renderContext), pixels(expected, using: renderContext),
                tolerance: 0.001, "Vivid Slide \(quality)"
            )
        }
    }

    private func vividSlide() throws -> FilmRecipe {
        try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "velvia-vivid" })
    }

    private func neutralDetail() -> CIImage {
        fixture(width: 128, height: 96) { x, y in
            // Deliberately deterministic, high-frequency neutral detail. Its
            // level remains below the highlight threshold after Vivid Slide.
            let noise = Float((x * 73 + y * 151 + x * y * 19) % 101) / 100
            let value = Float(0.10) + Float(x) / 127 * 0.30 + noise * 0.03
            return [value, value, value, 1]
        }
    }

    private func highlightScene() -> CIImage {
        fixture(width: 192, height: 96) { x, y in
            if (80..<112).contains(x) && (24..<72).contains(y) { return [1, 1, 1, 1] }
            let value = Float(0.1) + Float(x) / 191 * 0.5
            return [value, value * 0.8, value * 0.6, 1]
        }
    }

    private func fixture(width: Int, height: Int, pixel: (Int, Int) -> [Float]) -> CIImage {
        var values: [Float] = []
        values.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                values.append(contentsOf: pixel(x, y))
            }
        }
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(
            bitmapData: data, bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: colorSpace
        )
    }

    private func pixels(_ image: CIImage, using renderContext: CIContext? = nil) -> [Float] {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var result = [Float](repeating: .nan, count: width * height * 4)
        result.withUnsafeMutableBytes { buffer in
            (renderContext ?? context).render(
                image, toBitmap: buffer.baseAddress!, rowBytes: width * 4 * MemoryLayout<Float>.stride,
                bounds: image.extent, format: .RGBAf, colorSpace: colorSpace
            )
        }
        XCTAssertTrue(result.allSatisfy { $0.isFinite }, "Core Image left non-finite or unrendered pixels")
        return result
    }

    private func assertRGBEqual(
        _ actual: [Float], _ expected: [Float], tolerance: Float, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, message, file: file, line: line)
        guard actual.count == expected.count else { return }
        var maximumError: Float = 0
        for index in actual.indices where index % 4 != 3 {
            guard actual[index].isFinite && expected[index].isFinite else {
                XCTFail("Non-finite RGB: \(message)", file: file, line: line)
                return
            }
            maximumError = max(maximumError, abs(actual[index] - expected[index]))
        }
        XCTAssertLessThanOrEqual(maximumError, tolerance, message, file: file, line: line)
    }

    private func finishedJPEG(_ image: CIImage, recipe: FilmRecipe) throws -> CIImage {
        let rendered = FilmRenderer.render(image, recipe: recipe, quality: .photo)
        let cgImage = try XCTUnwrap(FilmRenderer.outputCGImage(rendered))
        let data = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: cgImage, sourceData: Data(), capturedAt: Date(timeIntervalSince1970: 0), recipe: recipe
        ))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CIImage(cgImage: decoded)
    }
}
