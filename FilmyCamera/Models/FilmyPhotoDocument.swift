import Foundation

/// Fully serialized edit inputs, not references to mutable catalog defaults.
struct FilmyRenderGeometry: Codable, Equatable, Sendable {
    var viewportWidth: Double
    var viewportHeight: Double
    var previewWidth: Double
    var previewHeight: Double
    var grainSeed: UInt32
    var flashFired: Bool
}

struct FilmyPhotoRevision: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let recipe: FilmRecipe
    let finish: PhotoFinish
    let output: ProCaptureSettings
    var renditionExtension: String?

    var renditionFilename: String? {
        guard let renditionExtension, ["jpg", "heic"].contains(renditionExtension) else { return nil }
        return "\(id.uuidString).\(renditionExtension)"
    }
}

struct FilmyPhotoDocument: Codable, Identifiable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let id: UUID
    let capturedAt: Date
    let originalExtension: String
    let hasRAW: Bool
    let hasLivePhoto: Bool
    let geometry: FilmyRenderGeometry
    var revisions: [FilmyPhotoRevision]
    var photosAssetIdentifier: String?

    var currentRevision: FilmyPhotoRevision? { revisions.last }
    var originalFilename: String? {
        guard ["jpg", "heic"].contains(originalExtension) else { return nil }
        return "original.\(originalExtension)"
    }
}
