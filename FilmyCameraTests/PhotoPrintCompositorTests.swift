import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import FilmyCamera

final class PhotoPrintCompositorTests: XCTestCase {
    func testInstantPrintNormalizesTranslatedExtentAndAddsLargerBottomMargin() throws {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 17, y: -9, width: 80, height: 60))
        let layout = try XCTUnwrap(
            PhotoPrintCompositor.layout(for: source.extent, finish: .instantPrint)
        )
        let output = try XCTUnwrap(
            PhotoPrintCompositor.composedImage(source, finish: .instantPrint)
        )

        XCTAssertEqual(layout.sourcePixelExtent, CGRect(x: 17, y: -9, width: 80, height: 60))
        XCTAssertEqual(layout.sideMargin, 3)
        XCTAssertEqual(layout.topMargin, 3)
        XCTAssertEqual(layout.bottomMargin, 8)
        XCTAssertEqual(layout.imageFrame, CGRect(x: 3, y: 8, width: 80, height: 60))
        XCTAssertEqual(layout.canvasExtent, CGRect(x: 0, y: 0, width: 86, height: 71))
        XCTAssertEqual(output.extent, layout.canvasExtent)
        XCTAssertGreaterThan(layout.bottomMargin, layout.topMargin)
    }

    func testInstantPrintPreservesEverySourcePixelAndProducesOpaquePaper() throws {
        let sourceImage = try detailedImage(width: 24, height: 18)
        let translatedSource = CIImage(cgImage: sourceImage).transformed(
            by: CGAffineTransform(translationX: -11, y: 23)
        )
        let layout = try XCTUnwrap(
            PhotoPrintCompositor.layout(for: translatedSource.extent, finish: .instantPrint)
        )
        let output = try XCTUnwrap(
            PhotoPrintCompositor.composedImage(translatedSource, finish: .instantPrint)
        )
        let extractedPhoto = output
            .cropped(to: layout.imageFrame)
            .transformed(by: CGAffineTransform(
                translationX: -layout.imageFrame.minX,
                y: -layout.imageFrame.minY
            ))

        XCTAssertEqual(layout.imageFrame.size, translatedSource.extent.size)
        XCTAssertEqual(
            try rgbaPixels(extractedPhoto, extent: CGRect(origin: .zero, size: layout.imageFrame.size)),
            try rgbaPixels(CIImage(cgImage: sourceImage), extent: CIImage(cgImage: sourceImage).extent),
            "The compositor must not crop, rescale, blur, or otherwise change photo pixels"
        )

        let borderedPixels = try rgbaPixels(output, extent: output.extent)
        XCTAssertGreaterThan(borderedPixels[2], 230)
        XCTAssertGreaterThanOrEqual(borderedPixels[1], borderedPixels[2])
        XCTAssertGreaterThanOrEqual(borderedPixels[0], borderedPixels[1])
        XCTAssertEqual(borderedPixels[3], 255, "The warm-white paper must be opaque")

        let transparentSource = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.25))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let transparentOutput = try XCTUnwrap(
            PhotoPrintCompositor.composedImage(transparentSource, finish: .instantPrint)
        )
        let outputPixels = try rgbaPixels(transparentOutput, extent: transparentOutput.extent)
        XCTAssertTrue(
            stride(from: 3, to: outputPixels.count, by: 4).allSatisfy { outputPixels[$0] == 255 },
            "Opaque print paper must safely resolve source alpha"
        )
    }

    func testPhotoFinishIsAnIdentityOperation() throws {
        let source = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: -7, y: 12, width: 31, height: 19))
        let output = try XCTUnwrap(PhotoPrintCompositor.composedImage(source, finish: .photo))

        XCTAssertTrue(output === source)
        XCTAssertEqual(output.extent, source.extent)

        let oversizedPhoto = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 10_000, height: 10_000))
        XCTAssertTrue(
            PhotoPrintCompositor.composedImage(oversizedPhoto, finish: .photo) === oversizedPhoto,
            "The default finish must never introduce a new resolution limit"
        )

        let encoded = try JSONEncoder().encode(PhotoFinish.instantPrint)
        XCTAssertEqual(try JSONDecoder().decode(PhotoFinish.self, from: encoded), .instantPrint)
        XCTAssertEqual(PhotoFinish.allCases, [.photo, .instantPrint])
    }

    func testPixelBudgetsAcceptNativeHighResolutionAndRejectUnboundedCanvases() {
        let native48MP = CGRect(x: 0, y: 0, width: 8_000, height: 6_000)
        let layout = PhotoPrintCompositor.layout(for: native48MP, finish: .instantPrint)

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.imageFrame.size, native48MP.size)
        XCTAssertLessThanOrEqual(
            (layout?.canvasExtent.width ?? .infinity) * (layout?.canvasExtent.height ?? .infinity),
            PhotoPrintCompositor.maximumOutputPixelCount
        )

        XCTAssertNil(PhotoPrintCompositor.layout(
            for: CGRect(x: 0, y: 0, width: 8_001, height: 8_000),
            finish: .instantPrint
        ))
        XCTAssertNil(PhotoPrintCompositor.layout(
            for: CGRect(x: 0, y: 0, width: 64_000_000, height: 1),
            finish: .instantPrint
        ))
        XCTAssertNil(PhotoPrintCompositor.composedImage(
            CIImage(color: CIColor(red: 1, green: 1, blue: 1)),
            finish: .instantPrint
        ))
        XCTAssertNil(PhotoPrintCompositor.layout(for: .zero, finish: .instantPrint))
    }

    private func detailedImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                pixels[offset] = UInt8((x * 37 + y * 11) % 256)
                pixels[offset + 1] = UInt8((x * 13 + y * 43) % 256)
                pixels[offset + 2] = UInt8((x * 29 + y * 17) % 256)
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func rgbaPixels(_ image: CIImage, extent: CGRect) throws -> [UInt8] {
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace
        ])
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return pixels
    }
}
