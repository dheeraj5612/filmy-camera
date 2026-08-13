import CoreGraphics
import CoreImage
import UIKit
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

    func testRendererSanitizesNonFiniteRecipeControls() {
        var recipe = FilmRecipe.builtIns[0]
        recipe.exposure = .nan
        recipe.tone = FilmRecipe.Tone(highlight: .infinity, shadow: -.infinity)
        recipe.saturation = .nan
        recipe.contrast = .infinity
        recipe.whiteBalance = FilmRecipe.WhiteBalanceShift(temperature: .nan, tint: .infinity)
        recipe.colorChrome = .nan
        recipe.blueResponse = .infinity
        recipe.fxBlue = -.infinity
        recipe.sharpness = .nan
        recipe.noiseReduction = .infinity
        recipe.clarity = -.infinity
        recipe.grain = .nan
        recipe.grainSize = .infinity
        recipe.vignette = -.infinity
        recipe.halation = .nan
        recipe.palette = FilmRecipe.Palette(
            redBias: .nan,
            greenBias: .infinity,
            blueBias: -.infinity,
            redGreenMix: .nan,
            greenBlueMix: .infinity,
            blueRedMix: -.infinity,
            saturation: .nan
        )

        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let input = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.5, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

        for quality in [FilmRenderer.Quality.preview, .photo, .export] {
            let output = FilmRenderer.render(input, recipe: recipe, quality: quality)
            let pixels = renderFloatPixels(output, extent: extent, context: context)
            XCTAssertTrue(pixels.allSatisfy(\.isFinite), "Non-finite output at \(quality)")
            XCTAssertTrue(
                pixels.allSatisfy { (-0.0005...1.0005).contains(Double($0)) },
                "Non-finite controls escaped normalized bounds at \(quality)"
            )
        }
    }

    func testColorChromeDoesNotChangeBlueWhenDedicatedBlueControlsAreOff() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let input = CIImage(color: CIColor(red: 0.08, green: 0.18, blue: 0.90, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        var withoutChrome = FilmRecipe.builtIns[0]
        withoutChrome.colorChrome = 0
        withoutChrome.blueResponse = 0
        withoutChrome.fxBlue = 0
        var withChrome = withoutChrome
        withChrome.colorChrome = 1

        let base = renderFloatPixels(
            FilmRenderer.render(input, recipe: withoutChrome, quality: .photo),
            extent: extent,
            context: context
        )
        let chrome = renderFloatPixels(
            FilmRenderer.render(input, recipe: withChrome, quality: .photo),
            extent: extent,
            context: context
        )

        let distance = zip(base, chrome)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertLessThan(distance, 0.0005)
    }

    func testRendererPreservesSourceAlpha() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let input = CIImage(color: CIColor(red: 0.45, green: 0.20, blue: 0.75, alpha: 0.35))
            .cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let pixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: FilmRecipe.builtIns[2], quality: .photo),
            extent: extent,
            context: context
        )

        XCTAssertEqual(pixels.count, 4)
        XCTAssertEqual(pixels[3], 0.35, accuracy: 0.02)
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

    func testDynamicRangeStrengthIncreasesProtectionForHigherModes() {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let input = CIImage(color: CIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

        let dr200 = FilmRecipe(
            id: "test-dr200",
            name: "DR200",
            subtitle: "Test",
            dynamicRange: .dr200
        )
        var dr400 = dr200
        dr400.dynamicRange = .dr400

        let dr200Pixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: dr200, quality: .photo),
            extent: extent,
            context: context
        )
        let dr400Pixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: dr400, quality: .photo),
            extent: extent,
            context: context
        )

        XCTAssertLessThan(dr400Pixels[0], dr200Pixels[0])
    }

    func testMonochromeFiltersUseDistinctChannelMixes() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let source = CIImage(color: CIColor(red: 0.90, green: 0.12, blue: 0.08, alpha: 1))
            .cropped(to: extent)
        let filmBases: [FilmRecipe.FilmBase] = [.acrosYellow, .acrosRed, .acrosGreen]
        let values = filmBases.map { filmBase -> [Float] in
            let recipe = FilmRecipe(
                id: filmBase.rawValue,
                name: filmBase.displayName,
                subtitle: "Test",
                filmBase: filmBase,
                saturation: 0,
                contrast: 1,
                grain: 0,
                vignette: 0,
                halation: 0
            )
            return renderFloatPixels(
                FilmRenderer.render(source, recipe: recipe, quality: .photo),
                extent: extent,
                context: context
            )
        }

        for value in values {
            XCTAssertEqual(value[0], value[1], accuracy: 0.001)
            XCTAssertEqual(value[1], value[2], accuracy: 0.001)
            XCTAssertTrue(value[0].isFinite)
        }

        let distances = [
            zip(values[0], values[1]).map { abs(Double($0.0) - Double($0.1)) }.reduce(0, +),
            zip(values[1], values[2]).map { abs(Double($0.0) - Double($0.1)) }.reduce(0, +)
        ]
        XCTAssertTrue(distances.allSatisfy { $0 > 0.005 })
    }

    func testGrainIsStableAcrossRepeatedRenders() {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 24)
        let input = CIImage(color: CIColor(red: 0.68, green: 0.36, blue: 0.18, alpha: 1))
            .cropped(to: extent)
        let recipe = FilmRecipe(
            id: "deterministic-grain",
            name: "Deterministic Grain",
            subtitle: "Test",
            grain: 0.72,
            grainSize: 1.1
        )
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

        let first = renderFloatPixels(
            FilmRenderer.render(input, recipe: recipe, quality: .photo),
            extent: extent,
            context: context
        )
        let second = renderFloatPixels(
            FilmRenderer.render(input, recipe: recipe, quality: .photo),
            extent: extent,
            context: context
        )

        let difference = zip(first, second)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertLessThan(difference, 0.0001)
    }

    func testGrainSeedChangesSpatialPatternWithoutChangingRecipe() {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 24)
        let input = CIImage(color: CIColor(red: 0.68, green: 0.36, blue: 0.18, alpha: 1))
            .cropped(to: extent)
        let recipe = FilmRecipe(
            id: "seeded-grain",
            name: "Seeded Grain",
            subtitle: "Test",
            grain: 0.72,
            grainSize: 1.1
        )
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let first = renderFloatPixels(
            FilmRenderer.render(input, recipe: recipe, quality: .photo, grainSeed: 1),
            extent: extent,
            context: context
        )
        let second = renderFloatPixels(
            FilmRenderer.render(input, recipe: recipe, quality: .photo, grainSeed: 2),
            extent: extent,
            context: context
        )

        let difference = zip(first, second)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertGreaterThan(difference, 0.0001)
    }

    func testFXBlueRespondsMoreToBlueHuesThanWarmHues() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let base = FilmRecipe(
            id: "base",
            name: "Base",
            subtitle: "Test",
            grain: 0,
            vignette: 0,
            halation: 0
        )
        var fxBlue = base
        fxBlue.fxBlue = 1

        func distance(for color: CIColor) -> Double {
            let input = CIImage(color: color).cropped(to: extent)
            let original = renderFloatPixels(
                FilmRenderer.render(input, recipe: base, quality: .photo),
                extent: extent,
                context: context
            )
            let filtered = renderFloatPixels(
                FilmRenderer.render(input, recipe: fxBlue, quality: .photo),
                extent: extent,
                context: context
            )
            return zip(original, filtered)
                .map { abs(Double($0.0) - Double($0.1)) }
                .reduce(0, +)
        }

        let blueDistance = distance(for: CIColor(red: 0.08, green: 0.18, blue: 0.90, alpha: 1))
        let warmDistance = distance(for: CIColor(red: 0.90, green: 0.20, blue: 0.08, alpha: 1))
        XCTAssertGreaterThan(blueDistance, warmDistance + 0.001)
    }

    func testPositiveToneValuesHardenTheCorrespondingCurveRegions() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let base = FilmRecipe(
            id: "tone-direction",
            name: "Tone direction",
            subtitle: "Test",
            grain: 0,
            vignette: 0,
            halation: 0
        )

        func luma(for color: CIColor, recipe: FilmRecipe) -> Double {
            let input = CIImage(color: color).cropped(to: extent)
            let pixel = renderFloatPixels(
                FilmRenderer.render(input, recipe: recipe, quality: .photo),
                extent: extent,
                context: context
            )
            return 0.2126 * Double(pixel[0])
                + 0.7152 * Double(pixel[1])
                + 0.0722 * Double(pixel[2])
        }

        var harderShadows = base
        harderShadows.tone.shadow = 1
        var liftedShadows = base
        liftedShadows.tone.shadow = -1
        XCTAssertLessThan(
            luma(for: CIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1), recipe: harderShadows),
            luma(for: CIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1), recipe: liftedShadows)
        )

        var harderHighlights = base
        harderHighlights.tone.highlight = 1
        var liftedHighlights = base
        liftedHighlights.tone.highlight = -1
        XCTAssertLessThan(
            luma(for: CIColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1), recipe: harderHighlights),
            luma(for: CIColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1), recipe: liftedHighlights)
        )
    }

    func testPositiveTintMovesOutputTowardMagenta() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let base = FilmRecipe(
            id: "tint-direction",
            name: "Tint direction",
            subtitle: "Test",
            grain: 0,
            vignette: 0,
            halation: 0
        )
        var magenta = base
        magenta.whiteBalance.tint = 1
        var green = base
        green.whiteBalance.tint = -1
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            .cropped(to: extent)
        let magentaPixel = renderFloatPixels(
            FilmRenderer.render(input, recipe: magenta, quality: .photo),
            extent: extent,
            context: context
        )
        let greenPixel = renderFloatPixels(
            FilmRenderer.render(input, recipe: green, quality: .photo),
            extent: extent,
            context: context
        )

        XCTAssertGreaterThan(
            Double(magentaPixel[0]) - Double(magentaPixel[1]),
            Double(greenPixel[0]) - Double(greenPixel[1])
        )
    }

    func testRecipeLookRemainsStableAcrossPreviewPhotoAndExportQuality() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 48)
        let input = CIImage(color: CIColor(red: 0.76, green: 0.34, blue: 0.16, alpha: 1))
            .cropped(to: extent)
        var recipe = FilmRecipe.builtIns[7]
        recipe.grain = 0.42
        recipe.grainSize = 1.2
        recipe.halation = 0.55
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])

        let outputs = [FilmRenderer.Quality.preview, .photo, .export].map {
            renderFloatPixels(
                FilmRenderer.render(input, recipe: recipe, quality: $0),
                extent: extent,
                context: context
            )
        }

        for pair in zip(outputs, outputs.dropFirst()) {
            let meanAbsoluteDifference = zip(pair.0, pair.1)
                .map { abs(Double($0.0) - Double($0.1)) }
                .reduce(0, +) / Double(pair.0.count)
            XCTAssertLessThan(
                meanAbsoluteDifference,
                0.035,
                "Quality tier changed the look too much"
            )
        }
    }

    func testRecipeThumbnailUsesTheRendererAndRequestedSize() {
        let size = CGSize(width: 120, height: 80)
        let image = FilmRenderer.thumbnail(for: FilmRecipe.builtIns[1], size: size)

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.cgImage?.width, Int(size.width))
        XCTAssertEqual(image?.cgImage?.height, Int(size.height))
    }

    func testAspectFillCropMatchesThePreviewViewport() {
        let source = CGRect(x: 0, y: 0, width: 4000, height: 3000)
        let portraitCrop = CameraFrameLayout.aspectFillCrop(
            sourceExtent: source,
            targetSize: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(portraitCrop.width / portraitCrop.height, 390 / 844, accuracy: 0.0001)
        XCTAssertEqual(portraitCrop.midX, source.midX, accuracy: 0.001)
        XCTAssertEqual(portraitCrop.midY, source.midY, accuracy: 0.001)

        let landscapeCrop = CameraFrameLayout.aspectFillCrop(
            sourceExtent: source,
            targetSize: CGSize(width: 844, height: 390)
        )
        XCTAssertEqual(landscapeCrop.width / landscapeCrop.height, 844 / 390, accuracy: 0.0001)
        XCTAssertEqual(landscapeCrop.midX, source.midX, accuracy: 0.001)
        XCTAssertEqual(landscapeCrop.midY, source.midY, accuracy: 0.001)
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
