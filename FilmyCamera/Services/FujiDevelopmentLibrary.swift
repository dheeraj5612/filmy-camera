import Foundation

struct FujiStoredPhoto: Codable, Identifiable, Sendable {
    let id: UUID
    let groupID: UUID
    let metadata: FujiCaptureMetadata
    var recipe: FilmRecipe
    var adjustments = FujiDevelopmentAdjustments()
    var cropFactor: Double = 1
    var aspectRatio: Double? = nil
    var finish: PhotoFinish = .photo
    var exportedToPhotos = false
    var sourceName: String { metadata.sourceKind.isRAW ? "original.dng" : "original.image" }
}

/// Originals are immutable files. Editing only replaces the small JSON
/// sidecar. UUID paths, atomic writes and a storage budget bound the archive.
actor FujiDevelopmentLibrary {
    static let shared = FujiDevelopmentLibrary()
    private let root: URL
    private let maximumBytes: Int

    init(root: URL? = nil, maximumBytes: Int = 2_000_000_000) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FujiDevelopment", isDirectory: true)
        self.maximumBytes = maximumBytes
    }

    func store(_ frame: FujiSourceFrame, recipe: FilmRecipe, groupID: UUID, crop: Double, aspect: Double?) throws -> FujiStoredPhoto {
        guard frame.data.count <= FujiLimits.maximumSourceBytes else { throw FujiCaptureError.invalidImage }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let usage = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard frame.data.count <= maximumBytes - min(usage, maximumBytes) else {
            throw FujiCaptureError.unavailable("The 2 GB development library is full. Export or delete originals in Q > RAW development.")
        }
        let record = FujiStoredPhoto(id: UUID(), groupID: groupID, metadata: frame.metadata, recipe: recipe,
                                     cropFactor: crop, aspectRatio: aspect)
        let directory = directory(for: record.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try frame.data.write(to: directory.appendingPathComponent(record.sourceName), options: .atomic)
            try update(record)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return record
    }

    func list() throws -> [FujiStoredPhoto] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url.appendingPathComponent("development.json")), data.count < 1_000_000,
                      let record = try? JSONDecoder().decode(FujiStoredPhoto.self, from: data),
                      record.id.uuidString == url.lastPathComponent else { return nil }
                return record
            }.sorted { $0.metadata.capturedAt > $1.metadata.capturedAt }
    }

    func frame(for record: FujiStoredPhoto) throws -> FujiSourceFrame {
        let url = sourceURL(for: record)
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= FujiLimits.maximumSourceBytes else { throw FujiCaptureError.invalidImage }
        return FujiSourceFrame(data: try Data(contentsOf: url, options: .mappedIfSafe), metadata: record.metadata)
    }

    func update(_ record: FujiStoredPhoto) throws {
        var validated = record
        validated.adjustments = record.adjustments.validated()
        try JSONEncoder().encode(validated).write(to: directory(for: record.id).appendingPathComponent("development.json"), options: .atomic)
    }

    func delete(_ record: FujiStoredPhoto) throws { try FileManager.default.removeItem(at: directory(for: record.id)) }
    func sourceURL(for record: FujiStoredPhoto) -> URL { directory(for: record.id).appendingPathComponent(record.sourceName) }
    private func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
}
