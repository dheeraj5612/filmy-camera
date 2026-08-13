import CoreGraphics
import CoreImage
import XCTest
@testable import FilmyCamera

final class ColorSpaceBoundaryTests: XCTestCase {
    func testRendererMaterializesWideGamutInputAsDisplayReferredSRGB() throws {
        let inputColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: inputColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.92, green: 0.18, blue: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let input = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(try XCTUnwrap(input.colorSpace).model, .rgb)

        let rendered = FilmRenderer.render(
            CIImage(cgImage: input),
            recipe: FilmRecipe.builtIns[0],
            quality: .photo
        )
        let output = try XCTUnwrap(FilmRenderer.outputCGImage(rendered))
        let outputColorSpace = try XCTUnwrap(output.colorSpace)
        let expectedColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))

        XCTAssertEqual(outputColorSpace.model, .rgb)
        XCTAssertEqual(outputColorSpace.name, expectedColorSpace.name)
        XCTAssertEqual(output.width, 2)
        XCTAssertEqual(output.height, 2)
    }
}
