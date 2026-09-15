@preconcurrency import Photos
import Foundation

/// PhotoKit associates the exact camera-produced still and paired movie. RAW
/// is an alternate resource of that original, not a second filtered JPEG.
enum FilmyOriginalExporter {
    private final class Identifier: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?
        func set(_ value: String?) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> String? { lock.lock(); defer { lock.unlock() }; return value }
    }
    static func save(photo: Data, raw: Data?, movie: URL?, capturedAt: Date) async throws -> String {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status = current == .notDetermined ? await PHPhotoLibrary.requestAuthorization(for: .addOnly) : current
        guard status == .authorized || status == .limited else { throw PhotoLibrarySaveError.accessDenied }
        let identifier = Identifier()
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = capturedAt
                request.addResource(with: .photo, data: photo, options: nil)
                if let raw { request.addResource(with: .alternatePhoto, data: raw, options: nil) }
                if let movie {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(with: .pairedVideo, fileURL: movie, options: options)
                }
                identifier.set(request.placeholderForCreatedAsset?.localIdentifier)
            } completionHandler: { success, error in
                if success, let value = identifier.get() { continuation.resume(returning: value) }
                else { continuation.resume(throwing: error ?? PhotoLibrarySaveError.writeFailed) }
            }
        }
    }
}
