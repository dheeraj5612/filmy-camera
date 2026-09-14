import CoreGraphics
import CoreImage
import XCTest
@testable import FilmyCamera

final class SignatureCharacterTests: XCTestCase {
    func testVelviaSignatureStageUsesHalfwayToneCurveAndSaturation() throws {
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "velvia-vivid" })
        let input = Self.signatureFixture()
        let stages = FilmRenderer.diagnosticRenderStages(
            input,
            recipe: recipe,
            quality: .photo,
            grainSeed: 73
        )

        let preSignature = try XCTUnwrap(stages[.preSignature])
        let postSignature = try XCTUnwrap(stages[.postSignature])
        let expected = try XCTUnwrap(Self.halfwayVelviaSignature(from: preSignature))
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let actualPixels = try Self.pixels(postSignature, context: context)
        let expectedPixels = try Self.pixels(expected, context: context)

        XCTAssertLessThan(
            Self.meanAbsoluteRGBDifference(actualPixels, expectedPixels),
            0.000_01,
            "postSignature must be the 50% Velvia curve and 1.04 saturation applied to preSignature"
        )
    }

    func testSignatureStageChangesEveryEligibleFilmAndCreativeCollectionRepresentative() throws {
        let input = Self.signatureFixture()
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let representatives = try Self.signatureRepresentatives()

        for recipe in representatives {
            let stages = FilmRenderer.diagnosticRenderStages(
                input,
                recipe: recipe,
                quality: .photo,
                grainSeed: 73
            )
            let before = try XCTUnwrap(stages[.preSignature], recipe.id)
            let after = try XCTUnwrap(stages[.postSignature], recipe.id)
            let beforePixels = try Self.pixels(before, context: context)
            let afterPixels = try Self.pixels(after, context: context)
            let difference = Self.meanAbsoluteRGBDifference(beforePixels, afterPixels)

            XCTAssertGreaterThan(
                difference,
                0.000_01,
                "Signature stage has no rendered effect for \(recipe.id)"
            )
            XCTAssertTrue(afterPixels.allSatisfy(\.isFinite), "Non-finite Signature output for \(recipe.id)")
        }
    }

    func testNeutralStandardAndG7XBypassSharedSignatureAndFinalMatchesNormalRender() throws {
        let input = Self.signatureFixture()
        let context = CIContext(options: FilmRenderer.testContextOptions)
        let neutral = FilmRecipe(
            id: "standard-neutral-control",
            name: "Standard Neutral Control",
            subtitle: "Test control",
            filmBase: .standard
        )
        let g7x = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })

        for recipe in [neutral, g7x] {
            let stages = FilmRenderer.diagnosticRenderStages(
                input,
                recipe: recipe,
                quality: .photo,
                captureContext: recipe.filmBase == .compactDigital
                    ? .init(flashFired: false)
                    : .standard,
                grainSeed: 73
            )
            let before = try XCTUnwrap(stages[.preSignature], recipe.id)
            let after = try XCTUnwrap(stages[.postSignature], recipe.id)
            let beforePixels = try Self.pixels(before, context: context)
            let afterPixels = try Self.pixels(after, context: context)
            XCTAssertLessThan(
                Self.meanAbsoluteRGBDifference(beforePixels, afterPixels),
                0.000_001,
                "\(recipe.id) must bypass the shared Signature stage"
            )

            let normal = FilmRenderer.render(
                input,
                recipe: recipe,
                quality: .photo,
                captureContext: recipe.filmBase == .compactDigital
                    ? .init(flashFired: false)
                    : .standard,
                grainSeed: 73
            )
            let final = try XCTUnwrap(stages[.final], recipe.id)
            XCTAssertLessThan(
                Self.meanAbsoluteRGBDifference(
                    try Self.pixels(normal, context: context),
                    try Self.pixels(final, context: context)
                ),
                0.000_01,
                "Normal render and diagnostic final diverged for \(recipe.id)"
            )
        }
    }

    private static func signatureRepresentatives() throws -> [FilmRecipe] {
        var result: [FilmRecipe] = []
        for base in FilmRecipe.FilmBase.allCases where base != .standard && base != .compactDigital {
            let recipe = try XCTUnwrap(
                FilmRecipe.builtIns.first(where: { $0.filmBase == base }),
                "No built-in representative for \(base.rawValue)"
            )
            result.append(recipe)
        }

        for collection in FilmRecipe.Collection.allCases {
            let recipe = try XCTUnwrap(
                FilmRecipe.builtIns.first(where: {
                    $0.creativeCollection == collection && $0.filmBase != .compactDigital
                }),
                "No creative collection representative for \(collection.rawValue)"
            )
            result.append(recipe)
        }
        return result
    }

    private static func halfwayVelviaSignature(from image: CIImage) -> CIImage? {
        guard let curve = CIFilter(name: "CIToneCurve") else { return nil }
        let controlPoints: [CGFloat] = [0, 0.20, 0.50, 0.80, 1]
        let signatureLevels: [CGFloat] = [0, 0.115, 0.49, 0.87, 1]
        curve.setValue(image, forKey: kCIInputImageKey)
        for (index, x) in controlPoints.enumerated() {
            let halfway = x + (signatureLevels[index] - x) * 0.50
            curve.setValue(CIVector(x: x, y: halfway), forKey: "inputPoint\(index)")
        }
        guard let curved = curve.outputImage?.cropped(to: image.extent) else { return nil }
        return curved.applyingFilter(
            "CIColorControls",
            parameters: [kCIInputSaturationKey: 1.04]
        )
    }

    private static func signatureFixture() -> CIImage {
        let width = 80
        let height = 24
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let levels: [(Double, Double, Double)] = [
            (0.04, 0.03, 0.02),
            (0.20, 0.14, 0.10),
            (0.50, 0.35, 0.22),
            (0.78, 0.60, 0.42),
            (0.98, 0.84, 0.66)
        ]
        for y in 0..<height {
            for x in 0..<width {
                let level = levels[min(levels.count - 1, x * levels.count / width)]
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8((level.0 * 255).rounded())
                bytes[offset + 1] = UInt8((level.1 * 255).rounded())
                bytes[offset + 2] = UInt8((level.2 * 255).rounded())
                bytes[offset + 3] = 255
            }
        }
        let data = Data(bytes)
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private static func pixels(_ image: CIImage, context: CIContext) throws -> [Float] {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var values = [Float](repeating: 0, count: width * height * 4)
        try values.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw NSError(domain: "SignatureCharacterTests", code: 1)
            }
            context.render(
                image,
                toBitmap: baseAddress,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: image.extent,
                format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        }
        return values
    }

    private static func meanAbsoluteRGBDifference(_ lhs: [Float], _ rhs: [Float]) -> Double {
        precondition(lhs.count == rhs.count && lhs.count.isMultiple(of: 4))
        var total = 0.0
        for offset in stride(from: 0, to: lhs.count, by: 4) {
            for channel in 0..<3 {
                total += Double(abs(lhs[offset + channel] - rhs[offset + channel]))
            }
        }
        return total / Double(lhs.count / 4 * 3)
    }
}
