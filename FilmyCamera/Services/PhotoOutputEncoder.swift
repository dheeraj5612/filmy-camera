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
        let recipeID: String
        let recipeName: String
        let filmBase: FilmRecipe.FilmBase
        let recipeSchemaVersion: Int
        let rendererVersion: String
        let provenance: FilmRecipe.Provenance

        init(recipe: FilmRecipe) {
            format = PhotoOutputEncoder.recipeMetadataFormat
            metadataVersion = 1
            recipeID = recipe.id
            recipeName = recipe.name
            filmBase = recipe.filmBase
            recipeSchemaVersion = recipe.schemaVersion
            rendererVersion = recipe.provenance.rendererVersion
            provenance = recipe.provenance
        }
    }

    static func jpegData(
        for image: CGImage,
        sourceData _: Data,
        capturedAt: Date,
        recipe: FilmRecipe
    ) -> Data? {
        // FilmRenderer.outputCGImage() establishes the actual sRGB conversion
        // before this boundary. Replacing the color space here makes that
        // contract explicit to ImageIO and ensures an ICC profile is emitted
        // for the JPEG rather than inheriting a source-camera profile.
        guard let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let outputImage = image.copy(colorSpace: sRGBColorSpace) else {
            return nil
        }

        // Build export metadata from an explicit allowlist. Source TIFF, EXIF,
        // MakerApple, GPS, and other camera/device metadata must never cross
        // this boundary into an app-created JPEG.
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
        var exif: [String: Any] = [
            kCGImagePropertyExifDateTimeOriginal as String: dateFormatter.string(from: capturedAt),
            kCGImagePropertyExifPixelXDimension as String: outputImage.width,
            kCGImagePropertyExifPixelYDimension as String: outputImage.height,
            // EXIF 2.3: 1 means sRGB. This complements the embedded ICC
            // profile for readers that inspect EXIF but do not parse ICC
            // resources.
            kCGImagePropertyExifColorSpace as String: 1
        ]
        if let provenance = provenanceJSON(for: recipe) {
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

    private static func provenanceJSON(for recipe: FilmRecipe) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(RecipeProvenanceMetadata(recipe: recipe)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
