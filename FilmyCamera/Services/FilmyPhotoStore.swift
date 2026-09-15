import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FilmyPhotoEdit: Codable, Equatable, Sendable {
    var recipe: FilmRecipe
    var finish: PhotoFinish
    var options: ProCaptureOptions
    let viewport: CGSize
    let previewDrawable: CGSize
    let grainSeed: UInt32
    let flashFired: Bool
}

struct FilmyPhotoProject: Codable, Identifiable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let capturedAt: Date
    let sourceDimensions: ProPhotoDimensions
    let originalFilename: String
    let originalSHA256: String
    let rawFilename: String?
    let rawSHA256: String?
    let movieFilename: String?
    let movieSHA256: String?
    let initialEdit: FilmyPhotoEdit
    var edit: FilmyPhotoEdit
    var revision: Int
    var renditionFilename: String?
    var thumbnailFilename: String?
    var outputDimensions: ProPhotoDimensions?
    var outputHasHDRGainMap: Bool
    var originalPhotosIdentifier: String?
}

enum FilmyPhotoStoreError: LocalizedError, Equatable {
    case unsupportedVersion
    case corruptOriginal
    case invalidManifest
    case conflict
    case renderFailed
    case originalExportInProgress

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This photo was saved by a newer Filmy version. Its originals have not been changed."
        case .corruptOriginal:
            return "The original's integrity check failed. Its files have not been changed."
        case .invalidManifest:
            return "This photo's project file is incomplete or invalid. Its originals remain on disk."
        case .conflict:
            return "This photo changed while the edit was rendering. Reopen it before saving again."
        case .renderFailed:
            return "The edit could not be rendered. The previous edit and original are unchanged."
        case .originalExportInProgress:
            return "An original export is already in progress."
        }
    }
}

/// Originals live in Application Support, never the purgeable Roll cache.
/// The actor owns both legacy document manifests and the newer project
/// manifests. Original resources are immutable; every edit publishes a new
/// derivative before its manifest is atomically replaced.
actor FilmyPhotoStore {
    static let shared = FilmyPhotoStore()

    enum StoreError: LocalizedError {
        case invalidDocument
        case unsupportedVersion
        case emptyOriginal
        case missingOriginal
        case editConflict
        case missingRendition

        var errorDescription: String? {
            switch self {
            case .invalidDocument:
                return "This Filmy document is damaged. Its original files have not been deleted."
            case .unsupportedVersion:
                return "This photo was created by a newer Filmy version. Update Filmy to edit it."
            case .emptyOriginal:
                return "The camera did not provide a complete original."
            case .missingOriginal:
                return "The original is missing. The existing Photos export is unchanged."
            case .editConflict:
                return "This photo changed in another editor. Reopen it before saving another version."
            case .missingRendition:
                return "Develop this version before exporting it."
            }
        }
    }

    struct Inventory: Sendable {
        let documents: [FilmyPhotoDocument]
        let unreadableCount: Int
    }

    struct Listing: Sendable {
        let photos: [FilmyPhotoProject]
        let unreadableCount: Int
    }

    struct Preview: @unchecked Sendable {
        let image: CGImage
    }

    let root: URL
    private let files = FileManager.default
    private var exporting: Set<UUID> = []

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FilmyPhotos", isDirectory: true)
    }

    // MARK: Legacy document store

    func create(
        processed: Data,
        raw: Data?,
        liveMovieURL: URL?,
        capturedAt: Date,
        geometry: FilmyRenderGeometry,
        recipe: FilmRecipe,
        finish: PhotoFinish,
        settings: ProCaptureSettings
    ) throws -> FilmyPhotoDocument {
        guard !processed.isEmpty,
              let originalExtension = Self.imageExtension(processed),
              !settings.format.retainsRAW || raw?.isEmpty == false,
              !settings.livePhoto || liveMovieURL != nil,
              raw == nil || raw?.isEmpty == false,
              settings.incompatibility == nil else {
            throw StoreError.emptyOriginal
        }

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
                id: UUID(),
                createdAt: Date(),
                recipe: recipe,
                finish: finish,
                output: settings,
                renditionExtension: nil
            )
            let document = FilmyPhotoDocument(
                schemaVersion: FilmyPhotoDocument.currentSchemaVersion,
                id: id,
                capturedAt: capturedAt,
                originalExtension: originalExtension,
                hasRAW: raw != nil,
                hasLivePhoto: liveMovieURL != nil,
                geometry: geometry,
                revisions: [revision],
                photosAssetIdentifier: nil
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
        let children = try files.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        var documents: [FilmyPhotoDocument] = []
        var unreadable = 0
        for url in children {
            guard let id = UUID(uuidString: url.lastPathComponent),
                  files.fileExists(atPath: url.appendingPathComponent("document.json").path) else {
                continue
            }
            do {
                documents.append(try loadDocument(id))
            } catch {
                unreadable += 1
            }
        }
        return Inventory(
            documents: documents.sorted { $0.capturedAt > $1.capturedAt },
            unreadableCount: unreadable
        )
    }

    /// Loads the pre-project document format used by the existing library UI.
    func loadDocument(_ id: UUID) throws -> FilmyPhotoDocument {
        let data = try Data(contentsOf: directory(id).appendingPathComponent("document.json"))
        let document = try JSONDecoder().decode(FilmyPhotoDocument.self, from: data)
        guard document.schemaVersion == FilmyPhotoDocument.currentSchemaVersion else {
            throw StoreError.unsupportedVersion
        }
        guard document.id == id,
              let original = document.originalFilename,
              !document.revisions.isEmpty,
              Set(document.revisions.map(\.id)).count == document.revisions.count,
              document.revisions.allSatisfy({ $0.renditionExtension == nil || $0.renditionFilename != nil }) else {
            throw StoreError.invalidDocument
        }
        guard files.fileExists(atPath: directory(id).appendingPathComponent(original).path) else {
            throw StoreError.missingOriginal
        }
        return document
    }

    func originalData(_ id: UUID) throws -> Data {
        let document = try loadDocument(id)
        guard let name = document.originalFilename else { throw StoreError.invalidDocument }
        return try Data(contentsOf: directory(id).appendingPathComponent(name), options: .mappedIfSafe)
    }

    func originalURL(_ id: UUID, raw: Bool = false) throws -> URL {
        let document = try loadDocument(id)
        guard let name = document.originalFilename, !raw || document.hasRAW else {
            throw StoreError.missingOriginal
        }
        let url = directory(id).appendingPathComponent(raw ? "original.dng" : name)
        guard files.fileExists(atPath: url.path) else { throw StoreError.missingOriginal }
        return url
    }

    func liveMovieURL(_ id: UUID) throws -> URL? {
        let document = try loadDocument(id)
        guard document.hasLivePhoto else { return nil }
        let url = directory(id).appendingPathComponent("original.mov")
        guard files.fileExists(atPath: url.path) else { throw StoreError.missingOriginal }
        return url
    }

    func renditionURL(_ id: UUID, revisionID: UUID? = nil) throws -> URL {
        let document = try loadDocument(id)
        let revision: FilmyPhotoRevision?
        if let revisionID {
            revision = document.revisions.first { $0.id == revisionID }
        } else {
            revision = document.currentRevision
        }
        guard let name = revision?.renditionFilename else { throw StoreError.missingRendition }
        let url = directory(id).appendingPathComponent(name)
        guard files.fileExists(atPath: url.path) else { throw StoreError.missingRendition }
        return url
    }

    func thumbnailData(_ id: UUID) throws -> Data? {
        let document = try loadDocument(id)
        guard let revision = document.currentRevision else { return nil }
        return try? Data(contentsOf: directory(id).appendingPathComponent("\(revision.id.uuidString)-thumb.jpg"))
    }

    @discardableResult
    func addRevision(
        _ id: UUID,
        expectedRevisionID: UUID,
        recipe: FilmRecipe,
        finish: PhotoFinish,
        settings: ProCaptureSettings,
        renderedData: Data
    ) throws -> FilmyPhotoDocument {
        var document = try loadDocument(id)
        guard document.currentRevision?.id == expectedRevisionID else {
            throw StoreError.editConflict
        }
        guard let ext = Self.imageExtension(renderedData) else {
            throw StoreError.missingRendition
        }
        let revision = FilmyPhotoRevision(
            id: UUID(),
            createdAt: Date(),
            recipe: recipe,
            finish: finish,
            output: settings,
            renditionExtension: ext
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
        if let thumbnail = Self.thumbnail(renderedData) {
            try? write(thumbnail, to: directory(id).appendingPathComponent("\(revision.id.uuidString)-thumb.jpg"))
        }
        return document
    }

    func linkPhotosAsset(_ assetIdentifier: String, to id: UUID) throws {
        var document = try loadDocument(id)
        document.photosAssetIdentifier = assetIdentifier
        try writeManifest(document, in: directory(id))
    }

    // MARK: Persistent original projects

    func insert(
        original: Data,
        raw: Data?,
        movieURL: URL?,
        capturedAt: Date,
        dimensions: ProPhotoDimensions,
        edit: FilmyPhotoEdit
    ) throws -> FilmyPhotoProject {
        guard !original.isEmpty, raw == nil || raw?.isEmpty == false else {
            throw FilmyPhotoStoreError.invalidManifest
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)

        let id = UUID()
        let staging = root.appendingPathComponent(".staging-\(id.uuidString)", isDirectory: true)
        let destination = directory(id)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            let originalName = "original.\(ProPhotoEncoder.fileExtension(for: original))"
            guard Self.isSafeFilename(originalName),
                  originalName != "project.json",
                  originalName != "original.dng" else {
                throw FilmyPhotoStoreError.invalidManifest
            }
            try write(original, to: staging.appendingPathComponent(originalName))
            if let raw {
                try write(raw, to: staging.appendingPathComponent("original.dng"))
            }

            var movieHash: String?
            if let movieURL {
                let movie = staging.appendingPathComponent("original.mov")
                try files.copyItem(at: movieURL, to: movie)
                try protect(movie)
                movieHash = try digest(file: movie)
            }

            let project = FilmyPhotoProject(
                schemaVersion: 1,
                id: id,
                capturedAt: capturedAt,
                sourceDimensions: dimensions,
                originalFilename: originalName,
                originalSHA256: Self.digest(original),
                rawFilename: raw == nil ? nil : "original.dng",
                rawSHA256: raw.map(Self.digest),
                movieFilename: movieURL == nil ? nil : "original.mov",
                movieSHA256: movieHash,
                initialEdit: edit,
                edit: edit,
                revision: 0,
                renditionFilename: nil,
                thumbnailFilename: nil,
                outputDimensions: nil,
                outputHasHDRGainMap: false,
                originalPhotosIdentifier: nil
            )
            try write(try JSONEncoder().encode(project), to: staging.appendingPathComponent("project.json"))
            try protect(staging)
            try files.moveItem(at: staging, to: destination)
            return project
        } catch {
            try? files.removeItem(at: staging)
            throw error
        }
    }

    func list() throws -> Listing {
        guard files.fileExists(atPath: root.path) else {
            return Listing(photos: [], unreadableCount: 0)
        }
        let directories = try files.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var projects: [FilmyPhotoProject] = []
        var unreadable = 0
        for url in directories {
            guard let id = UUID(uuidString: url.lastPathComponent),
                  files.fileExists(atPath: url.appendingPathComponent("project.json").path) else {
                continue
            }
            do {
                projects.append(try load(id))
            } catch {
                unreadable += 1
            }
        }
        return Listing(
            photos: projects.sorted { $0.capturedAt > $1.capturedAt },
            unreadableCount: unreadable
        )
    }

    func load(_ id: UUID) throws -> FilmyPhotoProject {
        let data = try Data(contentsOf: directory(id).appendingPathComponent("project.json"))
        let project = try JSONDecoder().decode(FilmyPhotoProject.self, from: data)
        guard project.schemaVersion == 1 else { throw FilmyPhotoStoreError.unsupportedVersion }
        guard project.id == id, project.revision >= 0 else {
            throw FilmyPhotoStoreError.invalidManifest
        }
        let names = [
            project.originalFilename,
            project.rawFilename,
            project.movieFilename,
            project.renditionFilename,
            project.thumbnailFilename
        ].compactMap { $0 }
        guard names.allSatisfy(Self.isSafeFilename),
              Set(names + ["project.json"]).count == names.count + 1,
              project.renditionFilename.map({ $0.hasPrefix("edit-") }) ?? true,
              project.thumbnailFilename.map({ $0.hasPrefix("thumb-") }) ?? true,
              (project.rawFilename == nil) == (project.rawSHA256 == nil),
              (project.movieFilename == nil) == (project.movieSHA256 == nil) else {
            throw FilmyPhotoStoreError.invalidManifest
        }
        return project
    }

    func original(_ id: UUID, raw: Bool = false) throws -> Data {
        let project = try load(id)
        let name = raw ? project.rawFilename : project.originalFilename
        let checksum = raw ? project.rawSHA256 : project.originalSHA256
        guard let name, let checksum else { throw FilmyPhotoStoreError.invalidManifest }
        let data = try Data(contentsOf: directory(id).appendingPathComponent(name), options: .mappedIfSafe)
        guard Self.digest(data) == checksum else { throw FilmyPhotoStoreError.corruptOriginal }
        return data
    }

    func resourceURL(_ id: UUID, filename: String) throws -> URL {
        let project = try load(id)
        let resources = [
            project.originalFilename,
            project.rawFilename,
            project.movieFilename,
            project.renditionFilename,
            project.thumbnailFilename
        ].compactMap { $0 }
        guard resources.contains(filename) else { throw FilmyPhotoStoreError.invalidManifest }
        return directory(id).appendingPathComponent(filename)
    }

    func data(_ id: UUID, filename: String) throws -> Data {
        try Data(contentsOf: resourceURL(id, filename: filename), options: .mappedIfSafe)
    }

    func preview(_ id: UUID, original: Bool, maximum: Int, hdr: Bool) throws -> Preview {
        let project = try load(id)
        let filename = original ? project.originalFilename : (project.renditionFilename ?? project.originalFilename)
        let url = try resourceURL(id, filename: filename)
        let options: [CIImageOption: Any] = [.applyOrientationProperty: true]
        guard let source = CIImage(contentsOf: url, options: options),
              source.extent.width > 0, source.extent.height > 0 else {
            throw FilmyPhotoStoreError.renderFailed
        }
        let scale = min(
            1,
            CGFloat(max(1, min(maximum, 2048))) / max(source.extent.width, source.extent.height)
        )
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let space = CGColorSpace(
            name: hdr ? CGColorSpace.extendedLinearDisplayP3 : CGColorSpace.displayP3
        )!
        guard let image = ProPhotoEncoder.context.createCGImage(
            small,
            from: small.extent.integral,
            format: hdr ? .RGBAh : .RGBA8,
            colorSpace: space
        ) else {
            throw FilmyPhotoStoreError.renderFailed
        }
        return Preview(image: image)
    }

    @discardableResult
    func commitRendition(
        _ id: UUID,
        data: Data,
        edit: FilmyPhotoEdit,
        expectedRevision: Int
    ) throws -> FilmyPhotoProject {
        var project = try load(id)
        guard project.revision == expectedRevision else { throw FilmyPhotoStoreError.conflict }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0,
              height > 0,
              width <= Int(Int32.max),
              height <= Int(Int32.max) else {
            throw FilmyPhotoStoreError.renderFailed
        }

        let revisionID = UUID().uuidString
        let renditionName = "edit-\(revisionID).\(ProPhotoEncoder.fileExtension(for: data))"
        let thumbnailName = "thumb-\(revisionID).jpg"
        let location = directory(id)
        let renditionURL = location.appendingPathComponent(renditionName)
        let thumbnailURL = location.appendingPathComponent(thumbnailName)
        let previousRendition = project.renditionFilename
        let previousThumbnail = project.thumbnailFilename
        do {
            try write(data, to: renditionURL)
            guard let thumbnail = Self.thumbnail(source) else {
                throw FilmyPhotoStoreError.renderFailed
            }
            try write(thumbnail, to: thumbnailURL)
            project.edit = edit
            project.revision += 1
            project.renditionFilename = renditionName
            project.thumbnailFilename = thumbnailName
            project.outputDimensions = ProPhotoDimensions(width: Int32(width), height: Int32(height))
            project.outputHasHDRGainMap = ProPhotoEncoder.containsHDRGainMap(data)
            try write(try JSONEncoder().encode(project), to: location.appendingPathComponent("project.json"))
        } catch {
            try? files.removeItem(at: renditionURL)
            try? files.removeItem(at: thumbnailURL)
            throw error
        }

        let originals = Set([
            project.originalFilename,
            project.rawFilename,
            project.movieFilename,
            "project.json"
        ].compactMap { $0 })
        for filename in [previousRendition, previousThumbnail].compactMap({ $0 })
            where !originals.contains(filename) {
            try? files.removeItem(at: location.appendingPathComponent(filename))
        }
        return project
    }

    func render(
        _ id: UUID,
        edit: FilmyPhotoEdit,
        expectedRevision: Int
    ) async throws -> FilmyPhotoProject {
        let project = try load(id)
        guard project.revision == expectedRevision else { throw FilmyPhotoStoreError.conflict }
        let source = try original(id)
        let outputSettings = Self.legacySettings(for: edit.options)
        let rendered = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                CameraViewModel.render(
                    sourceData: source,
                    recipe: edit.recipe,
                    viewportSize: edit.viewport,
                    previewDrawableSize: edit.previewDrawable,
                    capturedAt: project.capturedAt,
                    flashFired: edit.flashFired,
                    grainSeed: edit.grainSeed,
                    finish: edit.finish,
                    outputSettings: outputSettings
                )
            }
        }.value
        try Task.checkCancellation()
        guard let rendered else { throw FilmyPhotoStoreError.renderFailed }
        return try commitRendition(
            id,
            data: rendered.data,
            edit: edit,
            expectedRevision: expectedRevision
        )
    }

    /// Exports the immutable original pair. A movie is copied into Photos only
    /// with the still from the same capture.
    func exportOriginal(_ id: UUID, forceCopy: Bool = false) async throws {
        let project = try load(id)
        if project.originalPhotosIdentifier != nil, !forceCopy { return }
        guard exporting.insert(id).inserted else {
            throw FilmyPhotoStoreError.originalExportInProgress
        }
        defer { exporting.remove(id) }

        let data = try original(id)
        let raw = project.rawFilename == nil ? nil : try original(id, raw: true)
        let movie = project.movieFilename.map { directory(id).appendingPathComponent($0) }
        if let movie {
            guard let expected = project.movieSHA256, try digest(file: movie) == expected else {
                throw FilmyPhotoStoreError.corruptOriginal
            }
        }
        let identifier = try await FilmyOriginalExporter.save(
            photo: data,
            raw: raw,
            movie: movie,
            capturedAt: project.capturedAt
        )
        var current = try load(id)
        current.originalPhotosIdentifier = identifier
        try write(try JSONEncoder().encode(current), to: directory(id).appendingPathComponent("project.json"))
    }

    // MARK: Shared deletion and helpers

    func delete(_ id: UUID) throws {
        guard !exporting.contains(id) else {
            throw FilmyPhotoStoreError.originalExportInProgress
        }
        let location = directory(id)
        if files.fileExists(atPath: location.appendingPathComponent("project.json").path) {
            _ = try load(id)
        } else {
            _ = try loadDocument(id)
        }
        try files.removeItem(at: location)
    }

    private static func legacySettings(for options: ProCaptureOptions) -> ProCaptureSettings {
        var settings = ProCaptureSettings()
        settings.resolution = ProCaptureSettings.Resolution(rawValue: options.resolution.rawValue) ?? .mp12
        switch options.raw {
        case .off:
            settings.format = options.codec == .heif ? .heif : .jpeg
        case .bayer:
            settings.format = .bayerRAW
        case .appleProRAW:
            settings.format = .proRAW
        }
        settings.dynamicRange = options.hdr ? .hdr : .sdr
        settings.colorGamut = options.codec == .heif ? .displayP3 : .sRGB
        settings.livePhoto = options.livePhoto
        return settings
    }

    static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("..")
            && !name.hasPrefix(".")
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func digest(file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty {
            hash.update(data: block)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func directory(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

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
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try protect(url)
    }

    private func protect(_ url: URL) throws {
        #if os(iOS)
        try files.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    static func imageExtension(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else {
            return nil
        }
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "heic" }
        return nil
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source)
    }

    private static func thumbnail(_ source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
