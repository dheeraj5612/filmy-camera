import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class PhotoOutputEncoderTests: XCTestCase {
    func testFilteredJPEGKeepsCaptureProvenanceAndStripsGPS() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 4,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.76, green: 0.36, blue: 0.18, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let image = try XCTUnwrap(context.makeImage())

        let sourceData = NSMutableData()
        let sourceDestination = try XCTUnwrap(CGImageDestinationCreateWithData(
            sourceData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let sourceProperties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 41.88,
                kCGImagePropertyGPSLongitude as String: -87.63
            ],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFArtist as String: "Filmy Camera test"
            ]
        ]
        CGImageDestinationAddImage(sourceDestination, image, sourceProperties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sourceDestination))

        let capturedAt = Date(timeIntervalSince1970: 1_786_557_600)
        let output = try XCTUnwrap(PhotoOutputEncoder.jpegData(
            for: image,
            sourceData: sourceData as Data,
            capturedAt: capturedAt
        ))
        let outputSource = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [String: Any]
        )
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])

        XCTAssertEqual(tiff[kCGImagePropertyTIFFSoftware as String] as? String, "Filmy Camera")
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2026:08:12 18:00:00")
        XCTAssertEqual((properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue, 1)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertEqual(CGImageSourceGetType(outputSource) as String?, UTType.jpeg.identifier)
    }
}
