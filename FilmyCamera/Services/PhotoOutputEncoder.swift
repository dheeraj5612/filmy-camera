import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a finished frame as a Photos-ready JPEG while preserving useful
/// camera provenance and keeping location data out of app-created exports.
enum PhotoOutputEncoder {
    static let outputProfileName = "sRGB IEC61966-2.1"
    static let recipeMetadataFormat = "filmy-camera.recipe-provenance"
    /// Preserve fine texture through the app's single finished-JPEG encode
    /// while keeping 12 MP files practical for Photos and the local Roll.
    static let jpegCompressionQuality = 0.95

    struct RecipeProvenanceMetadata: Codable, Equatable, Sendable {
        let format: String
        let metadataVersion: Int
        let appVersion: String
        let appBuild: String
        let recipeID: String
        let recipeName: String
        let filmBase: FilmRecipe.FilmBase
        let recipeSchemaVersion: Int
        let rendererVersion: String
        let provenance: FilmRecipe.Provenance

        init(recipe: FilmRecipe, appVersion: String, appBuild: String) {
            format = PhotoOutputEncoder.recipeMetadataFormat
            metadataVersion = 1
            self.appVersion = appVersion
            self.appBuild = appBuild
            recipeID = recipe.id
            recipeName = recipe.name
            filmBase = recipe.filmBase
            recipeSchemaVersion = recipe.schemaVersion
            rendererVersion = recipe.provenance.rendererVersion
            provenance = recipe.provenance
        }

        private enum CodingKeys: String, CodingKey {
            case format
            case metadataVersion
            case appVersion
            case appBuild
            case recipeID
            case recipeName
            case filmBase
            case recipeSchemaVersion
            case rendererVersion
            case provenance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            format = try container.decode(String.self, forKey: .format)
            metadataVersion = try container.decode(Int.self, forKey: .metadataVersion)
            // v1 provenance emitted before app version/build fields remains
            // readable; newly encoded payloads always populate both values.
            appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
            appBuild = try container.decodeIfPresent(String.self, forKey: .appBuild) ?? "unknown"
            recipeID = try container.decode(String.self, forKey: .recipeID)
            recipeName = try container.decode(String.self, forKey: .recipeName)
            filmBase = try container.decode(FilmRecipe.FilmBase.self, forKey: .filmBase)
            recipeSchemaVersion = try container.decode(Int.self, forKey: .recipeSchemaVersion)
            rendererVersion = try container.decode(String.self, forKey: .rendererVersion)
            provenance = try container.decode(FilmRecipe.Provenance.self, forKey: .provenance)
        }
    }

    static var currentApplicationVersion: String {
        bundleString(forKey: "CFBundleShortVersionString")
    }

    static var currentApplicationBuild: String {
        bundleString(forKey: "CFBundleVersion")
    }

    private static let preservedCaptureExifKeys: [String] = [
        kCGImagePropertyExifExposureTime as String,
        kCGImagePropertyExifExposureBiasValue as String,
        kCGImagePropertyExifExposureProgram as String,
        kCGImagePropertyExifISOSpeedRatings as String,
        kCGImagePropertyExifFNumber as String,
        kCGImagePropertyExifFocalLength as String,
        kCGImagePropertyExifFocalLenIn35mmFilm as String,
        kCGImagePropertyExifLensModel as String,
        kCGImagePropertyExifLensSpecification as String,
        kCGImagePropertyExifFlash as String,
        kCGImagePropertyExifMeteringMode as String,
        kCGImagePropertyExifWhiteBalance as String,
        kCGImagePropertyExifDateTimeOriginal as String,
        kCGImagePropertyExifDateTimeDigitized as String,
        kCGImagePropertyExifOffsetTimeOriginal as String,
        kCGImagePropertyExifOffsetTimeDigitized as String,
        kCGImagePropertyExifSubsecTimeOriginal as String,
        kCGImagePropertyExifSubsecTimeDigitized as String
    ]

    static func jpegData(
        for image: CGImage,
        sourceData: Data,
        capturedAt: Date,
        recipe: FilmRecipe,
        appVersion: String = currentApplicationVersion,
        appBuild: String = currentApplicationBuild
    ) -> Data? {
        // FilmRenderer.outputCGImage() establishes the actual sRGB conversion
        // before this boundary. Replacing the color space here makes that
        // contract explicit to ImageIO and ensures an ICC profile is emitted
        // for the JPEG rather than inheriting a source-camera profile.
        guard let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let outputImage = image.copy(colorSpace: sRGBColorSpace) else {
            return nil
        }

        // Build export metadata from an explicit allowlist. Source TIFF,
        // MakerApple, GPS, and other camera/device metadata must never cross
        // this boundary into an app-created JPEG. Capture facts such as
        // exposure, ISO, and lens are useful provenance and are copied below.
        var properties: [String: Any] = [
            kCGImagePropertyColorModel as String: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName as String: Self.outputProfileName,
            kCGImagePropertyPixelWidth as String: outputImage.width,
            kCGImagePropertyPixelHeight as String: outputImage.height,
            kCGImagePropertyOrientation as String: 1,
            kCGImageDestinationLossyCompressionQuality as String: Self.jpegCompressionQuality
        ]

        let tiff: [String: Any] = [
            kCGImagePropertyTIFFSoftware as String: "Filmy Camera",
            kCGImagePropertyTIFFImageDescription as String: "Filmy Camera • \(recipe.name)"
        ]
        properties[kCGImagePropertyTIFFDictionary as String] = tiff

        // The filtered frame may be aspect-fill cropped before encoding. Keep
        // the exported metadata truthful instead of carrying source-camera
        // dimensions into the finished JPEG.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        var exif = captureExif(from: sourceData)
        let fallbackDate = dateFormatter.string(from: capturedAt)
        let originalDateKey = kCGImagePropertyExifDateTimeOriginal as String
        let digitizedDateKey = kCGImagePropertyExifDateTimeDigitized as String
        let originalOffsetKey = kCGImagePropertyExifOffsetTimeOriginal as String
        let digitizedOffsetKey = kCGImagePropertyExifOffsetTimeDigitized as String
        if (exif[originalDateKey] as? String)?.isEmpty != false {
            exif[originalDateKey] = fallbackDate
            exif[originalOffsetKey] = "+00:00"
        }
        let digitizedDateWasDerived = (exif[digitizedDateKey] as? String)?.isEmpty != false
        if digitizedDateWasDerived {
            exif[digitizedDateKey] = exif[originalDateKey] ?? fallbackDate
        }
        if digitizedDateWasDerived,
           (exif[digitizedOffsetKey] as? String)?.isEmpty != false,
           let originalOffset = exif[originalOffsetKey] as? String {
            exif[digitizedOffsetKey] = originalOffset
        }
        exif[kCGImagePropertyExifPixelXDimension as String] = outputImage.width
        exif[kCGImagePropertyExifPixelYDimension as String] = outputImage.height
        // EXIF 2.3: 1 means sRGB. This complements the embedded ICC
        // profile for readers that inspect EXIF but do not parse ICC
        // resources.
        exif[kCGImagePropertyExifColorSpace as String] = 1
        if let provenance = provenanceJSON(
            for: recipe,
            appVersion: appVersion,
            appBuild: appBuild
        ) {
            exif[kCGImagePropertyExifUserComment as String] = provenance
        }
        properties[kCGImagePropertyExifDictionary as String] = exif

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }

    private static func captureExif(from sourceData: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let sourceExif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return [:]
        }

        return preservedCaptureExifKeys.reduce(into: [String: Any]()) { result, key in
            if let value = sourceExif[key] {
                result[key] = value
            }
        }
    }

    private static func bundleString(forKey key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "unknown"
        }
        return value
    }

    private static func provenanceJSON(
        for recipe: FilmRecipe,
        appVersion: String,
        appBuild: String
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(
            RecipeProvenanceMetadata(
                recipe: recipe,
                appVersion: appVersion,
                appBuild: appBuild
            )
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
