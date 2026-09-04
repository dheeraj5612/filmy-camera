import CoreGraphics
import CoreImage
import XCTest
@testable import FilmyCamera

final class ColorSpaceBoundaryTests: XCTestCase {
    func testRendererMaterializesWideGamutInputAsDisplayReferredSRGB() throws {
        let inputColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let sRGBColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let sourceComponents: [CGFloat] = [0.72, 0.38, 0.24, 1]
        let sourceColor = try XCTUnwrap(
            CGColor(colorSpace: inputColorSpace, components: sourceComponents)
        )
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: inputColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(sourceColor)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let input = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(try XCTUnwrap(input.colorSpace).model, .rgb)

        let neutralRecipe = FilmRecipe(
            id: "color-space-neutral",
            name: "Color space neutral",
            subtitle: "Test"
        )
        let rendered = FilmRenderer.render(
            CIImage(cgImage: input),
            recipe: neutralRecipe,
            quality: .photo
        )
        let output = try XCTUnwrap(FilmRenderer.outputCGImage(rendered))
        let materializedColorSpace = try XCTUnwrap(output.colorSpace)
        let expectedColor = try XCTUnwrap(
            sourceColor.converted(
                to: sRGBColorSpace,
                intent: .relativeColorimetric,
                options: nil
            )
        )
        let expectedComponents = try XCTUnwrap(expectedColor.components)

        var outputPixel = [Float](repeating: 0, count: 4)
        outputPixel.withUnsafeMutableBytes { bytes in
            CIContext(options: FilmRenderer.testContextOptions).render(
                CIImage(cgImage: output),
                toBitmap: bytes.baseAddress!,
                rowBytes: 4 * MemoryLayout<Float>.stride,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf,
                colorSpace: sRGBColorSpace
            )
        }

        XCTAssertEqual(materializedColorSpace.model, .rgb)
        XCTAssertEqual(materializedColorSpace.name, sRGBColorSpace.name)
        XCTAssertEqual(output.width, 2)
        XCTAssertEqual(output.height, 2)
        XCTAssertGreaterThan(
            abs(expectedComponents[0] - sourceComponents[0]),
            0.03,
            "The fixture must distinguish color conversion from relabeling P3 values as sRGB"
        )
        for channel in 0..<3 {
            XCTAssertEqual(
                CGFloat(outputPixel[channel]),
                expectedComponents[channel],
                accuracy: 0.015,
                "P3 to sRGB conversion drifted in channel \(channel)"
            )
        }
    }
}
