#if DEBUG
import CryptoKit
import Foundation
import ImageIO

/// Opt-in, debug-only capture evidence for comparing the exact camera source
/// with the finished JPEG. Nothing is written unless the explicit launch flag
/// or environment variable is present.
enum FilmyCaptureDiagnostics {
    static let launchArgument = "-FILMY_CAPTURE_DIAGNOSTICS"
    static let environmentVariable = "FILMY_CAPTURE_DIAGNOSTICS"

    struct Dimensions: Codable, Equatable, Sendable {
        let width: Int
        let height: Int
    }

    struct Size: Codable, Equatable, Sendable {
        let width: Double
        let height: Double
    }

    struct Metadata: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let capturedAt: Date
        let sourceDimensions: Dimensions
        let viewportSize: Size
        let previewDrawableSize: Size
        let grainSeed: UInt32
        let flashFired: Bool
        let finish: PhotoFinish
        let appVersion: String
        let appBuild: String
        let rendererVersion: String
        let recipe: FilmRecipe
        var finalDimensions: Dimensions?
        var sourceUniformTypeIdentifier: String?
        var sourceDataByteCount: Int
        var finalJPEGByteCount: Int
        var sourceDataSHA256: String
        var finalJPEGSHA256: String

        init(
            capturedAt: Date,
            sourceDimensions: Dimensions,
            viewportSize: Size,
            previewDrawableSize: Size,
            grainSeed: UInt32,
            flashFired: Bool,
            finish: PhotoFinish,
            appVersion: String,
            appBuild: String,
            recipe: FilmRecipe
        ) {
            schemaVersion = 1
            self.capturedAt = capturedAt
            self.sourceDimensions = sourceDimensions
            self.viewportSize = viewportSize
            self.previewDrawableSize = previewDrawableSize
            self.grainSeed = grainSeed
            self.flashFired = flashFired
            self.finish = finish
            self.appVersion = appVersion
            self.appBuild = appBuild
            rendererVersion = FilmRecipe.rendererVersion
            self.recipe = recipe
            finalDimensions = nil
            sourceUniformTypeIdentifier = nil
            sourceDataByteCount = 0
            finalJPEGByteCount = 0
            sourceDataSHA256 = ""
            finalJPEGSHA256 = ""
        }
    }

    private static let writeQueue = DispatchQueue(
        label: "com.filmycamera.capture-diagnostics",
        qos: .utility
    )

    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if arguments.contains(launchArgument) { return true }
        let value = environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes" || value == "on"
    }

    static func persist(
        originalData: Data,
        finalJPEGData: Data,
        metadata: Metadata,
        rootDirectory: URL? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            writeQueue.async {
                continuation.resume(returning: writeSynchronously(
                    originalData: originalData,
                    finalJPEGData: finalJPEGData,
                    metadata: metadata,
                    rootDirectory: rootDirectory
                ))
            }
        }
    }

    private static func writeSynchronously(
        originalData: Data,
        finalJPEGData: Data,
        metadata: Metadata,
        rootDirectory: URL?
    ) -> Bool {
        guard !originalData.isEmpty, !finalJPEGData.isEmpty else { return false }
        guard let parent = rootDirectory ?? defaultDirectory() else { return false }

        let fileManager = FileManager.default
        let latest = parent.appendingPathComponent("latest", isDirectory: true)
        let staging = parent.appendingPathComponent(
            ".latest-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: staging,
                withIntermediateDirectories: false
            )

            try originalData.write(
                to: staging.appendingPathComponent("source.capture"),
                options: .atomic
            )
            try finalJPEGData.write(
                to: staging.appendingPathComponent("final.jpg"),
                options: .atomic
            )

            var completedMetadata = metadata
            completedMetadata.finalDimensions = imageDimensions(from: finalJPEGData)
            completedMetadata.sourceUniformTypeIdentifier = imageTypeIdentifier(from: originalData)
            completedMetadata.sourceDataByteCount = originalData.count
            completedMetadata.finalJPEGByteCount = finalJPEGData.count
            completedMetadata.sourceDataSHA256 = sha256(originalData)
            completedMetadata.finalJPEGSHA256 = sha256(finalJPEGData)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let metadataData = try encoder.encode(completedMetadata)
            try metadataData.write(
                to: staging.appendingPathComponent("metadata.json"),
                options: .atomic
            )

            if fileManager.fileExists(atPath: latest.path) {
                try fileManager.removeItem(at: latest)
            }
            try fileManager.moveItem(at: staging, to: latest)
            return true
        } catch {
            try? fileManager.removeItem(at: staging)
            return false
        }
    }

    private static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("FilmyCaptureDiagnostics", isDirectory: true)
    }

    private static func imageDimensions(from data: Data) -> Dimensions? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            return nil
        }
        return Dimensions(width: width.intValue, height: height.intValue)
    }

    private static func imageTypeIdentifier(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        return type as String
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
#endif
