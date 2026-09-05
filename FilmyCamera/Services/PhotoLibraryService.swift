import Combine
import Foundation
@preconcurrency import Photos
import PhotosUI
import ImageIO
import UIKit

struct SavedFrameMetadata: Codable, Hashable, Sendable {
    let recipe: FilmRecipe
    let capturedAt: Date
}

struct LocalSavedFrame: Identifiable, Hashable, Sendable {
    let assetIdentifier: String
    let pixelWidth: Int
    let pixelHeight: Int

    var id: String { assetIdentifier }
}

struct PhotoPixelDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
}

enum PhotoLibraryGalleryAsset: Identifiable {
    case photos(PHAsset)
    case cached(LocalSavedFrame)

    var id: String { assetIdentifier }

    var assetIdentifier: String {
        switch self {
        case .photos(let asset):
            return asset.localIdentifier
        case .cached(let frame):
            return frame.assetIdentifier
        }
    }

    var pixelWidth: Int {
        switch self {
        case .photos(let asset):
            return asset.pixelWidth
        case .cached(let frame):
            return frame.pixelWidth
        }
    }

    var pixelHeight: Int {
        switch self {
        case .photos(let asset):
            return asset.pixelHeight
        case .cached(let frame):
            return frame.pixelHeight
        }
    }

    var isPhotosAsset: Bool {
        if case .photos = self { return true }
        return false
    }
}

enum PhotoLibraryAuthorizationPolicy {
    static func canRead(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    static func canAdd(_ status: PHAuthorizationStatus) -> Bool {
        // Limited access is a read/write concept. The add-only access level
        // reports .authorized when the app may create new Photos assets.
        status == .authorized
    }

    static func canManageCollections(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized
    }
}

struct PhotoLibraryImageRequestKey: Hashable, Sendable {
    let assetIdentifier: String
    let authorizationStatusRawValue: Int?
}

enum PhotoLibraryThumbnailCachePolicy {
    static let maxPixelSize = 600

    /// Only small, finite requests enter the decoded thumbnail cache. Full
    /// detail requests and Photos' maximum-size sentinel bypass it entirely.
    static func key(
        assetIdentifier: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        authorizationStatus: PHAuthorizationStatus?,
        revision: String?
    ) -> String? {
        guard !assetIdentifier.isEmpty,
              targetSize.width.isFinite,
              targetSize.height.isFinite,
              targetSize.width > 0,
              targetSize.height > 0,
              max(targetSize.width, targetSize.height) <= CGFloat(maxPixelSize) else {
            return nil
        }

        let width = max(Int(targetSize.width.rounded(.up)), 1)
        let height = max(Int(targetSize.height.rounded(.up)), 1)
        let mode = contentMode == .aspectFit ? "fit" : "fill"
        let status = authorizationStatus?.rawValue ?? -1
        return "\(assetIdentifier)|\(width)x\(height)|\(mode)|\(status)|\(revision ?? "-")"
    }
}

enum PhotoLibraryGalleryImagePolicy {
    static func canLoad(
        isPhotosAsset: Bool,
        authorizationStatus: PHAuthorizationStatus
    ) -> Bool {
        !isPhotosAsset || PhotoLibraryAuthorizationPolicy.canRead(authorizationStatus)
    }

    static func requestKey(
        assetIdentifier: String,
        isPhotosAsset: Bool,
        authorizationStatus: PHAuthorizationStatus
    ) -> PhotoLibraryImageRequestKey {
        PhotoLibraryImageRequestKey(
            assetIdentifier: assetIdentifier,
            authorizationStatusRawValue: isPhotosAsset ? authorizationStatus.rawValue : nil
        )
    }
}

enum PhotoLibraryServiceError: LocalizedError, Sendable {
    case accessDenied
    case notOwned
    case changeFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photos access is needed to manage this frame. Enable it in Settings, then try again."
        case .notOwned:
            return "Filmy Camera can only remove frames that it created. This frame was left in Photos."
        case .changeFailed:
            return "Photos could not update this frame. Try again in a moment."
        }
    }
}

enum PhotoLibrarySaveError: LocalizedError, Equatable, Sendable {
    case accessDenied
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photo access is needed to save this frame. Enable Photos access in Settings, then try again."
        case .writeFailed:
            return "Photos could not save this frame. Keep the review open and try again in a moment."
        }
    }

    static func failure(for authorizationStatus: PHAuthorizationStatus) -> Self {
        PhotoLibraryAuthorizationPolicy.canAdd(authorizationStatus) ? .writeFailed : .accessDenied
    }
}

@MainActor
protocol PhotoSaving: AnyObject {
    func save(
        image: UIImage,
        imageData: Data?,
        recipe: FilmRecipe,
        capturedAt: Date,
        completion: @escaping @MainActor (Result<Void, PhotoLibrarySaveError>) -> Void
    )
}

enum PhotoLibraryCompletionBridge {
    private final class MainActorCompletionBox: @unchecked Sendable {
        private let completion: @MainActor (Bool) -> Void

        init(completion: @escaping @MainActor (Bool) -> Void) {
            self.completion = completion
        }

        nonisolated func callAsynchronously(with success: Bool) {
            Task { @MainActor in
                completion(success)
            }
        }
    }

    private final class MainActorAsyncCompletionBox: @unchecked Sendable {
        private let completion: @MainActor (Bool) async -> Void

        init(completion: @escaping @MainActor (Bool) async -> Void) {
            self.completion = completion
        }

        nonisolated func callAsynchronously(with success: Bool) {
            Task { @MainActor in
                await completion(success)
            }
        }
    }

    /// PhotoKit invokes change completions on its own serial queue. Build the
    /// callback outside main-actor isolation, then explicitly hop before
    /// touching service state or SwiftUI-facing completion handlers.
    nonisolated static func mainActor(
        _ completion: @escaping @MainActor (Bool) -> Void
    ) -> @Sendable (Bool, Error?) -> Void {
        let box = MainActorCompletionBox(completion: completion)
        return { success, _ in
            box.callAsynchronously(with: success)
        }
    }

    /// Async variant used when a PhotoKit result must await local durability
    /// before the UI is told that the save is complete.
    nonisolated static func mainActorAsync(
        _ completion: @escaping @MainActor (Bool) async -> Void
    ) -> @Sendable (Bool, Error?) -> Void {
        let box = MainActorAsyncCompletionBox(completion: completion)
        return { success, _ in
            box.callAsynchronously(with: success)
        }
    }
}

enum PhotoLibraryAssetOwnership {
    static func contains(_ assetIdentifier: String, in savedIdentifiers: [String]) -> Bool {
        guard !assetIdentifier.isEmpty else { return false }
        return savedIdentifiers.contains(assetIdentifier)
    }

    static func adding(
        _ assetIdentifier: String,
        to savedIdentifiers: [String],
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }
        guard !assetIdentifier.isEmpty else {
            return normalized(savedIdentifiers, limit: limit)
        }

        return normalized(
            [assetIdentifier] + savedIdentifiers,
            limit: limit
        )
    }

    static func removing(_ assetIdentifier: String, from savedIdentifiers: [String]) -> [String] {
        savedIdentifiers.filter { $0 != assetIdentifier }
    }

    static func normalized(_ savedIdentifiers: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }

        var seen = Set<String>()
        return savedIdentifiers
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

enum PhotoLibraryCachePath {
    struct CleanupResult: Equatable {
        let removedFilenames: Set<String>
        let failedFilenames: Set<String>
    }

    static func fileURL(filename: String, in directory: URL) -> URL? {
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              URL(fileURLWithPath: filename).lastPathComponent == filename else {
            return nil
        }

        let directoryURL = directory.standardizedFileURL
        let fileURL = directoryURL
            .appendingPathComponent(filename, isDirectory: false)
            .standardizedFileURL
        guard fileURL.deletingLastPathComponent() == directoryURL else { return nil }
        return fileURL
    }

    static func regularFileURLs(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> [URL]? {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return nil
        }

        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    static func removeRegularFiles(
        in directory: URL,
        preservingFilenames: Set<String> = [],
        fileManager: FileManager = .default,
        removeItem: ((URL) throws -> Void)? = nil
    ) -> CleanupResult? {
        guard let regularFiles = regularFileURLs(in: directory, fileManager: fileManager) else {
            return nil
        }

        let remove = removeItem ?? { try fileManager.removeItem(at: $0) }
        var removedFilenames = Set<String>()
        var failedFilenames = Set<String>()
        for fileURL in regularFiles where !preservingFilenames.contains(fileURL.lastPathComponent) {
            do {
                try remove(fileURL)
                removedFilenames.insert(fileURL.lastPathComponent)
            } catch {
                failedFilenames.insert(fileURL.lastPathComponent)
            }
        }

        return CleanupResult(
            removedFilenames: removedFilenames,
            failedFilenames: failedFilenames
        )
    }
}

@MainActor
final class PhotoLibraryService: ObservableObject {
    private final class IdentifierBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?

        func set(_ value: String?) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct CachedThumbnail: @unchecked Sendable {
        let image: UIImage?
    }

    private final class ImageBox: @unchecked Sendable {
        let image: UIImage

        init(_ image: UIImage) {
            self.image = image
        }
    }

    // Internal so the cacheability state machine can be regression-tested
    // without requiring Photos permission or a live PHImage request.
    internal final class ImageRequestState: @unchecked Sendable {
        private let lock = NSLock()
        private let imageManager: PHImageManager
        private var requestID: PHImageRequestID?
        private var continuation: CheckedContinuation<UIImage?, Never>?
        private var fallbackImage: UIImage?
        private var didFinish = false
        private var didProduceCacheableImage = false

        init(imageManager: PHImageManager) {
            self.imageManager = imageManager
        }

        func install(_ continuation: CheckedContinuation<UIImage?, Never>) {
            lock.lock()
            let shouldFinish = didFinish
            if !shouldFinish {
                self.continuation = continuation
            }
            lock.unlock()

            if shouldFinish {
                continuation.resume(returning: nil)
            }
        }

        func install(requestID: PHImageRequestID) {
            lock.lock()
            let shouldCancel = didFinish
            if !shouldCancel {
                self.requestID = requestID
            }
            lock.unlock()

            if shouldCancel {
                imageManager.cancelImageRequest(requestID)
            }
        }

        func rememberFallback(_ image: UIImage?) {
            guard let image else { return }

            lock.lock()
            if !didFinish {
                fallbackImage = image
            }
            lock.unlock()
        }

        func finish(
            with image: UIImage?,
            cancelRequest: Bool = false,
            allowFallback: Bool = false,
            cacheable: Bool = false
        ) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            didProduceCacheableImage = cacheable && image != nil
            let resolvedImage = image ?? (allowFallback ? fallbackImage : nil)
            fallbackImage = nil
            let continuation = self.continuation
            self.continuation = nil
            let requestID = self.requestID
            self.requestID = nil
            lock.unlock()

            if cancelRequest, let requestID {
                imageManager.cancelImageRequest(requestID)
            }
            continuation?.resume(returning: resolvedImage)
        }

        func canCacheResult() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return didProduceCacheableImage
        }

        func cancel() {
            finish(with: nil, cancelRequest: true)
        }
    }

    private struct SavedFrameResource: Codable, Hashable, Sendable {
        let filename: String
        let pixelWidth: Int
        let pixelHeight: Int
    }

    @Published private(set) var assets: [PHAsset] = [] {
        didSet { galleryAssetsCache = nil }
    }
    @Published private(set) var localSavedFrames: [LocalSavedFrame] = [] {
        didSet { galleryAssetsCache = nil }
    }
    @Published private(set) var hasLocalCache = false
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var addOnlyAuthorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false

    private let albumTitle = "Filmy Camera"
    private let savedAssetIdentifiersKey = "filmyCamera.savedAssetIdentifiers"
    private let savedFrameMetadataKey = "filmyCamera.savedFrameMetadata"
    private nonisolated static let savedFrameResourcesKey = "filmyCamera.savedFrameResources"
    private var savedFrameResourcesKey: String { Self.savedFrameResourcesKey }
    private let localFramesDirectoryName = "FilmyCameraFrames"
    private let shareDirectoryName = "FilmyCameraShare"
    private let localCacheMaxBytes = 250 * 1024 * 1024
    private let isUITesting: Bool
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private var thumbnailCacheGeneration: UInt64 = 0
    private var savedFrameResourcesCache: [String: SavedFrameResource]?

    private func invalidateThumbnailCache() {
        thumbnailCacheGeneration &+= 1
        thumbnailCache.removeAllObjects()
    }

    private(set) var metadataByAssetIdentifier: [String: SavedFrameMetadata] {
        didSet { galleryAssetsCache = nil }
    }
    private var galleryAssetsCache: [PhotoLibraryGalleryAsset]?

    init() {
        isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        thumbnailCache.countLimit = 80
        thumbnailCache.totalCostLimit = 48 * 1024 * 1024
        metadataByAssetIdentifier = Self.loadMetadata(forKey: savedFrameMetadataKey)
        if isUITesting {
            authorizationStatus = .denied
            addOnlyAuthorizationStatus = .denied
        } else {
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            addOnlyAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            // Disk maintenance is not needed for the first frame and must not
            // block the main actor: it runs detached and only the outcome is
            // applied here, after which the Roll thumbnail refreshes.
            scheduleCacheMaintenance(includingLaunchPasses: true)
        }
    }

    private struct CacheMaintenanceInput: Sendable {
        let legacyDirectoryURL: URL?
        let directoryURL: URL?
        let shareDirectoryURL: URL?
        let savedAssetIdentifiers: [String]
        let resources: [String: SavedFrameResource]
        let maxBytes: Int
        let includingLaunchPasses: Bool
    }

    private struct CacheMaintenanceResult: Sendable {
        /// Identifiers whose local copy was evicted or found missing. Applied
        /// as removals so a save that landed meanwhile is never overwritten.
        let removedIdentifiers: Set<String>
    }

    private var cacheMaintenanceTask: Task<Void, Never>?
    private var cacheWriteGeneration: UInt64 = 0

    /// Runs migration, reconciliation, budget trimming, and share-file pruning
    /// on a background executor, then applies the result on the main actor.
    private func scheduleCacheMaintenance(includingLaunchPasses: Bool) {
        let input = CacheMaintenanceInput(
            legacyDirectoryURL: legacyLocalFramesDirectoryURL,
            directoryURL: localFramesDirectoryURL,
            shareDirectoryURL: temporaryShareDirectoryURL,
            savedAssetIdentifiers: savedAssetIdentifiers,
            resources: savedFrameResources,
            maxBytes: localCacheMaxBytes,
            includingLaunchPasses: includingLaunchPasses
        )
        let previous = cacheMaintenanceTask
        cacheMaintenanceTask = Task(priority: .utility) { [weak self] in
            // Passes touch the same directory; keep them strictly sequential.
            await previous?.value
            let result = await Task.detached(priority: .utility) {
                Self.runCacheMaintenance(input)
            }.value
            guard let self else { return }
            if !result.removedIdentifiers.isEmpty {
                var resources = self.savedFrameResources
                for identifier in result.removedIdentifiers {
                    resources.removeValue(forKey: identifier)
                }
                self.savedFrameResources = resources
            }
            self.refreshCachedFrames(excluding: Set(self.assets.map(\.localIdentifier)))
        }
    }

    private nonisolated static func runCacheMaintenance(_ input: CacheMaintenanceInput) -> CacheMaintenanceResult {
        if input.includingLaunchPasses {
            migrateLocalFrameCache(from: input.legacyDirectoryURL, to: input.directoryURL)
            reconcileLocalCache(in: input.directoryURL)
        }
        let removed = trimLocalCache(
            in: input.directoryURL,
            savedAssetIdentifiers: input.savedAssetIdentifiers,
            resources: input.resources,
            maxBytes: input.maxBytes
        )
        if input.includingLaunchPasses {
            pruneTemporaryShareFiles(in: input.shareDirectoryURL)
        }
        return CacheMaintenanceResult(removedIdentifiers: removed)
    }

    var canSaveToPhotos: Bool {
        PhotoLibraryAuthorizationPolicy.canAdd(addOnlyAuthorizationStatus)
    }

    var canDeletePhotos: Bool {
        !isUITesting && PhotoLibraryAuthorizationPolicy.canRead(authorizationStatus)
    }

    func canDelete(asset: PhotoLibraryGalleryAsset) -> Bool {
        guard case .photos(let photoAsset) = asset else { return false }
        return canDeletePhotos && PhotoLibraryAssetOwnership.contains(
            photoAsset.localIdentifier,
            in: savedAssetIdentifiers
        )
    }

    var galleryAssets: [PhotoLibraryGalleryAsset] {
        if let galleryAssetsCache {
            return galleryAssetsCache
        }

        let photoIdentifiers = Set(assets.map(\.localIdentifier))
        let combined = assets.map(PhotoLibraryGalleryAsset.photos)
            + localSavedFrames
                .filter { !photoIdentifiers.contains($0.assetIdentifier) }
                .map(PhotoLibraryGalleryAsset.cached)

        let sorted = combined.sorted { lhs, rhs in
            let lhsDate = galleryDate(for: lhs)
            let rhsDate = galleryDate(for: rhs)
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.assetIdentifier > rhs.assetIdentifier
        }
        galleryAssetsCache = sorted
        return sorted
    }

    private func galleryDate(for asset: PhotoLibraryGalleryAsset) -> Date {
        if let metadataDate = metadataByAssetIdentifier[asset.assetIdentifier]?.capturedAt {
            return metadataDate
        }
        if case .photos(let photoAsset) = asset {
            return photoAsset.creationDate ?? .distantPast
        }
        return .distantPast
    }

    func requestAccessIfNeeded() async -> Bool {
        if isUITesting {
            authorizationStatus = .denied
            addOnlyAuthorizationStatus = .denied
            assets = []
            localSavedFrames = []
            return false
        }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if currentStatus == .notDetermined {
            _ = await requestAuthorization(for: .readWrite)
        }
        refreshAuthorizationStatuses()

        guard PhotoLibraryAuthorizationPolicy.canRead(authorizationStatus) else {
            assets = []
            refreshCachedFrames(excluding: [])
            return false
        }

        refresh()
        return true
    }

    func requestSaveAccessIfNeeded() async -> Bool {
        if isUITesting {
            addOnlyAuthorizationStatus = .denied
            return false
        }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if currentStatus == .notDetermined {
            _ = await requestAuthorization(for: .addOnly)
        }
        refreshAuthorizationStatuses()
        return canSaveToPhotos
    }

    func refresh() {
        if isUITesting {
            authorizationStatus = .denied
            addOnlyAuthorizationStatus = .denied
            assets = []
            localSavedFrames = []
            return
        }

        refreshAuthorizationStatuses()
        guard PhotoLibraryAuthorizationPolicy.canRead(authorizationStatus) else {
            assets = []
            refreshCachedFrames(excluding: [])
            return
        }

        let options = PHFetchOptions()
        options.fetchLimit = 60
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // The album is only an organizational convenience. Never treat every
        // asset in a user-created album with the same title as an app-owned
        // frame; ownership is the persisted local identifier recorded at save.
        assets = Array(fetchSavedAssets(
            options: options,
            reconcileMissing: authorizationStatus == .authorized
        ).prefix(60))
        refreshCachedFrames(excluding: Set(assets.map(\.localIdentifier)))
    }

    func presentLimitedLibraryPicker() {
        guard !isUITesting, authorizationStatus == .limited,
              let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let presenter = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }

        let pickerCompletion: @Sendable ([String]) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(
            from: presenter,
            completionHandler: pickerCompletion
        )
    }

    private func refreshAuthorizationStatuses() {
        let previousReadStatus = authorizationStatus
        let previousAddStatus = addOnlyAuthorizationStatus
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        addOnlyAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorizationStatus != previousReadStatus || addOnlyAuthorizationStatus != previousAddStatus {
            invalidateThumbnailCache()
        }
    }

    func save(
        image: UIImage,
        imageData: Data? = nil,
        recipe: FilmRecipe,
        capturedAt: Date = Date(),
        completion: @escaping @MainActor (Result<Void, PhotoLibrarySaveError>) -> Void
    ) {
        Task { @MainActor in
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            let resolvedStatus: PHAuthorizationStatus
            if status == .notDetermined {
                resolvedStatus = await requestAuthorization(for: .addOnly)
            } else {
                resolvedStatus = status
            }
            addOnlyAuthorizationStatus = resolvedStatus

            guard PhotoLibraryAuthorizationPolicy.canAdd(resolvedStatus) else {
                completion(.failure(.accessDenied))
                return
            }

            // Limited and add-only access cannot create or fetch user albums. The
            // newly created asset is still available to the app under limited access.
            let canManageAppAlbum = PhotoLibraryAuthorizationPolicy.canManageCollections(
                PHPhotoLibrary.authorizationStatus(for: .readWrite)
            )
            let assetIdentifierBox = IdentifierBox()
            let metadata = SavedFrameMetadata(recipe: recipe, capturedAt: capturedAt)
            let cacheData = await Self.cacheData(
                providedData: imageData,
                image: image
            )

            let photoWriteCompletion = PhotoLibraryCompletionBridge.mainActorAsync { [weak self] success in
                guard let self else { return }
                guard success, let assetIdentifier = assetIdentifierBox.get() else {
                    let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                    completion(.failure(PhotoLibrarySaveError.failure(for: currentStatus)))
                    return
                }

                await self.rememberSavedAsset(
                    assetIdentifier,
                    metadata: metadata,
                    imageData: cacheData,
                    image: image
                )
                // The Photos asset and local Roll fallback are durable now.
                // Album organization is optional and can finish after the
                // review is dismissed, so it should not extend save latency.
                self.refresh()
                completion(.success(()))
                guard canManageAppAlbum else {
                    return
                }

                self.addToAppAlbum(assetIdentifier: assetIdentifier) { albumSaved in
                    self.refresh()
                    // The image is already safely in Photos if album organization
                    // fails. Do not report a false save failure or ask the user to
                    // retry and create a duplicate asset.
                    _ = albumSaved
                }
            }

            let photoWriteChanges: @Sendable () -> Void = {
                let request: PHAssetChangeRequest
                if let imageData, !imageData.isEmpty {
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                    request = creationRequest
                } else {
                    request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                request.creationDate = capturedAt
                assetIdentifierBox.set(request.placeholderForCreatedAsset?.localIdentifier)
            }
            PHPhotoLibrary.shared().performChanges(
                photoWriteChanges,
                completionHandler: photoWriteCompletion
            )
        }
    }

    func metadata(for asset: PHAsset) -> SavedFrameMetadata? {
        metadataByAssetIdentifier[asset.localIdentifier]
    }

    func metadata(for asset: PhotoLibraryGalleryAsset) -> SavedFrameMetadata? {
        metadataByAssetIdentifier[asset.assetIdentifier]
    }

    func delete(
        asset: PHAsset,
        completion: @escaping @MainActor (Result<Void, PhotoLibraryServiceError>) -> Void
    ) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard PhotoLibraryAuthorizationPolicy.canRead(status) else {
            completion(.failure(.accessDenied))
            return
        }

        let assetIdentifier = asset.localIdentifier
        guard PhotoLibraryAssetOwnership.contains(assetIdentifier, in: savedAssetIdentifiers) else {
            completion(.failure(.notOwned))
            return
        }
        let photoDeleteCompletion = PhotoLibraryCompletionBridge.mainActor { [weak self] success in
            guard let self else { return }
            guard success else {
                completion(.failure(.changeFailed))
                return
            }

            self.forgetSavedAsset(assetIdentifier)
            self.refresh()
            completion(.success(()))
        }

        // PhotoKit runs change blocks on its own queue. A closure literal formed
        // here would inherit main-actor isolation and trap at runtime, so build an
        // explicitly non-isolated block that only captures Sendable values.
        let photoDeleteChanges: @Sendable () -> Void = {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard assets.count > 0 else { return }
            PHAssetChangeRequest.deleteAssets(assets)
        }
        PHPhotoLibrary.shared().performChanges(
            photoDeleteChanges,
            completionHandler: photoDeleteCompletion
        )
    }

    func delete(
        asset: PhotoLibraryGalleryAsset,
        completion: @escaping @MainActor (Result<Void, PhotoLibraryServiceError>) -> Void
    ) {
        guard case .photos(let photoAsset) = asset else {
            completion(.failure(.accessDenied))
            return
        }
        delete(asset: photoAsset, completion: completion)
    }

    private func appAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", albumTitle)
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        ).firstObject
    }

    private var savedAssetIdentifiers: [String] {
        get {
            PhotoLibraryAssetOwnership.normalized(
                UserDefaults.standard.stringArray(forKey: savedAssetIdentifiersKey) ?? [],
                limit: 120
            )
        }
        set {
            UserDefaults.standard.set(
                PhotoLibraryAssetOwnership.normalized(newValue, limit: 120),
                forKey: savedAssetIdentifiersKey
            )
        }
    }

    /// The persisted local-copy index. Readable from any thread so background
    /// maintenance can consult the current index rather than a snapshot.
    private nonisolated static func loadSavedFrameResources(
        defaults: UserDefaults = .standard
    ) -> [String: SavedFrameResource] {
        guard let data = defaults.data(forKey: savedFrameResourcesKey),
              let resources = try? JSONDecoder().decode([String: SavedFrameResource].self, from: data) else {
            return [:]
        }
        return resources
    }

    private var savedFrameResources: [String: SavedFrameResource] {
        get {
            if let savedFrameResourcesCache { return savedFrameResourcesCache }
            let resources = Self.loadSavedFrameResources()
            savedFrameResourcesCache = resources
            return resources
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            // Every app write goes through this main-actor setter. Row/image
            // lookups reuse the decoded index; background maintenance keeps
            // using loadSavedFrameResources() for a fresh persisted snapshot.
            savedFrameResourcesCache = newValue
            UserDefaults.standard.set(data, forKey: savedFrameResourcesKey)
        }
    }

    private func rememberSavedAsset(
        _ identifier: String,
        metadata: SavedFrameMetadata,
        imageData: Data?,
        image: UIImage
    ) async {
        savedAssetIdentifiers = PhotoLibraryAssetOwnership.adding(
            identifier,
            to: savedAssetIdentifiers,
            limit: 120
        )
        metadataByAssetIdentifier[identifier] = metadata
        let retainedIdentifiers = Set(savedAssetIdentifiers)
        metadataByAssetIdentifier = metadataByAssetIdentifier.filter { retainedIdentifiers.contains($0.key) }
        persistMetadata()
        pruneResources(keeping: savedAssetIdentifiers)
        await cacheFrame(
            identifier: identifier,
            imageData: imageData,
            fallbackImage: image
        )
    }

    private func forgetSavedAsset(_ identifier: String) {
        savedAssetIdentifiers = PhotoLibraryAssetOwnership.removing(
            identifier,
            from: savedAssetIdentifiers
        )
        metadataByAssetIdentifier.removeValue(forKey: identifier)
        persistMetadata()
        removeCachedFrame(identifier: identifier)
    }

    private func fetchSavedAssets(
        options: PHFetchOptions,
        reconcileMissing: Bool
    ) -> [PHAsset] {
        let identifiers = savedAssetIdentifiers
        guard !identifiers.isEmpty else { return [] }

        // Reconcile only with full read access. In limited mode, an asset the
        // user did not select is intentionally invisible to PhotoKit; pruning
        // it here would destroy its recipe metadata and local Roll fallback.
        let reconciliationOptions = PHFetchOptions()
        reconciliationOptions.predicate = options.predicate
        reconciliationOptions.sortDescriptors = options.sortDescriptors
        reconciliationOptions.fetchLimit = 0
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: reconciliationOptions
        )
        let fetched = result.objects(at: IndexSet(integersIn: 0..<result.count))
        let assetsByIdentifier = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        let accessibleIdentifiers = identifiers.filter { assetsByIdentifier[$0] != nil }
        if reconcileMissing && accessibleIdentifiers != identifiers {
            savedAssetIdentifiers = accessibleIdentifiers
            pruneMetadata(keeping: accessibleIdentifiers)
            pruneResources(keeping: accessibleIdentifiers)
        }
        return accessibleIdentifiers.compactMap { assetsByIdentifier[$0] }
    }

    private func persistMetadata() {
        guard let data = try? JSONEncoder().encode(metadataByAssetIdentifier) else { return }
        UserDefaults.standard.set(data, forKey: savedFrameMetadataKey)
    }

    private func pruneMetadata(keeping identifiers: [String]) {
        let allowed = Set(identifiers)
        let pruned = metadataByAssetIdentifier.filter { allowed.contains($0.key) }
        guard pruned.count != metadataByAssetIdentifier.count else { return }
        metadataByAssetIdentifier = pruned
        persistMetadata()
    }

    private func pruneResources(keeping identifiers: [String]) {
        let allowed = Set(identifiers)
        var resources = savedFrameResources
        let removed = resources.keys.filter { !allowed.contains($0) }
        guard !removed.isEmpty else { return }

        for identifier in removed {
            if let resource = resources.removeValue(forKey: identifier) {
                if let resourceURL = localFrameURL(for: resource.filename) {
                    try? FileManager.default.removeItem(at: resourceURL)
                }
            }
        }
        savedFrameResources = resources
    }

    private func refreshCachedFrames(excluding excludedIdentifiers: Set<String>) {
        let resources = savedFrameResources
        let regularFiles = localFramesDirectoryURL.flatMap {
            PhotoLibraryCachePath.regularFileURLs(in: $0)
        }
        let regularFilenames = Set(regularFiles?.map(\.lastPathComponent) ?? [])
        localSavedFrames = savedAssetIdentifiers.compactMap { identifier in
            guard !excludedIdentifiers.contains(identifier),
                  let resource = resources[identifier],
                  let resourceURL = localFrameURL(for: resource.filename),
                  (regularFilenames.contains(resource.filename)
                   || FileManager.default.fileExists(atPath: resourceURL.path)) else {
                return nil
            }
            return LocalSavedFrame(
                assetIdentifier: identifier,
                pixelWidth: resource.pixelWidth,
                pixelHeight: resource.pixelHeight
            )
        }
        if let directoryURL = localFramesDirectoryURL {
            if let regularFiles {
                hasLocalCache = !regularFiles.isEmpty
            } else {
                hasLocalCache = FileManager.default.fileExists(atPath: directoryURL.path)
            }
        } else {
            hasLocalCache = false
        }
    }

    private func cacheFrame(identifier: String, imageData: Data?, fallbackImage: UIImage) async {
        guard let data = imageData, !data.isEmpty,
              let directoryURL = localFramesDirectoryURL else {
            return
        }

        let filename = "\(UUID().uuidString).jpg"
        guard let resourceURL = localFrameURL(for: filename) else { return }
        let dimensions = Self.pixelDimensions(in: data, fallbackImage: fallbackImage)
        let generation = cacheWriteGeneration

        let didWrite = await Self.persistCachedFrameData(
            data,
            directoryURL: directoryURL,
            resourceURL: resourceURL
        )
        guard didWrite else { return }
        guard cacheWriteGeneration == generation else {
            try? FileManager.default.removeItem(at: resourceURL)
            return
        }
        guard PhotoLibraryAssetOwnership.contains(identifier, in: savedAssetIdentifiers) else {
            try? FileManager.default.removeItem(at: resourceURL)
            return
        }
        var resources = savedFrameResources
        if let previousResource = resources[identifier], previousResource.filename != filename {
            if let previousResourceURL = localFrameURL(for: previousResource.filename) {
                try? FileManager.default.removeItem(at: previousResourceURL)
            }
        }
        resources[identifier] = SavedFrameResource(
            filename: filename,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        )
        savedFrameResources = resources
        scheduleCacheMaintenance(includingLaunchPasses: false)
    }

    /// Performs all cache filesystem work off the main actor and returns only
    /// after the atomic JPEG write and file-protection metadata are complete.
    nonisolated static func persistCachedFrameData(
        _ data: Data,
        directoryURL: URL,
        resourceURL: URL
    ) async -> Bool {
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
                Self.protectLocalResource(at: directoryURL)
                try data.write(to: resourceURL, options: .atomic)
                Self.protectLocalResource(at: resourceURL)
                return true
            } catch {
                return false
            }
        }.value
    }

    /// JPEG fallback encoding can be expensive for a large imported frame.
    /// Keep it off the main actor while preserving the caller-provided output
    /// bytes whenever the renderer already produced them.
    private nonisolated static func cacheData(
        providedData: Data?,
        image: UIImage
    ) async -> Data? {
        if let providedData, !providedData.isEmpty {
            return providedData
        }

        let imageBox = ImageBox(image)
        return await Task.detached(priority: .utility) {
            imageBox.image.jpegData(compressionQuality: 0.95)
        }.value
    }

    /// Reads encoded dimensions from ImageIO without decoding the full JPEG.
    /// The UIImage passed by the review flow is deliberately downsampled, so it
    /// is only a fallback when encoded metadata is unavailable.
    nonisolated static func pixelDimensions(
        in data: Data,
        fallbackImage: UIImage
    ) -> PhotoPixelDimensions {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
           let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
           width > 0, height > 0 {
            return PhotoPixelDimensions(width: width, height: height)
        }

        return PhotoPixelDimensions(
            width: fallbackImage.cgImage?.width
                ?? max(Int(fallbackImage.size.width * fallbackImage.scale), 1),
            height: fallbackImage.cgImage?.height
                ?? max(Int(fallbackImage.size.height * fallbackImage.scale), 1)
        )
    }

    private func removeCachedFrame(identifier: String) {
        invalidateThumbnailCache()
        var resources = savedFrameResources
        guard let resource = resources.removeValue(forKey: identifier) else { return }
        if let resourceURL = localFrameURL(for: resource.filename) {
            try? FileManager.default.removeItem(at: resourceURL)
        }
        savedFrameResources = resources
        refreshCachedFrames(excluding: Set(assets.map(\.localIdentifier)))
    }

    private var localFramesDirectoryURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(localFramesDirectoryName, isDirectory: true)
    }

    private var legacyLocalFramesDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(localFramesDirectoryName, isDirectory: true)
    }

    private func localFrameURL(for filename: String) -> URL? {
        guard let directoryURL = localFramesDirectoryURL else { return nil }
        return PhotoLibraryCachePath.fileURL(filename: filename, in: directoryURL)
    }

    /// Files younger than this are never treated as orphans: a save that is
    /// writing its JPEG right now has not indexed it yet.
    private nonisolated static let reconcileMinimumFileAge: TimeInterval = 120

    private nonisolated static func reconcileLocalCache(in directoryURL: URL?) {
        guard let directoryURL,
              let regularFiles = PhotoLibraryCachePath.regularFileURLs(in: directoryURL) else {
            return
        }
        // Consult the index as it is now, not the snapshot taken when the
        // pass was scheduled, so a frame saved since launch is preserved.
        let indexedFilenames = Set(
            loadSavedFrameResources().values.compactMap {
                PhotoLibraryCachePath.fileURL(filename: $0.filename, in: directoryURL)?.lastPathComponent
            }
        )
        let cutoff = Date().addingTimeInterval(-reconcileMinimumFileAge)
        // Remove only files that are both unindexed and old enough that no
        // in-progress save can own them. Photos remains the source of truth;
        // indexed local copies are retained for offline use.
        for fileURL in regularFiles where !indexedFilenames.contains(fileURL.lastPathComponent) {
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private nonisolated static func migrateLocalFrameCache(from legacyURL: URL?, to currentURL: URL?) {
        guard let legacyURL,
              let currentURL,
              legacyURL != currentURL,
              FileManager.default.fileExists(atPath: legacyURL.path) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: currentURL,
                withIntermediateDirectories: true
            )
            let files = try FileManager.default.contentsOfDirectory(
                at: legacyURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for fileURL in files {
                let destination = currentURL.appendingPathComponent(fileURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.moveItem(at: fileURL, to: destination)
                }
                protectLocalResource(at: destination)
            }
            try? FileManager.default.removeItem(at: legacyURL)
            protectLocalResource(at: currentURL)
        } catch {
            // A cache migration is best effort. Photos remains the source of
            // truth and the new cache can be rebuilt on the next save.
        }
    }

    private func protectLocalResource(at url: URL) {
        Self.protectLocalResource(at: url)
    }

    private nonisolated static func protectLocalResource(at url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    /// Evicts the oldest local copies beyond the byte budget and reports the
    /// identifiers whose local copy is gone (evicted, missing, or empty).
    private nonisolated static func trimLocalCache(
        in directoryURL: URL?,
        savedAssetIdentifiers: [String],
        resources: [String: SavedFrameResource],
        maxBytes: Int
    ) -> Set<String> {
        var totalBytes = 0
        var removed = Set<String>()

        if let directoryURL,
           FileManager.default.fileExists(atPath: directoryURL.path) {
            protectLocalResource(at: directoryURL)
        }

        // savedAssetIdentifiers is newest-first, so evict the oldest local
        // copies first while retaining the Photos originals.
        for identifier in savedAssetIdentifiers {
            guard let resource = resources[identifier] else { continue }
            guard let directoryURL,
                  let url = PhotoLibraryCachePath.fileURL(filename: resource.filename, in: directoryURL) else {
                removed.insert(identifier)
                continue
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            guard byteCount > 0 else {
                removed.insert(identifier)
                continue
            }

            if totalBytes + byteCount > maxBytes {
                do {
                    try FileManager.default.removeItem(at: url)
                    removed.insert(identifier)
                } catch {
                    // Keep the mapping so a later pass can retry the eviction.
                    totalBytes += byteCount
                }
            } else {
                protectLocalResource(at: url)
                totalBytes += byteCount
            }
        }
        return removed
    }

    /// Removes only Filmy Camera's on-device cached copies, including orphaned
    /// regular files. Photos originals and their saved ownership metadata are
    /// never deleted. Failed file deletions retain their cache mappings so a
    /// later clear can retry them.
    func clearLocalRollCache() {
        // Invalidate writes already running off the main actor so they cannot
        // recreate a cache entry after the user clears it.
        cacheWriteGeneration &+= 1
        invalidateThumbnailCache()

        guard let directoryURL = localFramesDirectoryURL else {
            savedFrameResources = [:]
            refreshCachedFrames(excluding: Set(assets.map(\.localIdentifier)))
            return
        }

        guard let result = PhotoLibraryCachePath.removeRegularFiles(in: directoryURL) else {
            // Keep the index if the directory cannot be read so a later clear
            // can retry the files that may still be present.
            refreshCachedFrames(excluding: Set(assets.map(\.localIdentifier)))
            return
        }

        var resources = savedFrameResources
        for (identifier, resource) in resources {
            guard let resourceURL = localFrameURL(for: resource.filename) else {
                resources.removeValue(forKey: identifier)
                continue
            }

            let filename = resourceURL.lastPathComponent
            if result.removedFilenames.contains(filename)
                || !FileManager.default.fileExists(atPath: resourceURL.path) {
                resources.removeValue(forKey: identifier)
            }
        }
        savedFrameResources = resources
        refreshCachedFrames(excluding: Set(assets.map(\.localIdentifier)))
    }

    func removeTemporaryShare(at url: URL) {
        guard let directoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(shareDirectoryName, isDirectory: true) else {
            return
        }

        let directoryPath = directoryURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(directoryPath + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func shareURL(for asset: PhotoLibraryGalleryAsset) async -> URL? {
        switch asset {
        case .cached(let frame):
            guard PhotoLibraryAssetOwnership.contains(
                frame.assetIdentifier,
                in: savedAssetIdentifiers
            ),
            let filename = savedFrameResources[frame.assetIdentifier]?.filename,
            let url = localFrameURL(for: filename) else { return nil }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil

        case .photos(let photoAsset):
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            let resources = PHAssetResource.assetResources(for: photoAsset)
            guard PhotoLibraryAuthorizationPolicy.canRead(status),
                  savedAssetIdentifiers.contains(photoAsset.localIdentifier),
                  let resource = resources.first(where: { $0.type == .photo }) ?? resources.first,
                  let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return nil
            }

            let directoryURL = cachesURL.appendingPathComponent(shareDirectoryName, isDirectory: true)
            let destinationURL = directoryURL.appendingPathComponent(
                "\(UUID().uuidString).jpg",
                isDirectory: false
            )
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                protectLocalResource(at: directoryURL)
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                let manager = PHAssetResourceManager.default()
                return await withCheckedContinuation { continuation in
                    let writeCompletion: @Sendable (Error?) -> Void = { [weak self] error in
                        Task { @MainActor in
                            guard error == nil else {
                                try? FileManager.default.removeItem(at: destinationURL)
                                continuation.resume(returning: nil)
                                return
                            }
                            self?.protectLocalResource(at: destinationURL)
                            continuation.resume(returning: destinationURL)
                        }
                    }
                    manager.writeData(
                        for: resource,
                        toFile: destinationURL,
                        options: options,
                        completionHandler: writeCompletion
                    )
                }
            } catch {
                return nil
            }
        }
    }

    private var temporaryShareDirectoryURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(shareDirectoryName, isDirectory: true)
    }

    private nonisolated static func pruneTemporaryShareFiles(in directoryURL: URL?) {
        guard let directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }
        // A share prepared since launch may be writing into this directory
        // right now; only files that predate this pass by a safe margin are
        // leftovers from an earlier session.
        let cutoff = Date().addingTimeInterval(-reconcileMinimumFileAge)

        protectLocalResource(at: directoryURL)

        for fileURL in files {
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func loadMetadata(forKey key: String) -> [String: SavedFrameMetadata] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let metadata = try? JSONDecoder().decode([String: SavedFrameMetadata].self, from: data) else {
            return [:]
        }
        return metadata
    }

    private func addToAppAlbum(
        assetIdentifier: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let album = appAlbum() else {
            let albumIdentifierBox = IdentifierBox()
            let albumTitle = self.albumTitle
            let albumCreationCompletion = PhotoLibraryCompletionBridge.mainActor { [weak self] success in
                guard let self else { return }
                guard success,
                      let albumIdentifier = albumIdentifierBox.get(),
                      let createdAlbum = PHAssetCollection.fetchAssetCollections(
                          withLocalIdentifiers: [albumIdentifier],
                          options: nil
                      ).firstObject else {
                    completion(false)
                    return
                }
                self.addAsset(assetIdentifier, to: createdAlbum, completion: completion)
            }

            let albumCreationChanges: @Sendable () -> Void = {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                albumIdentifierBox.set(request.placeholderForCreatedAssetCollection.localIdentifier)
            }
            PHPhotoLibrary.shared().performChanges(
                albumCreationChanges,
                completionHandler: albumCreationCompletion
            )
            return
        }

        addAsset(assetIdentifier, to: album, completion: completion)
    }

    private func addAsset(
        _ assetIdentifier: String,
        to album: PHAssetCollection,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject != nil else {
            completion(false)
            return
        }

        let albumIdentifier = album.localIdentifier
        let albumAddCompletion = PhotoLibraryCompletionBridge.mainActor(completion)
        // Re-fetch inside the change block so the block captures only
        // identifiers and stays free of main-actor isolation.
        let albumAddChanges: @Sendable () -> Void = {
            guard let album = PHAssetCollection.fetchAssetCollections(
                      withLocalIdentifiers: [albumIdentifier],
                      options: nil
                  ).firstObject else {
                return
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard assets.count > 0 else { return }
            PHAssetCollectionChangeRequest(for: album)?.addAssets(assets)
        }
        PHPhotoLibrary.shared().performChanges(
            albumAddChanges,
            completionHandler: albumAddCompletion
        )
    }

    func image(
        for asset: PhotoLibraryGalleryAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> UIImage? {
        switch asset {
        case .photos(let photoAsset):
            return await image(
                for: photoAsset,
                targetSize: targetSize,
                contentMode: contentMode
            )
        case .cached(let frame):
            guard let resource = savedFrameResources[frame.assetIdentifier],
                  PhotoLibraryAssetOwnership.contains(frame.assetIdentifier, in: savedAssetIdentifiers),
                  let resourceURL = localFrameURL(for: resource.filename) else {
                return nil
            }
            let cacheKey = PhotoLibraryThumbnailCachePolicy.key(
                assetIdentifier: frame.assetIdentifier,
                targetSize: targetSize,
                contentMode: contentMode,
                authorizationStatus: nil,
                revision: resource.filename
            )
            let nsCacheKey = cacheKey.map { $0 as NSString }
            if let nsCacheKey, let cached = thumbnailCache.object(forKey: nsCacheKey) {
                return cached
            }
            let cacheGeneration = thumbnailCacheGeneration
            let loaded = await Task.detached(priority: .utility) {
                CachedThumbnail(
                    image: Self.cachedImage(at: resourceURL, targetSize: targetSize)
                )
            }.value.image
            guard !Task.isCancelled else { return loaded }
            if cacheGeneration == thumbnailCacheGeneration {
                storeThumbnail(loaded, forKey: nsCacheKey)
            }
            return loaded
        }
    }

    func image(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> UIImage? {
        let revision = "\(asset.pixelWidth)x\(asset.pixelHeight)|\(asset.modificationDate?.timeIntervalSinceReferenceDate ?? -1)"
        let cacheKey = PhotoLibraryThumbnailCachePolicy.key(
            assetIdentifier: asset.localIdentifier,
            targetSize: targetSize,
            contentMode: contentMode,
            authorizationStatus: authorizationStatus,
            revision: revision
        )
        let nsCacheKey = cacheKey.map { $0 as NSString }
        if let nsCacheKey, let cached = thumbnailCache.object(forKey: nsCacheKey) {
            return cached
        }

        let imageManager = PHImageManager.default()
        let state = ImageRequestState(imageManager: imageManager)
        let cacheGeneration = thumbnailCacheGeneration

        let loaded = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: contentMode,
                    options: options
                ) { image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let hasError = info?[PHImageErrorKey] != nil

                    // Photos may deliver a usable preview before the final
                    // high-quality result. Keep it as a fallback so an iCloud
                    // fetch failure does not leave the viewer empty.
                    if isDegraded && !isCancelled && !hasError {
                        state.rememberFallback(image)
                        return
                    }

                    state.finish(
                        with: isCancelled || hasError ? nil : image,
                        allowFallback: !isCancelled,
                        cacheable: !isDegraded && !isCancelled && !hasError && image != nil
                    )
                }
                state.install(requestID: requestID)
            }
        }, onCancel: {
            state.cancel()
        })
        if !Task.isCancelled,
           cacheGeneration == thumbnailCacheGeneration,
           state.canCacheResult() {
            storeThumbnail(loaded, forKey: nsCacheKey)
        }
        return loaded
    }

    private func storeThumbnail(
        _ image: UIImage?,
        forKey key: NSString?
    ) {
        guard let image, let key else {
            return
        }
        let width = max(Int((image.size.width * image.scale).rounded(.up)), 1)
        let height = max(Int((image.size.height * image.scale).rounded(.up)), 1)
        let byteCount: Int64
        if let cgImage = image.cgImage {
            let result = Int64(cgImage.bytesPerRow).multipliedReportingOverflow(
                by: Int64(cgImage.height)
            )
            guard !result.overflow, result.partialValue > 0 else { return }
            byteCount = result.partialValue
        } else {
            let rowBytes = Int64(width).multipliedReportingOverflow(by: 4)
            guard !rowBytes.overflow else { return }
            let result = rowBytes.partialValue.multipliedReportingOverflow(by: Int64(height))
            guard !result.overflow, result.partialValue > 0 else { return }
            byteCount = result.partialValue
        }

        let maximumCost = Int64(48 * 1024 * 1024)
        guard byteCount <= maximumCost else { return }
        thumbnailCache.setObject(image, forKey: key, cost: Int(byteCount))
    }

    nonisolated static func thumbnailMaxPixelSize(for targetSize: CGSize) -> Int {
        let width = targetSize.width.isFinite && targetSize.width > 0
            ? targetSize.width
            : 0
        let height = targetSize.height.isFinite && targetSize.height > 0
            ? targetSize.height
            : 0
        let maximumDimension = max(width, height)
        guard maximumDimension > 0 else { return 1 }
        return Int(min(max(maximumDimension.rounded(.up), 1), 8_192))
    }

    private nonisolated static func cachedImage(at resourceURL: URL, targetSize: CGSize) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(
            resourceURL as CFURL,
            sourceOptions as CFDictionary
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize(for: targetSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            // The handler arrives on an arbitrary PhotoKit queue; keep it
            // explicitly non-isolated so it never trips the main-actor check.
            let handler: @Sendable (PHAuthorizationStatus) -> Void = { status in
                continuation.resume(returning: status)
            }
            PHPhotoLibrary.requestAuthorization(for: accessLevel, handler: handler)
        }
    }
}

extension PhotoLibraryService: PhotoSaving {}
