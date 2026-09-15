@preconcurrency import Photos
import Foundation

/// Disk originals are the source of truth. Photos is an explicit, retryable export.
/// No capture is deleted merely because rendering, authorization, or export fails.
enum CaptureMediaStore {
    private static let lock = NSRecursiveLock()

    static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let url = base.appendingPathComponent("FilmyCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func directory(_ id: UUID) throws -> URL {
        let url = try root().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func file(_ name: String, in id: UUID) throws -> URL {
        guard CaptureModesPolicy.isSafeFilename(name) else { throw CaptureModesError.invalidImage }
        return try directory(id).appendingPathComponent(name)
    }

    static func preflight() throws {
        let values = try root().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage,
              bytes >= CaptureModesPolicy.minimumFreeBytes else { throw CaptureModesError.diskSpace }
    }

    static func persist(_ media: CaptureMedia) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try JSONEncoder().encode(media)
        try data.write(to: file("capture.json", in: media.id), options: .atomic)
    }

    static func saveRecipe(_ recipe: FilmRecipe, in id: UUID) throws {
        try JSONEncoder().encode(recipe).write(to: file("recipe.json", in: id), options: .atomic)
    }

    static func loadRecipe(in id: UUID) throws -> FilmRecipe {
        try JSONDecoder().decode(FilmRecipe.self, from: Data(contentsOf: file("recipe.json", in: id)))
    }

    static func delete(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.removeItem(at: directory(id))
    }

    static func load(_ id: UUID) throws -> CaptureMedia {
        lock.lock()
        defer { lock.unlock() }
        let data = try Data(contentsOf: file("capture.json", in: id))
        return try JSONDecoder().decode(CaptureMedia.self, from: data)
    }

    static func recent() throws -> [CaptureMedia] {
        lock.lock()
        defer { lock.unlock() }
        let folders = try FileManager.default.contentsOfDirectory(at: root(), includingPropertiesForKeys: nil)
        return folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent) else { return nil }
            // One damaged manifest must not hide every other recoverable capture.
            return try? load(id)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Recover a completed movie after termination between AVFoundation's final
    /// callback and the manifest update. Partial/empty movie files are not promoted.
    static func recoverableOriginals(_ media: CaptureMedia) throws -> [URL] {
        let folder = try directory(media.id)
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.lastPathComponent.hasPrefix("original-") }
            .filter { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Exports original encoded files, never UIImage conversions that discard depth
    /// or stereo metadata. Confirmed slots are persisted individually for retry.
    static func exportToPhotos(_ initial: CaptureMedia) async throws -> CaptureMedia {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw CaptureModesError.unavailable("Photos access is disabled. Captures remain saved in Filmy; enable access in Settings or share a file.")
        }
        var media = try load(initial.id)
        guard !media.outputs.isEmpty else {
            throw CaptureModesError.unavailable("This capture has originals only. Share the originals or retry processing first.")
        }
        for name in media.outputs where media.photosIdentifiers[name] == nil {
            try Task.checkCancellation()
            let url = try file(name, in: media.id)
            guard FileManager.default.fileExists(atPath: url.path) else { throw CaptureModesError.invalidImage }
            let receipt = PhotoReceipt()
            let date = media.createdAt
            let isVideo = media.mode.isVideo
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.creationDate = date
                request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: options)
                receipt.identifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            guard let identifier = receipt.identifier else {
                throw CaptureModesError.unavailable("Photos did not return an export receipt. Check Photos before retrying to avoid a duplicate.")
            }
            media.photosIdentifiers[name] = identifier
            try persist(media)
        }
        return media
    }

    /// Accessed by a Photos change block, then after its awaited completion only.
    private final class PhotoReceipt: @unchecked Sendable {
        var identifier: String?
    }
}
