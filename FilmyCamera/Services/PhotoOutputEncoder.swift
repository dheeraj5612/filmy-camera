import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a finished frame as a Photos-ready JPEG while preserving useful
/// camera provenance and keeping location data out of app-created exports.
enum PhotoOutputEncoder {
    static let outputProfileName = "sRGB IEC61966-2.1"
    static let recipeMetadataFormat = "filmy-camera.recipe-provenance"

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
        sourceData: Data,
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
        tiff[kCGImagePropertyTIFFImageDescription as String] = "Filmy Camera • \(recipe.name)"
        properties[kCGImagePropertyTIFFDictionary as String] = tiff

        properties[kCGImagePropertyColorModel as String] = kCGImagePropertyColorModelRGB
        properties[kCGImagePropertyProfileName as String] = Self.outputProfileName

        // The filtered frame may be aspect-fill cropped before encoding. Keep
        // the exported metadata truthful instead of carrying source-camera
        // dimensions into the finished JPEG.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal as String] = dateFormatter.string(from: capturedAt)
        exif[kCGImagePropertyExifPixelXDimension as String] = outputImage.width
        exif[kCGImagePropertyExifPixelYDimension as String] = outputImage.height
        // EXIF 2.3: 1 means sRGB. This complements the embedded ICC profile
        // for readers that inspect EXIF but do not parse ICC resources.
        exif[kCGImagePropertyExifColorSpace as String] = 1
        if let provenance = provenanceJSON(for: recipe) {
            exif[kCGImagePropertyExifUserComment as String] = provenance
        }
        properties[kCGImagePropertyExifDictionary as String] = exif
        properties[kCGImagePropertyPixelWidth as String] = outputImage.width
        properties[kCGImagePropertyPixelHeight as String] = outputImage.height
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
