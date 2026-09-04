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
