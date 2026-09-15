import Foundation

struct FujiCameraPreset: Codable, Equatable, Sendable {
    var cameraPosition = "back"
    var deviceID: String?
    var zoom: Double = 1
    var exposureBias: Double = 0
    var manualISO: Double?
    var manualShutter: Double?
    var manualKelvin: Double?
    var manualTint: Double?
    var manualFocus: Double?
    var flashMode: Int = 0
    var aspect = "viewfinder"
    var timer = 0
    var finish = "photo"
}

struct FujiShootingBank: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    var name: String
    var recipe: FilmRecipe
    var settings: FujiShootingSettings
    var camera: FujiCameraPreset
    var savedAt: Date
}

struct FujiPreferences: Codable, Equatable, Sendable {
    var version = 1
    var settings = FujiShootingSettings()
    var banks: [FujiShootingBank] = []
    var selectedBank: Int?
    var quickControls = FujiQuickControl.allCases

    func normalized() -> Self {
        var copy = self
        copy.settings = settings.normalized()
        var usedBanks = Set<Int>()
        copy.banks = banks.filter { (1...7).contains($0.id) && usedBanks.insert($0.id).inserted }.map {
            var bank = $0
            bank.name = String(bank.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            bank.settings = bank.settings.normalized()
            return bank
        }.sorted { $0.id < $1.id }
        if let selectedBank, !copy.banks.contains(where: { $0.id == selectedBank }) { copy.selectedBank = nil }
        var usedControls = Set<FujiQuickControl>()
        copy.quickControls = quickControls.filter { usedControls.insert($0).inserted }
        return copy
    }

    static func load(from defaults: UserDefaults) -> (preferences: Self, recovered: Bool) {
        guard let data = defaults.data(forKey: "fuji.shooting.v1") else { return (Self(), false) }
        guard let result = try? JSONDecoder().decode(Self.self, from: data), result.version == 1 else {
            // Keep the bytes for recovery instead of overwriting an unknown schema.
            defaults.set(data, forKey: "fuji.shooting.recovery")
            return (Self(), true)
        }
        return (result.normalized(), false)
    }
}

struct FujiRAWAdjustment: Codable, Equatable, Hashable, Sendable {
    var exposure: Double = 0
    var useAsShotWhiteBalance = true
    var temperature: Double = 5600
    var tint: Double = 0
    var highlightRecovery: Double = 0.5
    var shadowLift: Double = 0

    func normalized() -> Self {
        var result = self
        result.exposure = FujiMath.finite(exposure, in: -5...5, fallback: 0)
        result.temperature = FujiMath.finite(temperature, in: 2000...12_000, fallback: 5600)
        result.tint = FujiMath.finite(tint, in: -150...150, fallback: 0)
        result.highlightRecovery = FujiMath.finite(highlightRecovery, in: 0...1, fallback: 0.5)
        result.shadowLift = FujiMath.finite(shadowLift, in: 0...1, fallback: 0)
        return result
    }
}

struct FujiOriginalRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let capturedAt: Date
    let isRAW: Bool
    let sourceFilename: String
    let sequenceID: UUID
    let dynamicRange: FujiDynamicRange
    let captureExposure: FujiExposureRecord?
    var recipe: FilmRecipe
    var adjustment: FujiRAWAdjustment
    let cropFactor: Double
    let viewportWidth: Double
    let viewportHeight: Double
    let label: String
    var version = 1
    static let rawExtensions: Set<String> = ["dng", "raf", "cr2", "cr3", "nef", "nrw", "arw", "orf", "rw2", "pef", "srw", "raw"]
    var hasSafeSourceFilename: Bool {
        isRAW ? Self.rawExtensions.contains(String(sourceFilename.dropFirst(7))) && sourceFilename.hasPrefix("source.")
            : sourceFilename == "source.jpg"
    }
}

struct FujiExposureRecord: Codable, Equatable, Hashable, Sendable {
    let iso: Double
    let seconds: Double
    let bracketOffset: Double
    let protectedStops: Double
}

struct FujiPendingExport: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let recipe: FilmRecipe
    let label: String
}

/// Durable, atomic originals and export outbox. No automatic eviction of user
/// originals or failed Photos writes. A manifest is written LAST, so a process
/// death cannot publish an entry whose image is missing.
actor FujiCaptureLibrary {
    static let shared = FujiCaptureLibrary()
    private let root: URL
    private let fileManager = FileManager.default
    static let maximumImportBytes = 200 * 1024 * 1024

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FujiCaptureLibrary/v1", isDirectory: true)
    }

    private func directory(_ collection: String, id: UUID) -> URL {
        root.appendingPathComponent(collection, isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func encode<T: Encodable>(_ record: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func retainOriginal(_ data: Data, record: FujiOriginalRecord) throws {
        guard !data.isEmpty, data.count <= Self.maximumImportBytes,
              record.hasSafeSourceFilename else { throw FujiShootingError.storageFailed }
        let folder = directory("originals", id: record.id)
        guard !fileManager.fileExists(atPath: folder.path) else { throw FujiShootingError.storageFailed }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(record.sourceFilename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try encode(record, to: folder.appendingPathComponent("record.json"))
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    func originalData(_ record: FujiOriginalRecord) throws -> Data {
        guard record.hasSafeSourceFilename else { throw FujiShootingError.storageFailed }
        return try Data(contentsOf: directory("originals", id: record.id).appendingPathComponent(record.sourceFilename), options: .mappedIfSafe)
    }

    func originalURL(_ record: FujiOriginalRecord) throws -> URL {
        guard record.hasSafeSourceFilename else { throw FujiShootingError.storageFailed }
        return directory("originals", id: record.id).appendingPathComponent(record.sourceFilename)
    }

    func updateOriginal(_ record: FujiOriginalRecord) throws {
        guard record.hasSafeSourceFilename else { throw FujiShootingError.storageFailed }
        let folder = directory("originals", id: record.id)
        guard fileManager.fileExists(atPath: folder.appendingPathComponent(record.sourceFilename).path) else {
            throw FujiShootingError.storageFailed
        }
        try encode(record, to: folder.appendingPathComponent("record.json"))
    }

    func originals() throws -> [FujiOriginalRecord] {
        try records(FujiOriginalRecord.self, in: "originals").filter { $0.version == 1 }.sorted { $0.capturedAt > $1.capturedAt }
    }

    func removeOriginal(id: UUID) throws {
        try fileManager.removeItem(at: directory("originals", id: id))
    }

    func enqueue(_ data: Data, recipe: FilmRecipe, capturedAt: Date, label: String) throws -> FujiPendingExport {
        guard !data.isEmpty else { throw FujiShootingError.storageFailed }
        let record = FujiPendingExport(id: UUID(), capturedAt: capturedAt, recipe: recipe, label: label)
        let folder = directory("outbox", id: record.id)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("image.jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try encode(record, to: folder.appendingPathComponent("record.json"))
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return record
    }

    func pendingExports() throws -> [FujiPendingExport] {
        try records(FujiPendingExport.self, in: "outbox").sorted { $0.capturedAt < $1.capturedAt }
    }

    func exportData(_ record: FujiPendingExport) throws -> Data {
        try Data(contentsOf: directory("outbox", id: record.id).appendingPathComponent("image.jpg"), options: .mappedIfSafe)
    }

    func markExported(_ record: FujiPendingExport) throws {
        try fileManager.removeItem(at: directory("outbox", id: record.id))
    }

    private func records<T: Decodable>(_ type: T.Type, in collection: String) throws -> [T] {
        let folder = root.appendingPathComponent(collection, isDirectory: true)
        guard fileManager.fileExists(atPath: folder.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        return try entries.compactMap { entry in
            // Only our UUID directories are trusted. Never traverse arbitrary
            // filenames from imported metadata or follow an external path.
            guard UUID(uuidString: entry.lastPathComponent) != nil else { return nil }
            let manifest = entry.appendingPathComponent("record.json")
            guard fileManager.fileExists(atPath: manifest.path) else { return nil }
            return try JSONDecoder().decode(type, from: Data(contentsOf: manifest))
        }
    }
}
