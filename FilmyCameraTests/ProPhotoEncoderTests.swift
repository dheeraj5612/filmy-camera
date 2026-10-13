import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class ProPhotoEncoderTests: XCTestCase {
    func testHEIFActuallyContainsP3ProfileAndDoesNotForgeHDRFromSDR() throws {
        var options = ProCaptureOptions(); options.codec = .heif; options.hdr = true
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0, colorSpace: p3)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 96))
        let data = try XCTUnwrap(ProPhotoEncoder.heifData(image: source, sourceSDR: source, sourceHDR: nil, sourceData: Data(),
            recipe: FilmRecipe.builtIns[0], capturedAt: Date(), options: options))
        let file = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(file))
        XCTAssertTrue(UTType(type as String)!.conforms(to: .heif) || UTType(type as String)!.conforms(to: .heic))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [String: Any])
        XCTAssertTrue((properties[kCGImagePropertyProfileName as String] as? String ?? "").contains("P3"))
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
        XCTAssertFalse(ProPhotoEncoder.containsHDRGainMap(data))
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertNotEqual(exif[kCGImagePropertyExifColorSpace as String] as? Int, 1)
        XCTAssertNotNil(exif[kCGImagePropertyExifUserComment as String])
    }
    func testHDRSourceProducesANewGainMap() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("HDR encoding requires iOS 18") }
        let rect = CGRect(x: 0, y: 0, width: 128, height: 96)
        let sdr = CIImage(color: CIColor(red: 0.75, green: 0.5, blue: 0.25)).cropped(to: rect)
        let expanded = sdr.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 2.0])
        let cg = try XCTUnwrap(ProPhotoEncoder.context.createCGImage(expanded, from: rect, format: .RGBAh,
            colorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!))
        let hdr = CIImage(cgImage: cg, options: [.contentHeadroom: 4.0])
        XCTAssertGreaterThan(hdr.contentHeadroom, 1)
        var options = ProCaptureOptions(); options.codec = .heif; options.hdr = true
        let data = try XCTUnwrap(ProPhotoEncoder.heifData(image: sdr, sourceSDR: sdr, sourceHDR: hdr, sourceData: Data(),
            recipe: FilmRecipe.builtIns[0], capturedAt: Date(), options: options))
        XCTAssertTrue(ProPhotoEncoder.containsHDRGainMap(data))
    }

    func testResolutionDownsampleDoesNotChangeSmallImages() {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 96))
        XCTAssertEqual(ProPhotoEncoder.sized(image, resolution: .mp48).extent, image.extent)
        let large = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 8064, height: 6048))
        XCTAssertEqual(ProPhotoEncoder.sized(large, resolution: .mp48).extent, large.extent)
        let result = ProPhotoEncoder.sized(large, resolution: .mp24)
        XCTAssertLessThanOrEqual(result.extent.width * result.extent.height, 24_000_000)
        XCTAssertGreaterThan(result.extent.width * result.extent.height, 23_980_000)
    }
}
