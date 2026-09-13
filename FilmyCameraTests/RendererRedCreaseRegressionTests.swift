import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import FilmyCamera

/// Regression coverage for dark, warm crease pixels that sit on the lower edge
/// of the renderer's skin hue mask. The mask may feather the correction, but it
/// must not turn a small source hue step into a red contour.
final class RendererRedCreaseRegressionTests: XCTestCase {
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
    private let context = CIContext(options: FilmRenderer.testContextOptions)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func testLowerSkinHueCreaseDoesNotAmplifyNeighboringRedHueContrast() throws {
        let input = creaseFixture()
        var recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        // Isolate the color pipeline under test from stochastic grain and
        // spatial detail filters, while retaining the look's color cube.
        recipe.grain = 0
        recipe.sharpness = 0
        recipe.clarity = 0
        recipe.halation = 0
        recipe.vignette = 0

        let source = pixels(input)
        let rendered = pixels(FilmRenderer.render(input, recipe: recipe, quality: .photo))

        var sourceHueStep = 0.0
        var renderedHueStep = 0.0
        var sourceLumaStep = 0.0
        var renderedLumaStep = 0.0
        var sourceChroma = 0.0
        var renderedChroma = 0.0

        // Four-pixel blocks keep the sampled points away from Core Image's
        // interpolation boundaries. Even columns straddle the lower-mask hue
        // edge; rows alternate a darker crease and its immediately lit surface.
        for y in stride(from: 2, to: 50, by: 16) {
            for x in stride(from: 2, to: 50, by: 16) {
                let lower = offset(x: x, y: y)
                let upper = offset(x: x + 4, y: y)
                let lit = offset(x: x, y: y + 8)
                sourceHueStep = max(sourceHueStep, abs(normalizedRedHue(source, at: lower) - normalizedRedHue(source, at: upper)))
                renderedHueStep = max(renderedHueStep, abs(normalizedRedHue(rendered, at: lower) - normalizedRedHue(rendered, at: upper)))
                sourceLumaStep = max(sourceLumaStep, abs(luma(source, at: lower) - luma(source, at: lit)))
                renderedLumaStep = max(renderedLumaStep, abs(luma(rendered, at: lower) - luma(rendered, at: lit)))
                sourceChroma += chroma(source, at: lower)
                renderedChroma += chroma(rendered, at: lower)
            }
        }

        XCTAssertGreaterThan(sourceHueStep, 0.04)
        XCTAssertLessThan(
            renderedHueStep,
            sourceHueStep * 1.75 + 0.025,
            "A lower-mask crease must not acquire an isolated red hue contour"
        )
        XCTAssertGreaterThan(
            renderedChroma,
            sourceChroma * 0.55,
            "The skin correction must retain natural source chroma"
        )
        XCTAssertGreaterThan(
            renderedLumaStep,
            sourceLumaStep * 0.45,
            "The crease's luminance texture must survive the color correction"
        )
    }

    private func creaseFixture() -> CIImage {
        let lowerDark: [Float] = [0.475, 0.196, 0.149, 1]
        let upperDark: [Float] = [0.475, 0.219, 0.149, 1]
        let lowerLit: [Float] = [0.550, 0.227, 0.172, 1]
        let upperLit: [Float] = [0.550, 0.254, 0.172, 1]
        let blocks = [lowerDark, upperDark, lowerLit, upperLit]
        var values: [Float] = []
        values.reserveCapacity(64 * 64 * 4)
        for y in 0..<64 {
            for x in 0..<64 {
                let blockX = (x / 4) % blocks.count
                let blockY = (y / 8) % 2
                values.append(contentsOf: blocks[blockY == 0 ? blockX : (blockX + 2) % blocks.count])
            }
        }
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: 64 * 4 * MemoryLayout<Float>.stride,
            size: CGSize(width: 64, height: 64),
            format: .RGBAf,
            colorSpace: colorSpace
        )
    }

    private func pixels(_ image: CIImage) -> [Float] {
        var result = [Float](repeating: .nan, count: 64 * 64 * 4)
        result.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: 64 * 4 * MemoryLayout<Float>.stride,
                bounds: extent,
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        XCTAssertTrue(result.allSatisfy(\.isFinite), "Core Image produced a non-finite pixel")
        return result
    }

    private func offset(x: Int, y: Int) -> Int { (y * 64 + x) * 4 }

    private func luma(_ values: [Float], at index: Int) -> Double {
        0.2126 * Double(values[index]) + 0.7152 * Double(values[index + 1]) + 0.0722 * Double(values[index + 2])
    }

    private func normalizedRedHue(_ values: [Float], at index: Int) -> Double {
        (Double(values[index]) - Double(values[index + 1])) / max(luma(values, at: index), 0.02)
    }

    private func chroma(_ values: [Float], at index: Int) -> Double {
        let red = Double(values[index])
        let green = Double(values[index + 1])
        let blue = Double(values[index + 2])
        return max(red, max(green, blue)) - min(red, min(green, blue))
    }
}
