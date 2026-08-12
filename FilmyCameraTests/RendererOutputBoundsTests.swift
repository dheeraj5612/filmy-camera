import CoreGraphics
import CoreImage
import XCTest
@testable import FilmyCamera

final class RendererOutputBoundsTests: XCTestCase {
    func testRendererPreservesInputExtentAtEveryQualityTier() {
        let sourceExtent = CGRect(x: -12, y: 7, width: 64, height: 48)
        let input = CIImage(color: CIColor(red: 0.82, green: 0.37, blue: 0.12, alpha: 1))
            .cropped(to: sourceExtent)
        let recipe = FilmRecipe.builtIns[0]

        for quality in [FilmRenderer.Quality.preview, .photo, .export] {
            let output = FilmRenderer.render(input, recipe: recipe, quality: quality)
            XCTAssertEqual(output.extent, sourceExtent, "Extent changed at \(quality)")
            XCTAssertTrue(output.extent.width.isFinite)
            XCTAssertTrue(output.extent.height.isFinite)
            XCTAssertGreaterThan(output.extent.width, 0)
            XCTAssertGreaterThan(output.extent.height, 0)
        }
    }

    func testRenderedRGBAChannelsAreFiniteAndWithinNormalizedBounds() {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.95, green: 0.12, blue: 0.78, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])

        for recipe in FilmRecipe.builtIns {
            let output = FilmRenderer.render(input, recipe: recipe, quality: .preview)
            let pixels = renderFloatPixels(output, extent: extent, context: context)

            XCTAssertEqual(pixels.count, Int(extent.width * extent.height) * 4, recipe.id)
            for (index, channel) in pixels.enumerated() {
                XCTAssertTrue(channel.isFinite, "Non-finite channel \(index) for \(recipe.id)")
                XCTAssertTrue(
                    (-0.0005...1.0005).contains(Double(channel)),
                    "Out-of-bounds channel \(index) for \(recipe.id): \(channel)"
                )
            }
        }
    }

    func testEmptyInputIsReturnedWithoutExpandingBounds() {
        let empty = CIImage.empty()
        let output = FilmRenderer.render(
            empty,
            recipe: FilmRecipe.builtIns[0],
            quality: .preview
        )

        XCTAssertEqual(output.extent, empty.extent)
        XCTAssertTrue(output.extent.isEmpty)
    }

    func testRendererMaterializesSinglePixelForEveryQualityTier() {
        let extent = CGRect(x: 7, y: -3, width: 1, height: 1)
        let input = CIImage(color: CIColor(red: 0.95, green: 0.18, blue: 0.72, alpha: 0.35))
            .cropped(to: extent)
        let recipe = FilmRecipe.builtIns[1]
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])

        for quality in [FilmRenderer.Quality.preview, .photo, .export] {
            let output = FilmRenderer.render(input, recipe: recipe, quality: quality)
            let pixels = renderFloatPixels(output, extent: extent, context: context)

            XCTAssertEqual(output.extent, extent, "Extent changed at " + String(describing: quality))
            XCTAssertEqual(pixels.count, 4, "Unexpected pixel count at " + String(describing: quality))
            XCTAssertTrue(pixels.allSatisfy(\.isFinite), "Non-finite output at " + String(describing: quality))
            XCTAssertTrue(
                pixels.allSatisfy { (-0.0005...1.0005).contains(Double($0)) },
                "Output escaped normalized bounds at " + String(describing: quality) + ": " + String(describing: pixels)
            )
        }
    }

    func testRendererKeepsExtremeFiniteRecipeControlsBounded() {
        var recipe = FilmRecipe.builtIns[0]
        recipe.exposure = 4
        recipe.tone = FilmRecipe.Tone(highlight: 8, shadow: -8)
        recipe.saturation = -4
        recipe.contrast = 8
        recipe.whiteBalance = FilmRecipe.WhiteBalanceShift(temperature: 5, tint: -5)
        recipe.colorChrome = 4
        recipe.blueResponse = -4
        recipe.fxBlue = 4
        recipe.sharpness = 4
        recipe.noiseReduction = 4
        recipe.clarity = -4
        recipe.grain = 4
        recipe.grainSize = 0
        recipe.vignette = 4
        recipe.halation = 4
        recipe.palette = FilmRecipe.Palette(
            redBias: 4,
            greenBias: -4,
            blueBias: 4,
            redGreenMix: -4,
            greenBlueMix: 4,
            blueRedMix: -4,
            saturation: 4
        )

        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let input = CIImage(color: CIColor(red: 1, green: 0.03, blue: 0.92, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])

        for quality in [FilmRenderer.Quality.preview, .photo, .export] {
            let output = FilmRenderer.render(input, recipe: recipe, quality: quality)
            let pixels = renderFloatPixels(output, extent: extent, context: context)

            XCTAssertEqual(output.extent, extent, "Extent changed at " + String(describing: quality))
            XCTAssertTrue(pixels.allSatisfy(\.isFinite), "Non-finite output at " + String(describing: quality))
            XCTAssertTrue(
                pixels.allSatisfy { (-0.0005...1.0005).contains(Double($0)) },
                "Extreme controls escaped normalized bounds at " + String(describing: quality)
            )
        }
    }

    func testFilmBaseChangesRenderedColorEvenWithSharedNumericControls() {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.88, green: 0.42, blue: 0.16, alpha: 1))
            .cropped(to: extent)
        let standard = FilmRecipe(
            id: "test-standard",
            name: "Standard",
            subtitle: "Test",
            filmBase: .standard,
            saturation: 1,
            contrast: 1
        )
        let velvia = FilmRecipe(
            id: "test-velvia",
            name: "Velvia",
            subtitle: "Test",
            filmBase: .velvia,
            saturation: 1,
            contrast: 1
        )
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

        let standardPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: standard, quality: .photo),
            extent: extent,
            context: context
        )
        let velviaPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: velvia, quality: .photo),
            extent: extent,
            context: context
        )

        let distance = zip(standardPixels, velviaPixels)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertGreaterThan(distance, 0.01)
    }

    func testRecipeTuningChangesRenderedOutput() {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.82, green: 0.34, blue: 0.22, alpha: 1))
            .cropped(to: extent)
        var tuned = FilmRecipe.builtIns[0]
        tuned.exposure += 0.35
        tuned.fxBlue = -0.65
        tuned.halation = 0.8
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

        let basePixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: FilmRecipe.builtIns[0], quality: .photo),
            extent: extent,
            context: context
        )
        let tunedPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: tuned, quality: .photo),
            extent: extent,
            context: context
        )

        let distance = zip(basePixels, tunedPixels)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertGreaterThan(distance, 0.01)
    }

    private func renderFloatPixels(
        _ image: CIImage,
        extent: CGRect,
        context: CIContext
    ) -> [Float] {
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)

        pixels.withUnsafeMutableBytes { rawBuffer in
            context.render(
                image,
                toBitmap: rawBuffer.baseAddress!,
                rowBytes: width * 4 * MemoryLayout<Float>.stride,
                bounds: extent,
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }

        return pixels
    }
}
