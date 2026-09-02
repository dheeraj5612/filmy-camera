import CoreGraphics
import CoreImage
import UIKit
import XCTest
@testable import FilmyCamera

final class RendererOutputBoundsTests: XCTestCase {
    func testGrainControlUsesRestrainedPerceptualBlendStrength() {
        XCTAssertEqual(FilmRenderer.grainBlendOpacity(for: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(FilmRenderer.grainBlendOpacity(for: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(FilmRenderer.grainBlendOpacity(for: 0.5), 0.04, accuracy: 0.0001)
        XCTAssertEqual(FilmRenderer.grainBlendOpacity(for: 1), 0.12, accuracy: 0.0001)
        XCTAssertEqual(FilmRenderer.grainBlendOpacity(for: 2), 0.12, accuracy: 0.0001)
    }

    func testGrainAddsTextureWithoutMateriallyChangingAverageLuminance() {
        let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            .cropped(to: extent)
        var clean = FilmRecipe(id: "clean", name: "Clean", subtitle: "Test")
        clean.grain = 0
        var weak = clean
        weak.grain = 0.5
        var strong = clean
        strong.grain = 1
        let context = CIContext(options: FilmRenderer.testContextOptions)

        let cleanPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: clean),
            extent: extent,
            context: context
        )
        let weakPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: weak),
            extent: extent,
            context: context
        )
        let strongPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: strong),
            extent: extent,
            context: context
        )

        XCTAssertLessThan(abs(meanLuminance(weakPixels) - meanLuminance(cleanPixels)), 0.01)
        XCTAssertLessThan(abs(meanLuminance(strongPixels) - meanLuminance(cleanPixels)), 0.02)

        let weakTexture = meanAbsoluteRGBDifference(cleanPixels, weakPixels)
        let strongTexture = meanAbsoluteRGBDifference(cleanPixels, strongPixels)
        XCTAssertGreaterThan(weakTexture, 0.0005)
        XCTAssertLessThan(weakTexture, 0.015)
        XCTAssertGreaterThan(strongTexture, weakTexture * 1.8)
    }

    func testGrainTextureIsDeterministicMonochromeAndApproximatelyGaussian() {
        let first = FilmRenderer.deterministicGaussianGrainBytes(size: 128, seed: 42)
        let repeated = FilmRenderer.deterministicGaussianGrainBytes(size: 128, seed: 42)
        let differentSeed = FilmRenderer.deterministicGaussianGrainBytes(size: 128, seed: 43)

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, differentSeed)

        var samples: [Double] = []
        samples.reserveCapacity(first.count / 4)
        for index in stride(from: 0, to: first.count, by: 4) {
            XCTAssertEqual(first[index], first[index + 1])
            XCTAssertEqual(first[index], first[index + 2])
            XCTAssertEqual(first[index + 3], 255)
            samples.append(Double(first[index]))
        }

        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { total, sample in
            total + (sample - mean) * (sample - mean)
        } / Double(samples.count)
        let standardDeviation = sqrt(variance)
        let withinOneSigma = Double(samples.filter { abs($0 - mean) <= standardDeviation }.count)
            / Double(samples.count)
        let withinTwoSigma = Double(samples.filter { abs($0 - mean) <= standardDeviation * 2 }.count)
            / Double(samples.count)

        XCTAssertEqual(mean, 127.5, accuracy: 0.5)
        XCTAssertEqual(standardDeviation, 18, accuracy: 1)
        XCTAssertTrue((0.64...0.72).contains(withinOneSigma))
        XCTAssertTrue((0.93...0.98).contains(withinTwoSigma))
    }

    func testGrainLuminanceMaskConcentratesTextureInMidtones() {
        let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        var clean = FilmRecipe(id: "grain-mask-clean", name: "Clean", subtitle: "Test")
        clean.grain = 0
        var grain = clean
        grain.grain = 1

        func grainDifference(at luminance: CGFloat) -> Double {
            let input = CIImage(
                color: CIColor(red: luminance, green: luminance, blue: luminance, alpha: 1)
            ).cropped(to: extent)
            let cleanPixels = renderFloatPixels(
                FilmRenderer.render(input, recipe: clean, quality: .photo, grainSeed: 17),
                extent: extent,
                context: context
            )
            let grainPixels = renderFloatPixels(
                FilmRenderer.render(input, recipe: grain, quality: .photo, grainSeed: 17),
                extent: extent,
                context: context
            )
            return meanAbsoluteRGBDifference(cleanPixels, grainPixels)
        }

        let blackDifference = grainDifference(at: 0)
        let shadowDifference = grainDifference(at: 0.08)
        let midtoneDifference = grainDifference(at: 0.5)
        let highlightDifference = grainDifference(at: 0.92)
        let whiteDifference = grainDifference(at: 1)

        XCTAssertGreaterThan(midtoneDifference, 0.001)
        XCTAssertLessThan(blackDifference, midtoneDifference * 0.05)
        XCTAssertLessThan(whiteDifference, midtoneDifference * 0.05)
        XCTAssertLessThan(shadowDifference, midtoneDifference * 0.5)
        XCTAssertLessThan(highlightDifference, midtoneDifference * 0.5)
    }

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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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

    func testG7XCompactLookProducesADistinctWarmCompactResponse() throws {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let skinTone = CIImage(
            color: CIColor(red: 0.70, green: 0.43, blue: 0.30, alpha: 1)
        ).cropped(to: extent)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let neutral = FilmRecipe(
            id: "compact-neutral-control",
            name: "Compact Neutral Control",
            subtitle: "Test control"
        )

        let compactPixels = renderFloatPixels(
            FilmRenderer.render(skinTone, recipe: recipe, quality: .photo),
            extent: extent,
            context: context
        )
        let neutralPixels = renderFloatPixels(
            FilmRenderer.render(skinTone, recipe: neutral, quality: .photo),
            extent: extent,
            context: context
        )

        XCTAssertGreaterThan(meanAbsoluteRGBDifference(compactPixels, neutralPixels), 0.005)
        let compactPixel = pixel(compactPixels, width: 8, x: 4, y: 4)
        let neutralPixel = pixel(neutralPixels, width: 8, x: 4, y: 4)
        XCTAssertGreaterThan(
            compactPixel[0] - compactPixel[2],
            neutralPixel[0] - neutralPixel[2],
            "The compact recipe should preserve its intended warm portrait separation"
        )
    }

    func testClassicChromeSuppressesMagentaAndCoolsShadowsRelativeToProvia() throws {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let classicChrome = try XCTUnwrap(
            FilmRecipe.builtIns.first { $0.id == "classic-chrome" }
        )
        let provia = try XCTUnwrap(
            FilmRecipe.builtIns.first { $0.id == "provia-standard" }
        )
        let magenta = CIImage(
            color: CIColor(red: 0.72, green: 0.22, blue: 0.64, alpha: 1)
        ).cropped(to: extent)
        let coolShadow = CIImage(
            color: CIColor(red: 0.12, green: 0.17, blue: 0.34, alpha: 1)
        ).cropped(to: extent)

        let classicMagenta = pixel(
            renderFloatPixels(
                FilmRenderer.render(magenta, recipe: classicChrome, quality: .photo),
                extent: extent,
                context: context
            ),
            width: 8,
            x: 4,
            y: 4
        )
        let proviaMagenta = pixel(
            renderFloatPixels(
                FilmRenderer.render(magenta, recipe: provia, quality: .photo),
                extent: extent,
                context: context
            ),
            width: 8,
            x: 4,
            y: 4
        )
        let classicShadow = pixel(
            renderFloatPixels(
                FilmRenderer.render(coolShadow, recipe: classicChrome, quality: .photo),
                extent: extent,
                context: context
            ),
            width: 8,
            x: 4,
            y: 4
        )
        let proviaShadow = pixel(
            renderFloatPixels(
                FilmRenderer.render(coolShadow, recipe: provia, quality: .photo),
                extent: extent,
                context: context
            ),
            width: 8,
            x: 4,
            y: 4
        )

        let classicMagentaBias = (
            Double(classicMagenta[0]) + Double(classicMagenta[2])
        ) / 2 - Double(classicMagenta[1])
        let proviaMagentaBias = (
            Double(proviaMagenta[0]) + Double(proviaMagenta[2])
        ) / 2 - Double(proviaMagenta[1])

        XCTAssertLessThan(
            classicMagentaBias,
            proviaMagentaBias - 0.002,
            "Classic Chrome should selectively suppress magenta"
        )
        XCTAssertGreaterThan(
            Double(classicShadow[2] - classicShadow[0]),
            Double(proviaShadow[2] - proviaShadow[0]) + 0.002,
            "Classic Chrome should preserve cooler shadow separation"
        )
    }

    func testG7XCompactStrengthensBlueAndFoliageWithoutTintingNeutralGray() throws {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let compact = try XCTUnwrap(
            FilmRecipe.builtIns.first { $0.id == "g7x-compact" }
        )
        let neutral = FilmRecipe(
            id: "compact-reference-control",
            name: "Compact Reference Control",
            subtitle: "Test control"
        )
        let fixtures = [
            CIColor(red: 0.18, green: 0.38, blue: 0.76, alpha: 1),
            CIColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1),
            CIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
        ]

        let compactPixels = fixtures.map { color in
            pixel(
                renderFloatPixels(
                    FilmRenderer.render(
                        CIImage(color: color).cropped(to: extent),
                        recipe: compact,
                        quality: .photo
                    ),
                    extent: extent,
                    context: context
                ),
                width: 8,
                x: 4,
                y: 4
            )
        }
        let neutralPixels = fixtures.map { color in
            pixel(
                renderFloatPixels(
                    FilmRenderer.render(
                        CIImage(color: color).cropped(to: extent),
                        recipe: neutral,
                        quality: .photo
                    ),
                    extent: extent,
                    context: context
                ),
                width: 8,
                x: 4,
                y: 4
            )
        }

        XCTAssertGreaterThan(
            chroma(compactPixels[0]),
            chroma(neutralPixels[0]) + 0.003,
            "G7 X Compact should keep blue sky crisp"
        )
        XCTAssertLessThan(
            chroma(compactPixels[2]),
            0.08,
            "G7 X Compact should not impose a strong cast on neutral gray"
        )
        XCTAssertEqual(compact.grain, 0, accuracy: 0.0001)
        XCTAssertEqual(compact.halation, 0, accuracy: 0.0001)
    }

    func testFidelityReferenceLooksMatchAcrossQualityTiers() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 48)
        let input = resolutionFixture(size: extent.size)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let recipes = try ["classic-chrome", "g7x-compact"].map { identifier in
            try XCTUnwrap(
                FilmRecipe.builtIns.first { $0.id == identifier },
                "Missing fidelity reference recipe \(identifier)"
            )
        }

        for recipe in recipes {
            let outputs = [FilmRenderer.Quality.preview, .photo, .export].map {
                renderFloatPixels(
                    FilmRenderer.render(
                        input,
                        recipe: recipe,
                        quality: $0,
                        grainSeed: 0x2468,
                        grainPhase: CGPoint(x: 91.5, y: 37.25)
                    ),
                    extent: extent,
                    context: context
                )
            }
            guard let reference = outputs.first else {
                return XCTFail("Expected output for \(recipe.id)")
            }
            for output in outputs.dropFirst() {
                XCTAssertLessThan(
                    meanAbsoluteRGBDifference(reference, output),
                    0.0001,
                    "\(recipe.id) changed across quality tiers"
                )
            }
        }
    }

    func testG7XCompactToneCurveIsMonotonicAndOpensUsefulMidtones() throws {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let compact = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let neutral = replacingFilmBase(of: compact, with: .standard)

        func renderedLuma(_ value: CGFloat, recipe: FilmRecipe) -> Double {
            let image = CIImage(
                color: CIColor(red: value, green: value, blue: value, alpha: 1)
            ).cropped(to: extent)
            return luma(
                renderFloatPixels(
                    FilmRenderer.render(image, recipe: recipe, quality: .photo),
                    extent: extent,
                    context: context
                )
            )
        }

        let inputLevels: [CGFloat] = [0.02, 0.18, 0.50, 0.78, 0.95]
        let compactLevels = inputLevels.map { renderedLuma($0, recipe: compact) }
        for (lower, upper) in zip(compactLevels, compactLevels.dropFirst()) {
            XCTAssertLessThan(lower, upper, "The compact tone response must remain monotonic")
        }

        XCTAssertGreaterThan(
            renderedLuma(0.18, recipe: compact),
            renderedLuma(0.18, recipe: neutral) + 0.005,
            "The dedicated compact curve should recover useful shadow detail"
        )
        XCTAssertGreaterThan(
            renderedLuma(0.50, recipe: compact),
            renderedLuma(0.50, recipe: neutral) + 0.005,
            "The dedicated compact curve should give midtones JPEG-style presence"
        )
        XCTAssertLessThan(compactLevels.last ?? 1, 0.995, "Highlights should retain a shoulder before clipping")
    }

    func testG7XFlashContextSeparatesCenteredSubjectFromAmbientBackground() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let input = CIImage(
            color: CIColor(red: 0.42, green: 0.35, blue: 0.30, alpha: 1)
        ).cropped(to: extent)
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let captureContext = FilmRenderer.CaptureContext(
            flashFired: true,
            subjectRegions: [CGRect(x: 24, y: 24, width: 16, height: 16)]
        )
        let pixels = renderFloatPixels(
            FilmRenderer.render(
                input,
                recipe: recipe,
                quality: .photo,
                captureContext: captureContext
            ),
            extent: extent,
            context: context
        )

        let subject = pixel(pixels, width: 64, x: 32, y: 32)
        let ambient = pixel(pixels, width: 64, x: 2, y: 2)
        XCTAssertGreaterThan(
            luma(subject),
            luma(ambient) + 0.04,
            "Resolved flash captures should lift the subject while holding back ambient background"
        )
    }

    func testG7XCompactColorEmphasizesWarmSubjectsAndSkyWhileRestrainingFoliage() throws {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let compact = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let neutral = replacingFilmBase(of: compact, with: .standard)

        func rendered(_ color: CIColor, recipe: FilmRecipe) -> [Float] {
            renderFloatPixels(
                FilmRenderer.render(
                    CIImage(color: color).cropped(to: extent),
                    recipe: recipe,
                    quality: .photo
                ),
                extent: extent,
                context: context
            )
        }

        let skin = rendered(CIColor(red: 0.70, green: 0.43, blue: 0.30, alpha: 1), recipe: compact)
        let neutralSkin = rendered(CIColor(red: 0.70, green: 0.43, blue: 0.30, alpha: 1), recipe: neutral)
        // The compact profile pushes skin toward peach/pink rather than tan:
        // a little blue returns while the tone stays clearly rosy.
        XCTAssertGreaterThan(
            Double(skin[2]),
            Double(neutralSkin[2]),
            "Peach/pink skin keeps a little more blue than a plain warm render"
        )
        XCTAssertGreaterThan(
            Double(skin[0] - skin[1]),
            0.25,
            "Skin should stay clearly rosy"
        )

        let red = rendered(CIColor(red: 0.72, green: 0.16, blue: 0.12, alpha: 1), recipe: compact)
        let neutralRed = rendered(CIColor(red: 0.72, green: 0.16, blue: 0.12, alpha: 1), recipe: neutral)
        XCTAssertGreaterThan(
            Double(red[0] - max(red[1], red[2])),
            Double(neutralRed[0] - max(neutralRed[1], neutralRed[2]))
        )

        let foliage = rendered(CIColor(red: 0.18, green: 0.56, blue: 0.20, alpha: 1), recipe: compact)
        let neutralFoliage = rendered(CIColor(red: 0.18, green: 0.56, blue: 0.20, alpha: 1), recipe: neutral)
        XCTAssertLessThan(
            rgbChroma(foliage),
            rgbChroma(neutralFoliage),
            "Foliage should remain rich without receiving a blanket saturation boost"
        )

        let sky = rendered(CIColor(red: 0.16, green: 0.42, blue: 0.78, alpha: 1), recipe: compact)
        let neutralSky = rendered(CIColor(red: 0.16, green: 0.42, blue: 0.78, alpha: 1), recipe: neutral)
        XCTAssertGreaterThan(
            Double(sky[2] - sky[0]),
            Double(neutralSky[2] - neutralSky[0])
        )

        let gray = rendered(CIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1), recipe: compact)
        let grayChroma = Double(max(gray[0], max(gray[1], gray[2])) - min(gray[0], min(gray[1], gray[2])))
        XCTAssertLessThan(grayChroma, 0.020, "Neutral subjects should not receive a strong color cast")
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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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

    func testDRangePriorityAddsDeterministicHighlightProtection() {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let input = CIImage(color: CIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let base = FilmRecipe(
            id: "test-drp",
            name: "D Range Priority",
            subtitle: "Test",
            dynamicRange: .dr100,
            grain: 0,
            vignette: 0,
            halation: 0
        )
        var strong = base
        strong.dRangePriority = .strong

        let basePixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: base, quality: .photo),
            extent: extent,
            context: context
        )
        let strongPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: strong, quality: .photo),
            extent: extent,
            context: context
        )

        XCTAssertLessThan(strongPixels[0], basePixels[0])
    }

    func testMonochromeFiltersUseDistinctChannelMixes() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: FilmRenderer.testContextOptions)
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

    func testMonochromaticWarmCoolAxisMovesTintInDeclaredDirectionAcrossBases() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let source = CIImage(color: CIColor(red: 0.76, green: 0.25, blue: 0.12, alpha: 1))
            .cropped(to: extent)
        let bases: [FilmRecipe.FilmBase] = [.acros, .monochrome, .sepia]

        for filmBase in bases {
            let base = FilmRecipe(
                id: "mono-warm-cool-\(filmBase.rawValue)",
                name: filmBase.displayName,
                subtitle: "Test",
                filmBase: filmBase,
                saturation: 0,
                grain: 0,
                vignette: 0,
                halation: 0,
                palette: FilmRecipe.Palette(saturation: 0)
            )
            var neutral = base
            neutral.monochromaticColor = .init()
            var warm = base
            warm.monochromaticColor.warmCool = 1
            var cool = base
            cool.monochromaticColor.warmCool = -1

            func redBlueBias(_ recipe: FilmRecipe) -> Double {
                let pixel = renderFloatPixels(
                    FilmRenderer.render(source, recipe: recipe, quality: .photo),
                    extent: extent,
                    context: context
                )
                return Double(pixel[0]) - Double(pixel[2])
            }

            let neutralBias = redBlueBias(neutral)
            XCTAssertGreaterThan(
                redBlueBias(warm),
                neutralBias + 0.01,
                "Positive warm-cool axis was not warmer for \(filmBase.rawValue)"
            )
            XCTAssertLessThan(
                redBlueBias(cool),
                neutralBias - 0.01,
                "Negative warm-cool axis was not cooler for \(filmBase.rawValue)"
            )
        }
    }

    func testMonochromaticGreenMagentaAxisMovesTintInDeclaredDirectionAcrossBases() {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let source = CIImage(color: CIColor(red: 0.76, green: 0.25, blue: 0.12, alpha: 1))
            .cropped(to: extent)
        let bases: [FilmRecipe.FilmBase] = [.acros, .monochrome, .sepia]

        for filmBase in bases {
            let base = FilmRecipe(
                id: "mono-green-magenta-\(filmBase.rawValue)",
                name: filmBase.displayName,
                subtitle: "Test",
                filmBase: filmBase,
                saturation: 0,
                grain: 0,
                vignette: 0,
                halation: 0,
                palette: FilmRecipe.Palette(saturation: 0)
            )
            var neutral = base
            neutral.monochromaticColor = .init()
            var magenta = base
            magenta.monochromaticColor.greenMagenta = 1
            var green = base
            green.monochromaticColor.greenMagenta = -1

            func magentaBias(_ recipe: FilmRecipe) -> Double {
                let pixel = renderFloatPixels(
                    FilmRenderer.render(source, recipe: recipe, quality: .photo),
                    extent: extent,
                    context: context
                )
                return (Double(pixel[0]) + Double(pixel[2])) * 0.5 - Double(pixel[1])
            }

            let neutralBias = magentaBias(neutral)
            XCTAssertGreaterThan(
                magentaBias(magenta),
                neutralBias + 0.01,
                "Positive green-magenta axis was not more magenta for \(filmBase.rawValue)"
            )
            XCTAssertLessThan(
                magentaBias(green),
                neutralBias - 0.01,
                "Negative green-magenta axis was not greener for \(filmBase.rawValue)"
            )
        }
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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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

    func testHalationIsDerivedBeforeFinalGrainTexture() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 48)
        let background = CIImage(
            color: CIColor(red: 0.16, green: 0.14, blue: 0.12, alpha: 1)
        ).cropped(to: extent)
        let highlight = CIImage(
            color: CIColor(red: 0.98, green: 0.92, blue: 0.82, alpha: 1)
        )
        .cropped(to: CGRect(x: 26, y: 18, width: 12, height: 12))
        let source = highlight.composited(over: background)
        let context = CIContext(options: FilmRenderer.testContextOptions)

        let base = FilmRecipe(
            id: "finishing-order",
            name: "Finishing Order",
            subtitle: "Test",
            filmBase: .standard,
            saturation: 1,
            contrast: 1,
            grain: 0,
            vignette: 0,
            halation: 0
        )
        var halationOnly = base
        halationOnly.halation = 0.8
        var grainOnly = base
        grainOnly.grain = 0.7
        grainOnly.grainSize = 1.2
        var combined = grainOnly
        combined.halation = halationOnly.halation

        let combinedPixels = renderFloatPixels(
            FilmRenderer.render(source, recipe: combined, quality: .photo, grainSeed: 91),
            extent: extent,
            context: context
        )
        let halated = FilmRenderer.render(source, recipe: halationOnly, quality: .photo)
        let sequentialPixels = renderFloatPixels(
            FilmRenderer.render(halated, recipe: grainOnly, quality: .photo, grainSeed: 91),
            extent: extent,
            context: context
        )

        XCTAssertLessThan(
            meanAbsoluteRGBDifference(combinedPixels, sequentialPixels),
            0.001,
            "Combined finishing should match halation followed by grain"
        )
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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

    func testPersistedKelvinWhiteBalanceChangesRenderedOutput() {
        let extent = CGRect(x: 0, y: 0, width: 2, height: 2)
        let input = CIImage(color: CIColor(red: 0.56, green: 0.42, blue: 0.30, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        var warm = FilmRecipe.builtIns[0]
        warm.whiteBalance.mode = .colorTemperature
        warm.whiteBalance.kelvin = 2500
        var cool = warm
        cool.whiteBalance.kelvin = 10000

        let warmPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: warm, quality: .photo),
            extent: extent,
            context: context
        )
        let coolPixels = renderFloatPixels(
            FilmRenderer.render(input, recipe: cool, quality: .photo),
            extent: extent,
            context: context
        )

        let distance = zip(warmPixels, coolPixels)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertGreaterThan(distance, 0.001)
    }

    func testNonColorTemperatureWhiteBalanceIgnoresPersistedKelvin() {
        let extent = CGRect(x: 0, y: 0, width: 2, height: 2)
        let input = CIImage(color: CIColor(red: 0.56, green: 0.42, blue: 0.30, alpha: 1))
            .cropped(to: extent)
        let context = CIContext(options: FilmRenderer.testContextOptions)
        var daylightKelvin = FilmRecipe.builtIns[0]
        daylightKelvin.whiteBalance.mode = .daylight
        daylightKelvin.whiteBalance.kelvin = 2500
        var daylightOtherKelvin = daylightKelvin
        daylightOtherKelvin.whiteBalance.kelvin = 10000

        let first = renderFloatPixels(
            FilmRenderer.render(input, recipe: daylightKelvin, quality: .photo),
            extent: extent,
            context: context
        )
        let second = renderFloatPixels(
            FilmRenderer.render(input, recipe: daylightOtherKelvin, quality: .photo),
            extent: extent,
            context: context
        )

        let distance = zip(first, second)
            .map { abs(Double($0.0) - Double($0.1)) }
            .reduce(0, +)
        XCTAssertLessThan(distance, 0.0001)
    }

    func testNegativeClarityUsesBlurBlendAndPositiveClarityRemainsActiveAtMultipleSizes() {
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)
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
        let context = CIContext(options: FilmRenderer.testContextOptions)

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

    func testEveryBuiltInUsesIdenticalPixelsAcrossPreviewPhotoAndExport() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 48)
        let input = resolutionFixture(size: extent.size)
        let phase = CGPoint(x: 173.5, y: 61.25)
        let context = CIContext(options: FilmRenderer.testContextOptions)

        for recipe in FilmRecipe.builtIns {
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
                return XCTFail("Expected renderer output for \(recipe.id)")
            }
            for (index, output) in outputs.dropFirst().enumerated() {
                XCTAssertEqual(output.count, reference.count, recipe.id)
                XCTAssertLessThan(
                    meanAbsoluteRGBDifference(reference, output),
                    0.0001,
                    "\(recipe.id) changed at quality tier \(index + 1)"
                )
            }
        }
    }

    func testEveryBuiltInThumbnailUsesTheRendererAndRequestedSize() {
        let size = CGSize(width: 120, height: 80)
        for recipe in FilmRecipe.builtIns {
            let image = FilmRenderer.thumbnail(for: recipe, size: size)

            XCTAssertNotNil(image, recipe.id)
            XCTAssertEqual(image?.cgImage?.width, Int(size.width), recipe.id)
            XCTAssertEqual(image?.cgImage?.height, Int(size.height), recipe.id)
        }
    }

    func testRecipeThumbnailCacheReusesImageAndSeparatesRenderKeys() throws {
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first)
        let size = CGSize(width: 96, height: 64)

        let first = try XCTUnwrap(FilmRenderer.thumbnail(for: recipe, size: size))
        let second = try XCTUnwrap(FilmRenderer.thumbnail(for: recipe, size: size))
        XCTAssertTrue(first === second, "Identical recipe thumbnails should reuse the materialized image")

        let resized = try XCTUnwrap(
            FilmRenderer.thumbnail(for: recipe, size: CGSize(width: 120, height: 64))
        )
        XCTAssertFalse(first === resized, "Thumbnail dimensions must remain part of the cache key")
        XCTAssertEqual(resized.cgImage?.width, 120)
        XCTAssertEqual(resized.cgImage?.height, 64)

        var tuned = recipe
        tuned.exposure += 0.1
        let tunedImage = try XCTUnwrap(FilmRenderer.thumbnail(for: tuned, size: size))
        XCTAssertFalse(first === tunedImage, "Edited recipe values must render a distinct thumbnail")
    }

    func testRecipeContactSheetRendersEveryBuiltInLook() throws {
        let tileSize = CGSize(width: 264, height: 160)
        let labelHeight: CGFloat = 30
        let columns = 3
        let thumbnails = try FilmRecipe.builtIns.map { recipe in
            (
                recipe,
                try XCTUnwrap(
                    FilmRenderer.thumbnail(for: recipe, size: tileSize),
                    "Missing thumbnail for \(recipe.id)"
                )
            )
        }
        let rows = Int(
            ceil(Double(thumbnails.count) / Double(columns))
        )
        let canvasSize = CGSize(
            width: tileSize.width * CGFloat(columns),
            height: (tileSize.height + labelHeight) * CGFloat(rows)
        )
        let image = UIGraphicsImageRenderer(size: canvasSize).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: canvasSize))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(
                    ofSize: 12,
                    weight: .semibold
                ),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]

            for (index, entry) in thumbnails.enumerated() {
                let column = index % columns
                let row = index / columns
                let origin = CGPoint(
                    x: CGFloat(column) * tileSize.width,
                    y: CGFloat(row) * (tileSize.height + labelHeight)
                )
                entry.1.draw(in: CGRect(origin: origin, size: tileSize))
                (entry.0.name as NSString).draw(
                    in: CGRect(
                        x: origin.x,
                        y: origin.y + tileSize.height + 5,
                        width: tileSize.width,
                        height: labelHeight - 5
                    ),
                    withAttributes: attributes
                )
            }
        }

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = "all-recipe-contact-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
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

    private func chroma(_ pixel: [Float]) -> Double {
        let red = Double(pixel[0])
        let green = Double(pixel[1])
        let blue = Double(pixel[2])
        return max(red, max(green, blue)) - min(red, min(green, blue))
    }

    private func rgbChroma(_ pixel: [Float]) -> Double {
        Double(max(pixel[0], max(pixel[1], pixel[2])) - min(pixel[0], min(pixel[1], pixel[2])))
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

    private func meanLuminance(_ pixels: [Float]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        var total = 0.0
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[index])
                + 0.7152 * Double(pixels[index + 1])
                + 0.0722 * Double(pixels[index + 2])
            count += 1
        }
        return total / Double(count)
    }

    private func replacingFilmBase(
        of recipe: FilmRecipe,
        with filmBase: FilmRecipe.FilmBase
    ) -> FilmRecipe {
        FilmRecipe(
            id: "\(recipe.id)-\(filmBase.rawValue)-control",
            name: recipe.name,
            subtitle: recipe.subtitle,
            filmBase: filmBase,
            exposure: recipe.exposure,
            tone: recipe.tone,
            saturation: recipe.saturation,
            contrast: recipe.contrast,
            dynamicRange: recipe.dynamicRange,
            dRangePriority: recipe.dRangePriority,
            whiteBalance: recipe.whiteBalance,
            monochromaticColor: recipe.monochromaticColor,
            colorChrome: recipe.colorChrome,
            blueResponse: recipe.blueResponse,
            fxBlue: recipe.fxBlue,
            sharpness: recipe.sharpness,
            noiseReduction: recipe.noiseReduction,
            clarity: recipe.clarity,
            grain: recipe.grain,
            grainSize: recipe.grainSize,
            vignette: recipe.vignette,
            halation: recipe.halation,
            palette: recipe.palette,
            provenance: recipe.provenance
        )
    }
}
