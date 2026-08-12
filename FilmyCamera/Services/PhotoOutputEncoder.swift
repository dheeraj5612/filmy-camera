import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a finished frame as a Photos-ready JPEG while preserving useful
/// camera provenance and keeping location data out of app-created exports.
enum PhotoOutputEncoder {
    static func jpegData(
        for image: CGImage,
        sourceData: Data,
        capturedAt: Date
    ) -> Data? {
        var properties: [String: Any] = [:]
        if let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
           let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            // GPS is intentionally not copied. The app should not add a
            // location trail to an edited frame without an explicit user
            // choice.
            for key in [
                kCGImagePropertyTIFFDictionary as String,
                kCGImagePropertyExifDictionary as String,
                kCGImagePropertyMakerAppleDictionary as String
            ] {
                if let value = sourceProperties[key] {
                    properties[key] = value
                }
            }
        }

        var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFSoftware as String] = "Filmy Camera"
        properties[kCGImagePropertyTIFFDictionary as String] = tiff

        // The filtered frame may be aspect-fill cropped before encoding. Keep
        // the exported metadata truthful instead of carrying source-camera
        // dimensions into the finished JPEG.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal as String] = dateFormatter.string(from: capturedAt)
        exif[kCGImagePropertyExifPixelXDimension as String] = image.width
        exif[kCGImagePropertyExifPixelYDimension as String] = image.height
        properties[kCGImagePropertyExifDictionary as String] = exif
        properties[kCGImagePropertyPixelWidth as String] = image.width
        properties[kCGImagePropertyPixelHeight as String] = image.height
        properties[kCGImagePropertyOrientation as String] = 1

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }
}
