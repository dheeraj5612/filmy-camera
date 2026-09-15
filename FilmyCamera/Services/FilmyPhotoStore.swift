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
    case unsupportedVersion, corruptOriginal, invalidManifest, conflict, renderFailed, originalExportInProgress
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This photo was saved by a newer Filmy version. Its originals have not been changed."
        case .corruptOriginal: return "The original's integrity check failed. Its files have not been changed."
        case .invalidManifest: return "This photo's project file is incomplete or invalid. Its originals remain on disk."
        case .conflict: return "This photo changed while the edit was rendering. Reopen it before saving again."
        case .renderFailed: return "The edit could not be rendered. The previous edit and original are unchanged."
        case .originalExportInProgress: return "An original export is already in progress."
        }
    }
}

/// A project is user data, not a cache. A staged directory rename commits an
/// original; a manifest rename commits an edit. An interrupted edit can leave
/// an unreferenced rendition but never a manifest pointing at half-written data.
actor FilmyPhotoStore {
    static let shared = FilmyPhotoStore()
    let root: URL
    private let manager = FileManager.default
    private var exporting: Set<UUID> = []

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FilmyPhotos", isDirectory: true)
    }

    func insert(original: Data, raw: Data?, movieURL: URL?, capturedAt: Date,
                dimensions: ProPhotoDimensions, edit: FilmyPhotoEdit) throws -> FilmyPhotoProject {
        guard !original.isEmpty, raw == nil || raw?.isEmpty == false else { throw FilmyPhotoStoreError.invalidManifest }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let staging = root.appendingPathComponent(".staging-\(id.uuidString)", isDirectory: true)
        let destination = directory(id)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            let originalName = "original.\(ProPhotoEncoder.fileExtension(for: original))"
            try write(original, to: staging.appendingPathComponent(originalName))
            if let raw { try write(raw, to: staging.appendingPathComponent("original.dng")) }
            var movieHash: String?
            if let movieURL {
                let movie = staging.appendingPathComponent("original.mov")
                try manager.copyItem(at: movieURL, to: movie)
                try protect(movie)
                movieHash = try digest(file: movie)
            }
            let project = FilmyPhotoProject(schemaVersion: 1, id: id, capturedAt: capturedAt, sourceDimensions: dimensions,
                originalFilename: originalName, originalSHA256: Self.digest(original),
                rawFilename: raw == nil ? nil : "original.dng", rawSHA256: raw.map(Self.digest),
                movieFilename: movieURL == nil ? nil : "original.mov", movieSHA256: movieHash,
                initialEdit: edit, edit: edit, revision: 0, renditionFilename: nil, thumbnailFilename: nil,
                outputDimensions: nil, outputHasHDRGainMap: false, originalPhotosIdentifier: nil)
            try write(try JSONEncoder().encode(project), to: staging.appendingPathComponent("project.json"))
            try protect(staging)
            try manager.moveItem(at: staging, to: destination)
            return project
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    struct Listing: Sendable {
        let photos: [FilmyPhotoProject]
        let unreadableCount: Int
    }
    func list() throws -> Listing {
        guard manager.fileExists(atPath: root.path) else { return Listing(photos: [], unreadableCount: 0) }
        let directories = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var projects: [FilmyPhotoProject] = []
        var unreadable = 0
        for url in directories {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            do { projects.append(try load(id)) } catch { unreadable += 1 }
        }
        return Listing(photos: projects.sorted { $0.capturedAt > $1.capturedAt }, unreadableCount: unreadable)
    }

    func load(_ id: UUID) throws -> FilmyPhotoProject {
        let data = try Data(contentsOf: directory(id).appendingPathComponent("project.json"))
        let project = try JSONDecoder().decode(FilmyPhotoProject.self, from: data)
        guard project.schemaVersion == 1 else { throw FilmyPhotoStoreError.unsupportedVersion }
        guard project.id == id, project.revision >= 0 else { throw FilmyPhotoStoreError.invalidManifest }
        let names = [project.originalFilename, project.rawFilename, project.movieFilename,
                     project.renditionFilename, project.thumbnailFilename].compactMap { $0 }
        guard names.allSatisfy(Self.isSafeFilename) else { throw FilmyPhotoStoreError.invalidManifest }
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
        guard [project.originalFilename, project.rawFilename, project.movieFilename, project.renditionFilename,
               project.thumbnailFilename].compactMap({ $0 }).contains(filename) else { throw FilmyPhotoStoreError.invalidManifest }
        return directory(id).appendingPathComponent(filename)
    }

    func data(_ id: UUID, filename: String) throws -> Data {
        try Data(contentsOf: resourceURL(id, filename: filename), options: .mappedIfSafe)
    }

    struct Preview: @unchecked Sendable { let image: CGImage }
    func preview(_ id: UUID, original: Bool, maximum: Int, hdr: Bool) throws -> Preview {
        let project = try load(id)
        let filename = original ? project.originalFilename : (project.renditionFilename ?? project.originalFilename)
        let url = try resourceURL(id, filename: filename)
        guard let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true, .expandToHDR: hdr]),
              source.extent.width > 0, source.extent.height > 0 else { throw FilmyPhotoStoreError.renderFailed }
        let scale = min(1, CGFloat(max(1, min(maximum, 2048))) / max(source.extent.width, source.extent.height))
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let space = CGColorSpace(name: hdr ? CGColorSpace.extendedLinearDisplayP3 : CGColorSpace.displayP3)!
        guard let image = ProPhotoEncoder.context.createCGImage(small, from: small.extent.integral,
            format: hdr ? .RGBAh : .RGBA8, colorSpace: space) else { throw FilmyPhotoStoreError.renderFailed }
        return Preview(image: image)
    }

    @discardableResult
    func commitRendition(_ id: UUID, data: Data, edit: FilmyPhotoEdit, expectedRevision: Int) throws -> FilmyPhotoProject {
        var project = try load(id)
        guard project.revision == expectedRevision else { throw FilmyPhotoStoreError.conflict }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max) else {
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
            guard let thumbnail = Self.thumbnail(source) else { throw FilmyPhotoStoreError.renderFailed }
            try write(thumbnail, to: thumbnailURL)
            project.edit = edit
            project.revision += 1
            project.renditionFilename = renditionName
            project.thumbnailFilename = thumbnailName
            project.outputDimensions = ProPhotoDimensions(width: Int32(width), height: Int32(height))
            project.outputHasHDRGainMap = ProPhotoEncoder.containsHDRGainMap(data)
            try write(try JSONEncoder().encode(project), to: location.appendingPathComponent("project.json"))
        } catch {
            try? manager.removeItem(at: renditionURL)
            try? manager.removeItem(at: thumbnailURL)
            throw error
        }
        // Only obsolete derivatives are disposable. Originals are never GC'd.
        for filename in [previousRendition, previousThumbnail].compactMap({ $0 }) {
            try? manager.removeItem(at: location.appendingPathComponent(filename))
        }
        return project
    }

    func render(_ id: UUID, edit: FilmyPhotoEdit, expectedRevision: Int) async throws -> FilmyPhotoProject {
        let project = try load(id)
        guard project.revision == expectedRevision else { throw FilmyPhotoStoreError.conflict }
        let source = try original(id)
        let rendered = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                CameraViewModel.render(sourceData: source, recipe: edit.recipe, viewportSize: edit.viewport,
                    previewDrawableSize: edit.previewDrawable, capturedAt: project.capturedAt,
                    flashFired: edit.flashFired, grainSeed: edit.grainSeed, finish: edit.finish, outputOptions: edit.options)
            }
        }.value
        try Task.checkCancellation()
        guard let rendered else { throw FilmyPhotoStoreError.renderFailed }
        // The actor yielded during rendering. Recheck revision at commit.
        return try commitRendition(id, data: rendered.data, edit: edit, expectedRevision: expectedRevision)
    }

    /// Export the ORIGINAL pair. Never attach the unmodified movie to an
    /// independently filtered still: its content identifier/crop would differ.
    func exportOriginal(_ id: UUID, forceCopy: Bool = false) async throws {
        let project = try load(id)
        if project.originalPhotosIdentifier != nil && !forceCopy { return }
        guard exporting.insert(id).inserted else { throw FilmyPhotoStoreError.originalExportInProgress }
        defer { exporting.remove(id) }
        let data = try original(id)
        let raw = project.rawFilename == nil ? nil : try original(id, raw: true)
        let movie = project.movieFilename.map { directory(id).appendingPathComponent($0) }
        if let movie, try digest(file: movie) != project.movieSHA256 { throw FilmyPhotoStoreError.corruptOriginal }
        let identifier = try await FilmyOriginalExporter.save(photo: data, raw: raw, movie: movie, capturedAt: project.capturedAt)
        // An edit may have committed while Photos was writing. Do not replace
        // that edit with the older export-start manifest.
        var current = try load(id)
        current.originalPhotosIdentifier = identifier
        try write(try JSONEncoder().encode(current), to: directory(id).appendingPathComponent("project.json"))
    }

    func delete(_ id: UUID) throws {
        guard !exporting.contains(id) else { throw FilmyPhotoStoreError.originalExportInProgress }
        _ = try load(id)
        try manager.removeItem(at: directory(id))
    }

    static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && !name.contains("..") && !name.hasPrefix(".")
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func digest(file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    private func protect(_ url: URL) throws {
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    private static func thumbnail(_ source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
