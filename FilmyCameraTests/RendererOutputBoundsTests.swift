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

    func testOpaqueCopyReplacesSourceAlpha() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        var referenceRGB: [Float]?
        for sourceAlpha in [1.0, 0.35] {
            // Make the non-opaque fixture explicitly premultiplied, matching
            // the representation used by Core Image pixel buffers.
            let input = CIImage(color: CIColor(red: 0.42, green: 0.18, blue: 0.76, alpha: sourceAlpha))
                .premultiplyingAlpha()
                .cropped(to: extent)
            let pixels = renderFloatPixels(
                FilmRenderer.opaqueImage(from: input),
                extent: extent,
                context: context
            )

            XCTAssertEqual(pixels.count, 4)
            XCTAssertEqual(pixels[3], 1, accuracy: 0.001, "Source alpha \(sourceAlpha) was not replaced")
            if let referenceRGB {
                for channel in 0..<3 {
                    XCTAssertEqual(
                        pixels[channel],
                        referenceRGB[channel],
                        accuracy: 0.01,
                        "RGB channel \(channel) changed with source alpha"
                    )
                }
            } else {
                referenceRGB = Array(pixels.prefix(3))
            }
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

    func testLegacyNegativeFXBlueRendersAsOff() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let input = CIImage(color: CIColor(red: 0.08, green: 0.18, blue: 0.90, alpha: 1)).cropped(to: extent)
        var off = FilmRecipe.builtIns[0]
        off.fxBlue = 0
        var legacy = off
        legacy.fxBlue = -1

        let offPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: off, quality: .photo),
            extent: extent,
            context: context
        )
        let legacyPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: legacy, quality: .photo),
            extent: extent,
            context: context
        )

        let difference = zip(offPixels, legacyPixels)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertLessThan(difference, 0.0001)
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

    func testNegativeClarityUsesBlurBlendAndPositiveClarityRemainsActiveAtMultipleSizes() {
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
        let sizes = [
            CGSize(width: 256, height: 192),
            CGSize(width: 1024, height: 768)
        ]
        let base = FilmRecipe(
            id: "clarity-regression",
            name: "Clarity regression",
            subtitle: "Test",
            grain: 0,
            vignette: 0,
            halation: 0
        )
        var softened = base
        softened.clarity = -1
        var sharpened = base
        sharpened.clarity = 1

        for size in sizes {
            let extent = CGRect(origin: .zero, size: size)
            let input = resolutionFixture(size: size)
            let neutralPixels = renderFloatPixels(
                FilmRenderer.render(input, recipe: base, quality: .photo),
                extent: extent,
                context: context
            )
            let softenedPixels = renderFloatPixels(
                FilmRenderer.render(input, recipe: softened, quality: .photo),
                extent: extent,
                context: context
            )
            let sharpenedPixels = renderFloatPixels(
                FilmRenderer.render(input, recipe: sharpened, quality: .photo),
                extent: extent,
                context: context
            )

            let softenedDistance = meanAbsoluteRGBDifference(neutralPixels, softenedPixels)
            XCTAssertGreaterThan(
                softenedDistance,
                0.0005,
                "Negative clarity was a no-op at \(size)"
            )

            let boundary = Int(size.width / 4)
            let left = pixel(
                softenedPixels,
                width: Int(size.width),
                x: boundary - 2,
                y: Int(size.height / 2)
            )
            let right = pixel(
                softenedPixels,
                width: Int(size.width),
                x: boundary + 2,
                y: Int(size.height / 2)
            )
            let neutralLeft = pixel(
                neutralPixels,
                width: Int(size.width),
                x: boundary - 2,
                y: Int(size.height / 2)
            )
            let neutralRight = pixel(
                neutralPixels,
                width: Int(size.width),
                x: boundary + 2,
                y: Int(size.height / 2)
            )
            let sharpenedLeft = pixel(
                sharpenedPixels,
                width: Int(size.width),
                x: boundary - 2,
                y: Int(size.height / 2)
            )
            let sharpenedRight = pixel(
                sharpenedPixels,
                width: Int(size.width),
                x: boundary + 2,
                y: Int(size.height / 2)
            )

            let neutralContrast = abs(luma(neutralLeft) - luma(neutralRight))
            let softenedContrast = abs(luma(left) - luma(right))
            let sharpenedContrast = abs(luma(sharpenedLeft) - luma(sharpenedRight))
            XCTAssertLessThan(
                softenedContrast,
                neutralContrast,
                "Negative clarity did not reduce edge contrast at \(size)"
            )
            XCTAssertGreaterThan(
                sharpenedContrast,
                neutralContrast,
                "Positive clarity stopped sharpening edges at \(size)"
            )
        }
    }

    func testVignetteUsesNormalizedRadiusWithCenterAndEdgeBehaviorAtMultipleSizes() {
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
        let sizes = [
            CGSize(width: 256, height: 192),
            CGSize(width: 1024, height: 768)
        ]
        var recipe = FilmRecipe(
            id: "vignette-regression",
            name: "Vignette regression",
            subtitle: "Test",
            grain: 0,
            halation: 0
        )
        recipe.vignette = 0.5

        for size in sizes {
            let extent = CGRect(origin: .zero, size: size)
            let input = CIImage(
                color: CIColor(red: 0.72, green: 0.72, blue: 0.72, alpha: 1)
            ).cropped(to: extent)
            let pixels = renderFloatPixels(
                FilmRenderer.render(input, recipe: recipe, quality: .photo),
                extent: extent,
                context: context
            )
            let width = Int(size.width)
            let center = pixel(
                pixels,
                width: width,
                x: width / 2,
                y: Int(size.height) / 2
            )
            let corner = pixel(pixels, width: width, x: 0, y: 0)
            let centerLuma = luma(center)
            let cornerLuma = luma(corner)

            XCTAssertGreaterThan(
                centerLuma - cornerLuma,
                0.04,
                "Vignette did not darken the edge at \(size)"
            )
            XCTAssertGreaterThan(
                cornerLuma / centerLuma,
                0.60,
                "Vignette radius was treated as an over-large pixel value at \(size)"
            )
        }
    }

    func testResolutionNormalizedSpatialEffectsMatchAfterDownsamplingPhotoToPreviewSize() {
        let previewSize = CGSize(width: 720, height: 540)
        let photoSize = CGSize(width: 1440, height: 1080)
        let previewExtent = CGRect(origin: .zero, size: previewSize)
        var recipe = FilmRecipe(
            id: "resolution-parity",
            name: "Resolution parity",
            subtitle: "Test",
            sharpness: 0.35,
            clarity: 0.72,
            grain: 0.42,
            grainSize: 1.15,
            vignette: 0.5,
            halation: 0.45
        )
        recipe.dynamicRange = .dr100

        let previewInput = resolutionFixture(size: previewSize)
        let photoInput = resolutionFixture(size: photoSize)
        let previewOutput = FilmRenderer.render(
            previewInput,
            recipe: recipe,
            quality: .preview,
            grainSeed: 23
        )
        let photoOutput = FilmRenderer.render(
            photoInput,
            recipe: recipe,
            quality: .photo,
            grainSeed: 23
        )
        let downsampledPhoto = downsample(photoOutput, to: previewSize)
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
        let previewPixels = renderFloatPixels(
            previewOutput,
            extent: previewExtent,
            context: context
        )
        let downsampledPhotoPixels = renderFloatPixels(
            downsampledPhoto,
            extent: previewExtent,
            context: context
        )

        XCTAssertLessThan(
            meanAbsoluteRGBDifference(previewPixels, downsampledPhotoPixels),
            0.045,
            "Preview and downsampled photo diverged after spatial normalization"
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

    func testPreviewPhotoAndExportUseIdenticalPixelsForFixedRecipePhase() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 48)
        let input = resolutionFixture(size: extent.size)
        var recipe = FilmRecipe.builtIns[7]
        recipe.exposure = 0.35
        recipe.clarity = -0.42
        recipe.grain = 0.58
        recipe.grainSize = 1.25
        recipe.vignette = 0.44
        recipe.halation = 0.52
        let phase = CGPoint(x: 173.5, y: 61.25)
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])

        let outputs = [FilmRenderer.Quality.preview, .photo, .export].map { quality in
            renderFloatPixels(
                FilmRenderer.render(
                    input,
                    recipe: recipe,
                    quality: quality,
                    grainSeed: 0x1234,
                    grainPhase: phase
                ),
                extent: extent,
                context: context
            )
        }

        guard let reference = outputs.first else {
            return XCTFail("Expected renderer output for the preview quality")
        }
        for (index, output) in outputs.dropFirst().enumerated() {
            XCTAssertEqual(output.count, reference.count)
            XCTAssertLessThan(
                meanAbsoluteRGBDifference(reference, output),
                0.0001,
                "Quality tier \(index + 1) changed the recipe pixels"
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

    private func resolutionFixture(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        var image = CIImage(
            color: CIColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
        ).cropped(to: extent)
        let stripeCount = 8
        for index in 0..<stripeCount {
            let stripe = CGRect(
                x: size.width * CGFloat(index) / CGFloat(stripeCount),
                y: 0,
                width: size.width / CGFloat(stripeCount) + 1,
                height: size.height
            )
            let color = index.isMultiple(of: 2)
                ? CIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1)
                : CIColor(red: 0.74, green: 0.43, blue: 0.16, alpha: 1)
            image = CIImage(color: color)
                .cropped(to: stripe)
                .composited(over: image)
        }

        let highlightRects: [(CGRect, CIColor)] = [
            (
                CGRect(
                    x: size.width * 0.12,
                    y: size.height * 0.18,
                    width: size.width * 0.18,
                    height: size.height * 0.24
                ),
                CIColor(red: 0.98, green: 0.90, blue: 0.70, alpha: 1)
            ),
            (
                CGRect(
                    x: size.width * 0.62,
                    y: size.height * 0.48,
                    width: size.width * 0.22,
                    height: size.height * 0.28
                ),
                CIColor(red: 0.92, green: 0.96, blue: 0.98, alpha: 1)
            )
        ]
        for (rect, color) in highlightRects {
            image = CIImage(color: color)
                .cropped(to: rect)
                .composited(over: image)
        }
        return image
    }

    private func downsample(_ image: CIImage, to size: CGSize) -> CIImage {
        let scale = size.width / image.extent.width
        return image
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1
            ])
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func pixel(
        _ pixels: [Float],
        width: Int,
        x: Int,
        y: Int
    ) -> [Float] {
        let index = (y * width + x) * 4
        return Array(pixels[index..<(index + 4)])
    }

    private func luma(_ pixel: [Float]) -> Double {
        0.2126 * Double(pixel[0])
            + 0.7152 * Double(pixel[1])
            + 0.0722 * Double(pixel[2])
    }

    private func meanAbsoluteRGBDifference(_ lhs: [Float], _ rhs: [Float]) -> Double {
        var total = 0.0
        var count = 0
        for index in stride(from: 0, to: min(lhs.count, rhs.count), by: 4) {
            for channel in 0..<3 {
                total += abs(Double(lhs[index + channel]) - Double(rhs[index + channel]))
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }
}
