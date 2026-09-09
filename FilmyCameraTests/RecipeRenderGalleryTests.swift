import CoreImage
import UIKit
import XCTest
@testable import FilmyCamera

/// Renders local fixture photographs through the real Core Image pipeline and
/// attaches labelled side-by-side composites for visual review of recipe
/// tuning. Fixtures live in `FilmyCameraTests/Fixtures/fixture-*.jpg`, are
/// intentionally not committed, and the tests skip when none are bundled.
///
/// To use locally: drop JPEGs into that folder, run `xcodegen generate` so they
/// are bundled, run this suite, then regenerate the project without the folder
/// before committing (the CI reproducibility gate diffs the generated project).
final class RecipeRenderGalleryTests: XCTestCase {
    private static let panelWidth: CGFloat = 520
    private static let panelsPerRow = 4

    private var fixtureURLs: [URL] {
        let bundle = Bundle(for: Self.self)
        return (bundle.urls(forResourcesWithExtension: "jpg", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("fixture-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testG7XRenderGallery() throws {
        try renderGallery(
            recipeIDs: ["g7x-compact"],
            includeFlashVariant: true,
            name: "g7x"
        )
    }

    func testFujiRenderGallery() throws {
        try renderGallery(
            recipeIDs: [
                "provia-standard",
                "classic-chrome",
                "velvia-vivid",
                "astia-soft",
                "classic-negative",
                "nostalgic-negative",
                "reala-ace",
                "eterna-cinema",
                "pro-neg-high",
                "acros-monochrome",
                "nostalgic-summer"
            ],
            includeFlashVariant: false,
            name: "fuji"
        )
    }

    func testCreatorRenderGallery() throws {
        try renderGallery(
            recipeIDs: [
                "nostalgic-summer",
                "aurea-golden",
                "eternal-pastel",
                "crepuscolo-blue",
                "black-ice",
                "matter-monochrome",
                "honey-portrait",
                "pacifica-100",
                "desert-daydream",
                "quiet-provia",
                "velvet-haze",
                "pastel-400",
                "eterna-bleach-bypass",
                "pro-neg-standard",
                "sepia-archive"
            ],
            includeFlashVariant: false,
            name: "creator"
        )
    }

    private func renderGallery(
        recipeIDs: [String],
        includeFlashVariant: Bool,
        name: String
    ) throws {
        let urls = fixtureURLs
        try XCTSkipIf(urls.isEmpty, "No local render fixtures are bundled")

        let recipes = recipeIDs.compactMap { identifier in
            FilmRecipe.builtIns.first { $0.id == identifier }
        }
        XCTAssertEqual(recipes.count, recipeIDs.count, "Every requested recipe should exist")
        let expectedPanelCount = 1 + recipes.count + recipes.filter {
            includeFlashVariant && $0.filmBase == .compactDigital
        }.count

        for url in urls {
            let decoded = try XCTUnwrap(
                CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
                "Could not decode \(url.lastPathComponent)"
            )
            let extent = decoded.extent
            let source = decoded.transformed(by: CGAffineTransform(
                translationX: -extent.minX,
                y: -extent.minY
            ))
            let faces = FilmRenderer.portraitSubjectRegions(in: source)

            var panels: [(String, CGImage)] = []
            let sourceImage = try XCTUnwrap(
                FilmRenderer.outputCGImage(source, from: source.extent),
                "Could not materialize source \(url.lastPathComponent)"
            )
            panels.append(("source · \(faces.count) face(s)", sourceImage))

            for recipe in recipes {
                let context: FilmRenderer.CaptureContext = recipe.filmBase == .compactDigital
                    ? FilmRenderer.CaptureContext(flashFired: false, subjectRegions: faces)
                    : .standard
                let rendered = FilmRenderer.render(
                    source,
                    recipe: recipe,
                    quality: .photo,
                    captureContext: context
                )
                let image = try XCTUnwrap(
                    FilmRenderer.outputCGImage(rendered, from: source.extent),
                    "Could not materialize \(recipe.id) for \(url.lastPathComponent)"
                )
                panels.append((recipe.name, image))

                if includeFlashVariant, recipe.filmBase == .compactDigital {
                    let flashContext = FilmRenderer.CaptureContext(
                        flashFired: true,
                        subjectRegions: faces
                    )
                    let flashRendered = FilmRenderer.render(
                        source,
                        recipe: recipe,
                        quality: .photo,
                        captureContext: flashContext
                    )
                    let flashImage = try XCTUnwrap(
                        FilmRenderer.outputCGImage(flashRendered, from: source.extent),
                        "Could not materialize \(recipe.id) flash for \(url.lastPathComponent)"
                    )
                    panels.append(("\(recipe.name) · flash", flashImage))
                }
            }

            XCTAssertEqual(
                panels.count,
                expectedPanelCount,
                "\(url.lastPathComponent) must contain every requested render panel"
            )
            let composite = Self.composite(panels, faces: faces, sourceExtent: source.extent)
            let attachment = XCTAttachment(image: composite, quality: .medium)
            attachment.name = "\(name)-\(url.deletingPathExtension().lastPathComponent)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private static func composite(
        _ panels: [(String, CGImage)],
        faces: [CGRect],
        sourceExtent: CGRect
    ) -> UIImage {
        guard let first = panels.first?.1 else {
            return UIImage()
        }
        let scale = panelWidth / CGFloat(first.width)
        let panelHeight = (CGFloat(first.height) * scale).rounded()
        let labelHeight: CGFloat = 30
        let columns = min(panels.count, panelsPerRow)
        let rows = Int((Double(panels.count) / Double(panelsPerRow)).rounded(.up))
        let size = CGSize(
            width: CGFloat(columns) * panelWidth,
            height: CGFloat(rows) * (panelHeight + labelHeight)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: UIColor.white
            ]

            for (index, panel) in panels.enumerated() {
                let column = index % panelsPerRow
                let row = index / panelsPerRow
                let origin = CGPoint(
                    x: CGFloat(column) * panelWidth,
                    y: CGFloat(row) * (panelHeight + labelHeight)
                )
                let imageRect = CGRect(
                    x: origin.x,
                    y: origin.y + labelHeight,
                    width: panelWidth,
                    height: panelHeight
                )
                UIImage(cgImage: panel.1).draw(in: imageRect)
                (panel.0 as NSString).draw(
                    at: CGPoint(x: origin.x + 8, y: origin.y + 6),
                    withAttributes: labelAttributes
                )

                // Outline detected faces on the source panel so the subject
                // treatment can be judged against what the detector saw.
                if index == 0 {
                    context.setStrokeColor(UIColor.systemYellow.cgColor)
                    context.setLineWidth(2)
                    for face in faces {
                        let rect = CGRect(
                            x: imageRect.minX + face.minX * scale,
                            y: imageRect.minY + (sourceExtent.height - face.maxY) * scale,
                            width: face.width * scale,
                            height: face.height * scale
                        )
                        context.stroke(rect)
                    }
                }
            }
        }
    }
}


import ImageIO

/// Always-on catalog acceptance. Uses bundled/synthetic fixtures, never skips
/// for absent private photographs and never writes to the user's Photos.
final class CatalogRenderAcceptanceTests: XCTestCase {
    func testRender_provia_standard() throws { try verifyRecipe("provia-standard") }
    func testRender_classic_chrome() throws { try verifyRecipe("classic-chrome") }
    func testRender_velvia_vivid() throws { try verifyRecipe("velvia-vivid") }
    func testRender_astia_soft() throws { try verifyRecipe("astia-soft") }
    func testRender_pro_neg_high() throws { try verifyRecipe("pro-neg-high") }
    func testRender_eterna_cinema() throws { try verifyRecipe("eterna-cinema") }
    func testRender_acros_monochrome() throws { try verifyRecipe("acros-monochrome") }
    func testRender_sepia_archive() throws { try verifyRecipe("sepia-archive") }
    func testRender_acros_neutral_filter() throws { try verifyRecipe("acros-neutral-filter") }
    func testRender_acros_yellow_filter() throws { try verifyRecipe("acros-yellow-filter") }
    func testRender_acros_red_filter() throws { try verifyRecipe("acros-red-filter") }
    func testRender_acros_green_filter() throws { try verifyRecipe("acros-green-filter") }
    func testRender_classic_negative() throws { try verifyRecipe("classic-negative") }
    func testRender_nostalgic_negative() throws { try verifyRecipe("nostalgic-negative") }
    func testRender_eterna_bleach_bypass() throws { try verifyRecipe("eterna-bleach-bypass") }
    func testRender_pro_neg_standard() throws { try verifyRecipe("pro-neg-standard") }
    func testRender_reala_ace() throws { try verifyRecipe("reala-ace") }
    func testRender_g7x_compact() throws { try verifyRecipe("g7x-compact") }
    func testRender_nostalgic_summer() throws { try verifyRecipe("nostalgic-summer") }
    func testRender_aurea_golden() throws { try verifyRecipe("aurea-golden") }
    func testRender_eternal_pastel() throws { try verifyRecipe("eternal-pastel") }
    func testRender_crepuscolo_blue() throws { try verifyRecipe("crepuscolo-blue") }
    func testRender_black_ice() throws { try verifyRecipe("black-ice") }
    func testRender_matter_monochrome() throws { try verifyRecipe("matter-monochrome") }
    func testRender_honey_portrait() throws { try verifyRecipe("honey-portrait") }
    func testRender_pacifica_100() throws { try verifyRecipe("pacifica-100") }
    func testRender_desert_daydream() throws { try verifyRecipe("desert-daydream") }
    func testRender_quiet_provia() throws { try verifyRecipe("quiet-provia") }
    func testRender_velvet_haze() throws { try verifyRecipe("velvet-haze") }
    func testRender_pastel_400() throws { try verifyRecipe("pastel-400") }
    func testRender_archive_64() throws { try verifyRecipe("archive-64") }
    func testRender_tungsten_800() throws { try verifyRecipe("tungsten-800") }
    func testRender_pushed_tungsten() throws { try verifyRecipe("pushed-tungsten") }
    func testRender_pacific_blues() throws { try verifyRecipe("pacific-blues") }
    func testRender_green_800() throws { try verifyRecipe("green-800") }
    func testRender_hp5_texture() throws { try verifyRecipe("hp5-texture") }
    func testRender_negative_portrait_160() throws { try verifyRecipe("negative-portrait-160") }
    func testRender_negative_portrait_400() throws { try verifyRecipe("negative-portrait-400") }
    func testRender_negative_portrait_800() throws { try verifyRecipe("negative-portrait-800") }
    func testRender_negative_gold_200() throws { try verifyRecipe("negative-gold-200") }
    func testRender_negative_consumer_400() throws { try verifyRecipe("negative-consumer-400") }
    func testRender_negative_coastal_100() throws { try verifyRecipe("negative-coastal-100") }
    func testRender_negative_city_200() throws { try verifyRecipe("negative-city-200") }
    func testRender_negative_soft_cream() throws { try verifyRecipe("negative-soft-cream") }
    func testRender_negative_olive_400() throws { try verifyRecipe("negative-olive-400") }
    func testRender_negative_rose_200() throws { try verifyRecipe("negative-rose-200") }
    func testRender_negative_pastel_day() throws { try verifyRecipe("negative-pastel-day") }
    func testRender_negative_woodland() throws { try verifyRecipe("negative-woodland") }
    func testRender_negative_copper_800() throws { try verifyRecipe("negative-copper-800") }
    func testRender_negative_winter_200() throws { try verifyRecipe("negative-winter-200") }
    func testRender_negative_travel_400() throws { try verifyRecipe("negative-travel-400") }
    func testRender_negative_faded_album() throws { try verifyRecipe("negative-faded-album") }
    func testRender_slide_chrome_50() throws { try verifyRecipe("slide-chrome-50") }
    func testRender_slide_chrome_100() throws { try verifyRecipe("slide-chrome-100") }
    func testRender_slide_mountain_50() throws { try verifyRecipe("slide-mountain-50") }
    func testRender_slide_warm_projector() throws { try verifyRecipe("slide-warm-projector") }
    func testRender_slide_cool_chrome() throws { try verifyRecipe("slide-cool-chrome") }
    func testRender_slide_sunset_chrome() throws { try verifyRecipe("slide-sunset-chrome") }
    func testRender_slide_botanical() throws { try verifyRecipe("slide-botanical") }
    func testRender_slide_soft_transparency() throws { try verifyRecipe("slide-soft-transparency") }
    func testRender_slide_blue_hour() throws { try verifyRecipe("slide-blue-hour") }
    func testRender_slide_archive_projector() throws { try verifyRecipe("slide-archive-projector") }
    func testRender_cinema_daylight_250() throws { try verifyRecipe("cinema-daylight-250") }
    func testRender_cinema_tungsten_500() throws { try verifyRecipe("cinema-tungsten-500") }
    func testRender_cinema_night_neon() throws { try verifyRecipe("cinema-night-neon") }
    func testRender_cinema_silver_screen() throws { try verifyRecipe("cinema-silver-screen") }
    func testRender_cinema_amber_teal() throws { try verifyRecipe("cinema-amber-teal") }
    func testRender_cinema_matinee() throws { try verifyRecipe("cinema-matinee") }
    func testRender_cinema_noir_color() throws { try verifyRecipe("cinema-noir-color") }
    func testRender_cinema_road_movie() throws { try verifyRecipe("cinema-road-movie") }
    func testRender_cinema_rainy_city() throws { try verifyRecipe("cinema-rainy-city") }
    func testRender_cinema_summer_feature() throws { try verifyRecipe("cinema-summer-feature") }
    func testRender_cinema_velvet_night() throws { try verifyRecipe("cinema-velvet-night") }
    func testRender_cinema_newsreel_color() throws { try verifyRecipe("cinema-newsreel-color") }
    func testRender_instant_cream_square() throws { try verifyRecipe("instant-cream-square") }
    func testRender_instant_pastel_square() throws { try verifyRecipe("instant-pastel-square") }
    func testRender_instant_sun_faded() throws { try verifyRecipe("instant-sun-faded") }
    func testRender_instant_cool_pack() throws { try verifyRecipe("instant-cool-pack") }
    func testRender_instant_party_pack() throws { try verifyRecipe("instant-party-pack") }
    func testRender_instant_warm_pack() throws { try verifyRecipe("instant-warm-pack") }
    func testRender_instant_soft_focus() throws { try verifyRecipe("instant-soft-focus") }
    func testRender_instant_expired_pack() throws { try verifyRecipe("instant-expired-pack") }
    func testRender_digital_ccd_daylight() throws { try verifyRecipe("digital-ccd-daylight") }
    func testRender_digital_ccd_twilight() throws { try verifyRecipe("digital-ccd-twilight") }
    func testRender_digital_pocket_positive() throws { try verifyRecipe("digital-pocket-positive") }
    func testRender_digital_pocket_negative() throws { try verifyRecipe("digital-pocket-negative") }
    func testRender_digital_rangefinder_color() throws { try verifyRecipe("digital-rangefinder-color") }
    func testRender_digital_rangefinder_soft() throws { try verifyRecipe("digital-rangefinder-soft") }
    func testRender_digital_mirrorless_clean() throws { try verifyRecipe("digital-mirrorless-clean") }
    func testRender_digital_mirrorless_vivid() throws { try verifyRecipe("digital-mirrorless-vivid") }
    func testRender_digital_mirrorless_portrait() throws { try verifyRecipe("digital-mirrorless-portrait") }
    func testRender_digital_bridge_zoom() throws { try verifyRecipe("digital-bridge-zoom") }
    func testRender_digital_pocket_flash() throws { try verifyRecipe("digital-pocket-flash") }
    func testRender_digital_pocket_soft() throws { try verifyRecipe("digital-pocket-soft") }
    func testRender_digital_cmos_studio() throws { try verifyRecipe("digital-cmos-studio") }
    func testRender_digital_cmos_night() throws { try verifyRecipe("digital-cmos-night") }
    func testRender_digital_toy_digital() throws { try verifyRecipe("digital-toy-digital") }
    func testRender_digital_compact_sunset() throws { try verifyRecipe("digital-compact-sunset") }
    func testRender_experimental_cross_process() throws { try verifyRecipe("experimental-cross-process") }
    func testRender_experimental_red_dusk() throws { try verifyRecipe("experimental-red-dusk") }
    func testRender_experimental_mint_dream() throws { try verifyRecipe("experimental-mint-dream") }
    func testRender_experimental_violet_hour() throws { try verifyRecipe("experimental-violet-hour") }
    func testRender_experimental_solar_gold() throws { try verifyRecipe("experimental-solar-gold") }
    func testRender_experimental_washed_cyan() throws { try verifyRecipe("experimental-washed-cyan") }
    func testRender_monochrome_silver_100() throws { try verifyRecipe("monochrome-silver-100") }
    func testRender_monochrome_silver_400() throws { try verifyRecipe("monochrome-silver-400") }
    func testRender_monochrome_silver_1600() throws { try verifyRecipe("monochrome-silver-1600") }
    func testRender_monochrome_fine_25() throws { try verifyRecipe("monochrome-fine-25") }
    func testRender_monochrome_street_hard() throws { try verifyRecipe("monochrome-street-hard") }
    func testRender_monochrome_street_soft() throws { try verifyRecipe("monochrome-street-soft") }
    func testRender_monochrome_portrait_green() throws { try verifyRecipe("monochrome-portrait-green") }
    func testRender_monochrome_landscape_red() throws { try verifyRecipe("monochrome-landscape-red") }
    func testRender_monochrome_classic_yellow() throws { try verifyRecipe("monochrome-classic-yellow") }
    func testRender_monochrome_matte_paper() throws { try verifyRecipe("monochrome-matte-paper") }
    func testRender_monochrome_gloss_paper() throws { try verifyRecipe("monochrome-gloss-paper") }
    func testRender_monochrome_noir_rain() throws { try verifyRecipe("monochrome-noir-rain") }
    func testRender_monochrome_high_key() throws { try verifyRecipe("monochrome-high-key") }
    func testRender_monochrome_low_key() throws { try verifyRecipe("monochrome-low-key") }
    func testRender_monochrome_warm_fiber() throws { try verifyRecipe("monochrome-warm-fiber") }
    func testRender_monochrome_cool_silver() throws { try verifyRecipe("monochrome-cool-silver") }
    func testRender_monochrome_selenium() throws { try verifyRecipe("monochrome-selenium") }
    func testRender_monochrome_copper_print() throws { try verifyRecipe("monochrome-copper-print") }
    func testRender_monochrome_blue_print() throws { try verifyRecipe("monochrome-blue-print") }
    func testRender_monochrome_press_3200() throws { try verifyRecipe("monochrome-press-3200") }
    func testRender_monochrome_night_silver() throws { try verifyRecipe("monochrome-night-silver") }
    func testRender_monochrome_architecture() throws { try verifyRecipe("monochrome-architecture") }
    func testRender_monochrome_soft_charcoal() throws { try verifyRecipe("monochrome-soft-charcoal") }
    func testRender_monochrome_silver_rangefinder() throws { try verifyRecipe("monochrome-silver-rangefinder") }

    private func verifyRecipe(_ id: String) throws {
        try autoreleasepool { () throws -> Void in
            try renderAndVerifyRecipe(id)
        }
    }

    private func renderAndVerifyRecipe(_ id: String) throws {
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == id })
        XCTAssertTrue(recipe.isValid, id)
        let data = try JSONEncoder().encode(recipe)
        XCTAssertEqual(try JSONDecoder().decode(FilmRecipe.self, from: data), recipe)
        let sample = try XCTUnwrap(UIImage(named: "LookPreviewCafe")?.cgImage, "Bundled public-safe sample required")
        let bounds = CGRect(x: 0, y: 0, width: 96, height: 128)
        let cafe = CameraFrameLayout.aspectFill(CIImage(cgImage: sample), in: bounds)
        let dark = cafe.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -2.5])
        let fixtures: [(String, CIImage)] = [("color-chart", Self.chart(in: bounds)), ("daylight", cafe), ("low-light", dark)]
        let qualities: [FilmRenderer.Quality] = [FilmRenderer.Quality.preview, .photo]
        var previews: [CGImage] = []
        for (name, input) in fixtures {
            for quality in qualities {
                let output = FilmRenderer.render(input, recipe: recipe, quality: quality, grainSeed: 42)
                XCTAssertEqual(output.extent, input.extent, "\(id) \(name)")
                let bitmap = try verifyPixels(output, recipe: recipe, fixture: name, bounds: bounds)
                if quality == .photo {
                    try verifyJPEG(bitmap, recipe: recipe)
                    previews.append(bitmap)
                }
            }
        }
        attachContactSheet(previews, recipe: recipe)
    }

    private func verifyPixels(_ output: CIImage, recipe: FilmRecipe, fixture: String, bounds: CGRect) throws -> CGImage {
        let width = Int(bounds.width), height = Int(bounds.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        FilmRenderer.sharedContext.render(output, toBitmap: &pixels,
                                          rowBytes: width * 4 * MemoryLayout<Float>.size,
                                          bounds: bounds, format: .RGBAf, colorSpace: colorSpace)
        XCTAssertTrue(pixels.allSatisfy { $0.isFinite }, "Nonfinite pixels: \(recipe.id) \(fixture)")
        var minimum: Float = .greatestFiniteMagnitude
        var maximum: Float = -.greatestFiniteMagnitude
        var chroma: Float = 0
        var alphaError: Float = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
            minimum = min(minimum, r)
            maximum = max(maximum, r)
            let redGreen: Float = abs(r - g)
            let greenBlue: Float = abs(g - b)
            chroma = max(chroma, max(redGreen, greenBlue))
            alphaError = max(alphaError, abs(pixels[offset + 3] - 1))
        }
        XCTAssertLessThan(alphaError, 0.002, "Opaque source alpha changed: \(recipe.id)")
        if fixture == "color-chart" {
            XCTAssertGreaterThan(maximum - minimum, 0.05, "Collapsed tonal range: \(recipe.id)")
        }
        let neutralMonochrome = recipe.creativeCollection == .monochrome
            && recipe.filmBase.monochromeFilter != nil
            && recipe.monochromaticColor.warmCool == 0
            && recipe.monochromaticColor.greenMagenta == 0
        if neutralMonochrome {
            XCTAssertLessThan(chroma, 0.01, "Neutral monochrome contains unintended color: \(recipe.id)")
        }
        let bitmap = try XCTUnwrap(FilmRenderer.outputCGImage(output, from: bounds), recipe.id)
        XCTAssertEqual(bitmap.width, width)
        XCTAssertEqual(bitmap.height, height)
        return bitmap
    }

    private func verifyJPEG(_ bitmap: CGImage, recipe: FilmRecipe) throws {
        let encoded = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: bitmap, sourceData: Data(), capturedAt: Date(timeIntervalSince1970: 0), recipe: recipe))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 96)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 128)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let comment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        let metadata = try JSONDecoder().decode(PhotoOutputEncoder.RecipeProvenanceMetadata.self, from: Data(comment.utf8))
        XCTAssertEqual(metadata.recipeID, recipe.id)
        XCTAssertEqual(metadata.provenance, recipe.provenance)
    }

    private func attachContactSheet(_ previews: [CGImage], recipe: FilmRecipe) {
        XCTAssertEqual(previews.count, 3, recipe.id)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.white
        ]
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 288, height: 156), format: format)
        let sheet = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 288, height: 156))
            for (index, bitmap) in previews.enumerated() {
                let rect = CGRect(x: CGFloat(index) * 96, y: 28, width: 96, height: 128)
                UIImage(cgImage: bitmap).draw(in: rect)
            }
            (recipe.name as NSString).draw(at: CGPoint(x: 5, y: 5), withAttributes: attributes)
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "catalog-\(recipe.id)-chart-daylight-lowlight"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func chart(in bounds: CGRect) -> CIImage {
        let width = Int(bounds.width), height = Int(bounds.height)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if y < height / 2 {
                    let value = UInt8(x * 255 / (width - 1))
                    bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
                } else {
                    bytes[offset] = UInt8(x * 255 / (width - 1))
                    bytes[offset + 1] = UInt8((y - height / 2) * 255 / (height / 2 - 1))
                    bytes[offset + 2] = UInt8(255 - x * 255 / (width - 1))
                }
            }
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4,
                       size: bounds.size, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
