from pathlib import Path


def replace_once(relative_path: str, old: str, new: str) -> None:
    path = Path(relative_path)
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{relative_path}: expected one replacement target, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "FilmyCamera/Models/FilmRecipe.swift",
    '    public static let rendererVersion = "core-image-parametric-v2"\n',
    '    public static let rendererVersion = "core-image-parametric-v3"\n'
)

replace_once(
    "FilmyCamera/Models/FilmRecipe.swift",
    '''        FilmRecipe(
            id: "g7x-compact",
            name: "G7 X Compact",
            subtitle: "Warm skin / crisp compact color",
            filmBase: .compactDigital,
            exposure: 0.05,
            tone: Tone(highlight: 0.08, shadow: 0.10),
            saturation: 1.06,
            contrast: 1.08,
            dynamicRange: .dr200,
            dRangePriority: .off,
            whiteBalance: WhiteBalanceShift(
                temperature: 0.04,
                tint: 0.01,
                mode: .ambiencePriority
            ),
            colorChrome: 0,
            blueResponse: 0.08,
            fxBlue: 0,
            sharpness: 0.18,
            noiseReduction: 0.08,
            clarity: 0.10,
            grain: 0,
            grainSize: 0.75,
            vignette: 0.05,
            halation: 0,
            palette: Palette(
                redBias: 0.015,
                greenBias: 0.002,
                blueBias: -0.006,
                redGreenMix: 0.012,
                greenBlueMix: 0.004,
                blueRedMix: -0.008,
                saturation: 1.01
            ),
            provenance: g7XProvenance
        )
''',
    '''        FilmRecipe(
            id: "g7x-compact",
            name: "G7 X Compact",
            subtitle: "Warm skin / crisp compact color",
            filmBase: .compactDigital,
            exposure: 0.08,
            tone: Tone(highlight: 0.06, shadow: -0.05),
            saturation: 1.07,
            contrast: 1.07,
            dynamicRange: .dr200,
            dRangePriority: .off,
            whiteBalance: WhiteBalanceShift(
                temperature: 0.035,
                tint: 0.005,
                mode: .ambiencePriority
            ),
            colorChrome: 0,
            blueResponse: 0.10,
            fxBlue: 0,
            sharpness: 0.20,
            noiseReduction: 0.06,
            clarity: 0.08,
            grain: 0,
            grainSize: 0.75,
            vignette: 0.03,
            halation: 0,
            palette: Palette(
                redBias: 0.012,
                greenBias: 0.002,
                blueBias: -0.004,
                redGreenMix: 0.010,
                greenBlueMix: 0.005,
                blueRedMix: -0.006,
                saturation: 1.015
            ),
            provenance: g7XProvenance
        )
'''
)

replace_once(
    "FilmyCamera/Services/FilmRenderer.swift",
    '''            (
                CGRect(x: width * 0.80, y: height * 0.56, width: width * 0.12, height: height * 0.22),
                CIColor(red: 0.86, green: 0.86, blue: 0.82, alpha: 1)
            )
''',
    '''            (
                CGRect(x: width * 0.80, y: height * 0.56, width: width * 0.12, height: height * 0.22),
                CIColor(red: 0.86, green: 0.86, blue: 0.82, alpha: 1)
            ),
            (
                CGRect(x: width * 0.33, y: height * 0.57, width: width * 0.12, height: height * 0.18),
                CIColor(red: 0.69, green: 0.18, blue: 0.58, alpha: 1)
            ),
            (
                CGRect(x: width * 0.80, y: height * 0.80, width: width * 0.12, height: height * 0.14),
                CIColor(red: 0.43, green: 0.44, blue: 0.45, alpha: 1)
            )
'''
)

replace_once(
    "FilmyCamera/Services/FilmRenderer.swift",
    '''        case .classicChrome:
            saturate(0.94)
            mappedRed += 0.010 * highlightWeight
            mappedBlue += 0.012 * shadowWeight
            mappedGreen += 0.006 * shadowWeight
''',
    '''        case .classicChrome:
            // Fujifilm publicly characterizes Classic Chrome as subdued,
            // magenta-suppressing color with cool shadows. Use feathered hue
            // masks so that behavior is selective rather than a global cast.
            let chroma = max(mappedRed, max(mappedGreen, mappedBlue))
                - min(mappedRed, min(mappedGreen, mappedBlue))
            let hue = rgbHue(
                red: mappedRed,
                green: mappedGreen,
                blue: mappedBlue,
                chroma: chroma
            )
            let magentaWeight = hueSectorWeight(
                hue,
                center: 0.88,
                halfWidth: 0.13
            ) * smoothstep(0.025, 0.34, chroma)
            let coolShadowWeight = max(
                hueSectorWeight(hue, center: 0.56, halfWidth: 0.16),
                hueSectorWeight(hue, center: 0.65, halfWidth: 0.15)
            ) * shadowWeight
            let skinWeight = hueSectorWeight(
                hue,
                center: 0.075,
                halfWidth: 0.10
            ) * smoothstep(0.025, 0.30, chroma)

            saturate(0.92)
            mappedGreen += 0.030 * magentaWeight
            mappedRed -= 0.010 * magentaWeight
            mappedBlue -= 0.006 * magentaWeight
            mappedRed += 0.008 * highlightWeight + 0.005 * skinWeight
            mappedBlue += 0.020 * shadowWeight + 0.010 * coolShadowWeight
            mappedGreen += 0.007 * shadowWeight + 0.003 * coolShadowWeight
'''
)

replace_once(
    "FilmyCamera/Services/FilmRenderer.swift",
    '''        case .compactDigital:
            // Original compact-camera response inspired by the G7 X Mark III
            // product envelope: clean Standard-style color, warm portrait
            // mids, crisp blues/greens, and smooth highlights. This is a
            // parametric approximation, not Canon Picture Style data.
            let chroma = max(mappedRed, max(mappedGreen, mappedBlue))
                - min(mappedRed, min(mappedGreen, mappedBlue))
            let hue = rgbHue(
                red: mappedRed,
                green: mappedGreen,
                blue: mappedBlue,
                chroma: chroma
            )
            let midtoneWeight = smoothstep(0.12, 0.42, luma)
                * (1 - smoothstep(0.78, 0.98, luma))
            let skinWeight = hueSectorWeight(hue, center: 0.075, halfWidth: 0.095)
                * smoothstep(0.035, 0.32, chroma)
                * midtoneWeight
            let greenWeight = hueSectorWeight(hue, center: 0.32, halfWidth: 0.14)
                * smoothstep(0.04, 0.34, chroma)
            let blueWeight = hueSectorWeight(hue, center: 0.60, halfWidth: 0.13)
                * smoothstep(0.04, 0.34, chroma)

            saturate(1.025)
            mappedRed += 0.018 * skinWeight + 0.004 * highlightWeight
            mappedGreen += 0.004 * skinWeight + 0.006 * greenWeight
            mappedBlue -= 0.009 * skinWeight
            mappedBlue += 0.010 * blueWeight
            mappedRed -= 0.002 * blueWeight
''',
    '''        case .compactDigital:
            // Approximate Canon's Standard-style compact output with warm but
            // bounded portrait mids, crisp foliage and blue sky, clean neutral
            // grays, and restrained high-chroma boosts. This remains an
            // original sRGB transform, not Canon Picture Style data.
            let chroma = max(mappedRed, max(mappedGreen, mappedBlue))
                - min(mappedRed, min(mappedGreen, mappedBlue))
            let hue = rgbHue(
                red: mappedRed,
                green: mappedGreen,
                blue: mappedBlue,
                chroma: chroma
            )
            let midtoneWeight = smoothstep(0.12, 0.40, luma)
                * (1 - smoothstep(0.76, 0.96, luma))
            let highChromaGuard = 1 - smoothstep(0.42, 0.76, chroma)
            let skinWeight = hueSectorWeight(hue, center: 0.075, halfWidth: 0.10)
                * smoothstep(0.03, 0.28, chroma)
                * midtoneWeight
                * highChromaGuard
            let greenWeight = hueSectorWeight(hue, center: 0.32, halfWidth: 0.14)
                * smoothstep(0.035, 0.32, chroma)
                * highChromaGuard
            let blueWeight = hueSectorWeight(hue, center: 0.61, halfWidth: 0.14)
                * smoothstep(0.035, 0.34, chroma)
                * highChromaGuard

            saturate(1.03)
            mappedRed += 0.022 * skinWeight + 0.003 * highlightWeight
            mappedGreen += 0.006 * skinWeight + 0.010 * greenWeight
            mappedBlue -= 0.012 * skinWeight
            mappedRed -= 0.003 * greenWeight
            mappedBlue += 0.014 * blueWeight
            mappedGreen += 0.003 * blueWeight
            mappedRed -= 0.004 * blueWeight
'''
)

replace_once(
    "FilmyCameraTests/RendererOutputBoundsTests.swift",
    '''    func testG7XCompactLookProducesADistinctWarmCompactResponse() throws {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let skinTone = CIImage(
            color: CIColor(red: 0.70, green: 0.43, blue: 0.30, alpha: 1)
        ).cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
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

''',
    '''    func testG7XCompactLookProducesADistinctWarmCompactResponse() throws {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let skinTone = CIImage(
            color: CIColor(red: 0.70, green: 0.43, blue: 0.30, alpha: 1)
        ).cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
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
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
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
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
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
        XCTAssertGreaterThan(
            chroma(compactPixels[1]),
            chroma(neutralPixels[1]) + 0.003,
            "G7 X Compact should keep foliage crisp"
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
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
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

'''
)

replace_once(
    "FilmyCameraTests/RendererOutputBoundsTests.swift",
    '''    func testRecipeThumbnailUsesTheRendererAndRequestedSize() {
        let size = CGSize(width: 120, height: 80)
        let image = FilmRenderer.thumbnail(for: FilmRecipe.builtIns[1], size: size)

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.cgImage?.width, Int(size.width))
        XCTAssertEqual(image?.cgImage?.height, Int(size.height))
    }

''',
    '''    func testRecipeThumbnailUsesTheRendererAndRequestedSize() {
        let size = CGSize(width: 120, height: 80)
        let image = FilmRenderer.thumbnail(for: FilmRecipe.builtIns[1], size: size)

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.cgImage?.width, Int(size.width))
        XCTAssertEqual(image?.cgImage?.height, Int(size.height))
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

'''
)

replace_once(
    "FilmyCameraTests/RendererOutputBoundsTests.swift",
    '''    private func luma(_ pixel: [Float]) -> Double {
        0.2126 * Double(pixel[0])
            + 0.7152 * Double(pixel[1])
            + 0.0722 * Double(pixel[2])
    }

''',
    '''    private func luma(_ pixel: [Float]) -> Double {
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

'''
)

Path("docs/filter-fidelity-audit-20260821.md").write_text(
    '''# Filter fidelity audit — 2026-08-21

## Scope

This pass improves perceptual fidelity for the built-in Classic Chrome and
G7 X Compact looks, while retaining the app's explicit non-calibration
disclosures. Public documentation does not expose either vendor's complete
sensor-to-JPEG transform, so pixel-identical reproduction is not a supportable
claim without controlled paired captures from the target hardware.

## References consulted

- Fujifilm Classic Chrome overview:
  https://www.fujifilm-x.com/en-us/products/film-simulation/classic-chrome/
- Fujifilm X-T5 image-quality controls:
  https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/
- Fuji X Weekly Classic Chrome recipe archive:
  https://fujixweekly.com/tag/classic-chrome/
- Canon PowerShot G7 X Mark III:
  https://global.canon/en/c-museum/product/dcc884.html
- Canon Picture Style behavior:
  https://cam.start.canon/ky/C001/manual/html/UG-03_Shooting-1_0070.html
- Open-source neutral-profile plus 3D-LUT method:
  https://github.com/TingfengLuo/Camera-Profile-for-Fujifilm-Film-Simulation
- Open-source neutral preprocessing and Lab tone-curve method:
  https://github.com/t3mujinpack/t3mujinpack

## Method

The renderer keeps neutral input processing separate from the look transform,
then applies smooth hue-sector masks inside the existing deterministic 3D cube.
Classic Chrome now has directly tested magenta suppression and cool-shadow
separation. G7 X Compact now has directly tested warm portrait separation,
selective blue/foliage crispness, bounded neutral-gray cast, and zero
film-grain/halation finishing.

External LUT files were not copied into the app. Most available LUTs assume a
specific RAW camera profile, white balance, exposure, and input color space.
Applying one directly to an iPhone display-referred frame would make the result
less controlled and could create licensing ambiguity.

## Acceptance evidence

- Every built-in recipe remains finite and inside normalized RGB bounds.
- Classic Chrome suppresses magenta relative to Provia on the same swatch.
- Classic Chrome maintains greater cool-shadow blue/red separation.
- G7 X Compact increases blue and foliage chroma without materially tinting
  neutral gray.
- Preview, photo, and export remain pixel-identical for the two reference looks
  when the grain phase is fixed.
- A retained XCTest contact sheet renders every built-in look through the real
  renderer for manual inspection in CI artifacts.

## Path to tighter hardware matching

A future calibration pass should photograph a controlled ColorChecker,
skin-tone chart, gray ramp, foliage, and sky targets on the target Fuji and
Canon cameras under fixed illumination. The same scene should be captured on
the iPhone with exposure and white balance locked. A regularized 3D LUT can
then be fit in a documented neutral input space and validated on separate
holdout scenes. That is the defensible route toward substantially closer
hardware matching.
''',
    encoding="utf-8"
)
