import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Originals live in Application Support, never the purgeable Roll cache.
/// Only this actor owns the files and manifest writes. Capture resources are
/// immutable; every edit gets a new revision. Atomic directory publication
/// prevents partially copied originals from appearing in the library.
actor FilmyPhotoStore {
    static let shared = FilmyPhotoStore()

    enum StoreError: LocalizedError {
        case invalidDocument, unsupportedVersion, emptyOriginal, missingOriginal, editConflict, missingRendition
        var errorDescription: String? {
            switch self {
            case .invalidDocument: "This Filmy document is damaged. Its original files have not been deleted."
            case .unsupportedVersion: "This photo was created by a newer Filmy version. Update Filmy to edit it."
            case .emptyOriginal: "The camera did not provide a complete original."
            case .missingOriginal: "The original is missing. The existing Photos export is unchanged."
            case .editConflict: "This photo changed in another editor. Reopen it before saving another version."
            case .missingRendition: "Develop this version before exporting it."
            }
        }
    }

    struct Inventory: Sendable {
        let documents: [FilmyPhotoDocument]
        let unreadableCount: Int
    }

    private let root: URL
    private let files = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/FilmyPhotos", isDirectory: true)
    }

    func create(
        processed: Data, raw: Data?, liveMovieURL: URL?, capturedAt: Date,
        geometry: FilmyRenderGeometry, recipe: FilmRecipe, finish: PhotoFinish,
        settings: ProCaptureSettings
    ) throws -> FilmyPhotoDocument {
        guard !processed.isEmpty, let originalExtension = Self.imageExtension(processed),
              !settings.format.retainsRAW || raw?.isEmpty == false,
              !settings.livePhoto || liveMovieURL != nil,
              raw == nil || raw?.isEmpty == false, settings.incompatibility == nil else { throw StoreError.emptyOriginal }
        try makeDirectory(root)
        let id = UUID()
        let stage = root.appendingPathComponent(".\(id.uuidString).pending", isDirectory: true)
        let destination = directory(id)
        try makeDirectory(stage)
        do {
            try write(processed, to: stage.appendingPathComponent("original.\(originalExtension)"))
            if let raw {
                try write(raw, to: stage.appendingPathComponent("original.dng"))
            }
            if let liveMovieURL {
                let movie = stage.appendingPathComponent("original.mov")
                try files.copyItem(at: liveMovieURL, to: movie)
                try protect(movie)
                let bytes = try movie.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard bytes > 0 else { throw StoreError.emptyOriginal }
            }
            let revision = FilmyPhotoRevision(
                id: UUID(), createdAt: Date(), recipe: recipe, finish: finish,
                output: settings, renditionExtension: nil
            )
            let document = FilmyPhotoDocument(
                schemaVersion: FilmyPhotoDocument.currentSchemaVersion,
                id: id, capturedAt: capturedAt, originalExtension: originalExtension,
                hasRAW: raw != nil, hasLivePhoto: liveMovieURL != nil,
                geometry: geometry, revisions: [revision], photosAssetIdentifier: nil
            )
            try writeManifest(document, in: stage)
            try files.moveItem(at: stage, to: destination)
            return document
        } catch {
            try? files.removeItem(at: stage)
            throw error
        }
    }

    func inventory() throws -> Inventory {
        try makeDirectory(root)
        let children = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        var documents: [FilmyPhotoDocument] = []
        var unreadable = 0
        for url in children {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            do { documents.append(try load(id)) } catch { unreadable += 1 }
        }
        return Inventory(documents: documents.sorted { $0.capturedAt > $1.capturedAt }, unreadableCount: unreadable)
    }

    func load(_ id: UUID) throws -> FilmyPhotoDocument {
        let data = try Data(contentsOf: directory(id).appendingPathComponent("document.json"))
        let document = try JSONDecoder().decode(FilmyPhotoDocument.self, from: data)
        guard document.schemaVersion == FilmyPhotoDocument.currentSchemaVersion else { throw StoreError.unsupportedVersion }
        guard document.id == id, let original = document.originalFilename, !document.revisions.isEmpty,
              Set(document.revisions.map(\.id)).count == document.revisions.count,
              document.revisions.allSatisfy({ $0.renditionExtension == nil || $0.renditionFilename != nil }) else {
            throw StoreError.invalidDocument
        }
        guard files.fileExists(atPath: directory(id).appendingPathComponent(original).path) else { throw StoreError.missingOriginal }
        return document
    }

    func originalData(_ id: UUID) throws -> Data {
        let document = try load(id)
        guard let name = document.originalFilename else { throw StoreError.invalidDocument }
        return try Data(contentsOf: directory(id).appendingPathComponent(name), options: .mappedIfSafe)
    }

    func originalURL(_ id: UUID, raw: Bool = false) throws -> URL {
        let document = try load(id)
        guard let name = document.originalFilename, !raw || document.hasRAW else { throw StoreError.missingOriginal }
        let url = directory(id).appendingPathComponent(raw ? "original.dng" : name)
        guard files.fileExists(atPath: url.path) else { throw StoreError.missingOriginal }
        return url
    }

    func liveMovieURL(_ id: UUID) throws -> URL? {
        let document = try load(id)
        guard document.hasLivePhoto else { return nil }
        let url = directory(id).appendingPathComponent("original.mov")
        guard files.fileExists(atPath: url.path) else { throw StoreError.missingOriginal }
        return url
    }

    func renditionURL(_ id: UUID, revisionID: UUID? = nil) throws -> URL {
        let document = try load(id)
        let revision: FilmyPhotoRevision?
        if let revisionID { revision = document.revisions.first { $0.id == revisionID } }
        else { revision = document.currentRevision }
        guard let name = revision?.renditionFilename else { throw StoreError.missingRendition }
        let url = directory(id).appendingPathComponent(name)
        guard files.fileExists(atPath: url.path) else { throw StoreError.missingRendition }
        return url
    }

    func thumbnailData(_ id: UUID) throws -> Data? {
        let document = try load(id)
        guard let revision = document.currentRevision else { return nil }
        return try? Data(contentsOf: directory(id).appendingPathComponent("\(revision.id.uuidString)-thumb.jpg"))
    }

    @discardableResult
    func addRevision(
        _ id: UUID, expectedRevisionID: UUID, recipe: FilmRecipe, finish: PhotoFinish,
        settings: ProCaptureSettings, renderedData: Data
    ) throws -> FilmyPhotoDocument {
        var document = try load(id)
        guard document.currentRevision?.id == expectedRevisionID else { throw StoreError.editConflict }
        guard let ext = Self.imageExtension(renderedData) else { throw StoreError.missingRendition }
        let revision = FilmyPhotoRevision(
            id: UUID(), createdAt: Date(), recipe: recipe, finish: finish, output: settings, renditionExtension: ext
        )
        guard let name = revision.renditionFilename else { throw StoreError.invalidDocument }
        let url = directory(id).appendingPathComponent(name)
        try write(renderedData, to: url)
        document.revisions.append(revision)
        do {
            try writeManifest(document, in: directory(id))
        } catch {
            try? files.removeItem(at: url)
            throw error
        }
        // A failed thumbnail is recoverable and must not invalidate the edit.
        if let thumbnail = Self.thumbnail(renderedData) {
            try? write(thumbnail, to: directory(id).appendingPathComponent("\(revision.id.uuidString)-thumb.jpg"))
        }
        return document
    }

    func linkPhotosAsset(_ assetIdentifier: String, to id: UUID) throws {
        var document = try load(id)
        document.photosAssetIdentifier = assetIdentifier
        try writeManifest(document, in: directory(id))
    }

    /// Called only after explicit Delete Original confirmation, never by cache
    /// maintenance, Photos permission changes, or thumbnail eviction.
    func delete(_ id: UUID) throws {
        _ = try load(id)
        try files.removeItem(at: directory(id))
    }

    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func writeManifest(_ document: FilmyPhotoDocument, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(document), to: directory.appendingPathComponent("document.json"))
    }

    private func makeDirectory(_ url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        try protect(url)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try protect(url)
    }

    private func protect(_ url: URL) throws {
#if os(iOS)
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
#endif
    }

    static func imageExtension(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { return nil }
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "heic" }
        return nil
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
