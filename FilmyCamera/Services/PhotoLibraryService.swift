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

    private final class ImageRequestState: @unchecked Sendable {
        private let lock = NSLock()
        private let imageManager: PHImageManager
        private var requestID: PHImageRequestID?
        private var continuation: CheckedContinuation<UIImage?, Never>?
        private var didFinish = false

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

        func finish(with image: UIImage?, cancelRequest: Bool = false) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            let continuation = self.continuation
            self.continuation = nil
            let requestID = self.requestID
            self.requestID = nil
            lock.unlock()

            if cancelRequest, let requestID {
                imageManager.cancelImageRequest(requestID)
            }
            continuation?.resume(returning: image)
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

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var localSavedFrames: [LocalSavedFrame] = []
    @Published private(set) var hasLocalCache = false
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var addOnlyAuthorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false

    private let albumTitle = "Filmy Camera"
    private let savedAssetIdentifiersKey = "filmyCamera.savedAssetIdentifiers"
    private let savedFrameMetadataKey = "filmyCamera.savedFrameMetadata"
    private let savedFrameResourcesKey = "filmyCamera.savedFrameResources"
    private let localFramesDirectoryName = "FilmyCameraFrames"
    private let shareDirectoryName = "FilmyCameraShare"
    private let localCacheMaxBytes = 250 * 1024 * 1024
    private let isUITesting: Bool

    private(set) var metadataByAssetIdentifier: [String: SavedFrameMetadata]

    init() {
        isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        metadataByAssetIdentifier = Self.loadMetadata(forKey: savedFrameMetadataKey)
        if isUITesting {
            authorizationStatus = .denied
            addOnlyAuthorizationStatus = .denied
        } else {
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            addOnlyAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            migrateLocalFrameCacheIfNeeded()
            reconcileLocalCache()
            trimLocalCacheToBudget()
            pruneTemporaryShareFiles()
            refreshCachedFrames(excluding: [])
        }
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
        let photoIdentifiers = Set(assets.map(\.localIdentifier))
        let combined = assets.map(PhotoLibraryGalleryAsset.photos)
            + localSavedFrames
                .filter { !photoIdentifiers.contains($0.assetIdentifier) }
                .map(PhotoLibraryGalleryAsset.cached)

        return combined.sorted { lhs, rhs in
            let lhsDate = galleryDate(for: lhs)
            let rhsDate = galleryDate(for: rhs)
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.assetIdentifier > rhs.assetIdentifier
        }
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

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refreshAuthorizationStatuses() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        addOnlyAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    func save(
        image: UIImage,
        imageData: Data? = nil,
        recipe: FilmRecipe,
        capturedAt: Date = Date(),
        completion: @escaping @MainActor (Bool) -> Void
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
                completion(false)
                return
            }

            // Limited and add-only access cannot create or fetch user albums. The
            // newly created asset is still available to the app under limited access.
            let canManageAppAlbum = PhotoLibraryAuthorizationPolicy.canManageCollections(
                PHPhotoLibrary.authorizationStatus(for: .readWrite)
            )
            let assetIdentifierBox = IdentifierBox()
            let metadata = SavedFrameMetadata(recipe: recipe, capturedAt: capturedAt)
            let cacheData = imageData.flatMap { $0.isEmpty ? nil : $0 }
                ?? image.jpegData(compressionQuality: 0.95)

            let photoWriteCompletion = PhotoLibraryCompletionBridge.mainActor { [weak self] success in
                guard let self else { return }
                guard success, let assetIdentifier = assetIdentifierBox.get() else {
                    completion(false)
                    return
                }

                self.rememberSavedAsset(
                    assetIdentifier,
                    metadata: metadata,
                    imageData: cacheData,
                    image: image
                )
                guard canManageAppAlbum else {
                    self.refresh()
                    completion(true)
                    return
                }

                self.addToAppAlbum(assetIdentifier: assetIdentifier) { albumSaved in
                    self.refresh()
                    // The image is already safely in Photos if album organization
                    // fails. Do not report a false save failure or ask the user to
                    // retry and create a duplicate asset.
                    _ = albumSaved
                    completion(true)
                }
            }

            PHPhotoLibrary.shared().performChanges({
                let request: PHAssetChangeRequest
                if let imageData, !imageData.isEmpty {
                    let creationRequest = PHAssetCreationRequest()
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                    request = creationRequest
                } else {
                    request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                request.creationDate = capturedAt
                assetIdentifierBox.set(request.placeholderForCreatedAsset?.localIdentifier)
            }, completionHandler: photoWriteCompletion)
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

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }, completionHandler: photoDeleteCompletion)
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

    private var savedFrameResources: [String: SavedFrameResource] {
        get {
            guard let data = UserDefaults.standard.data(forKey: savedFrameResourcesKey),
                  let resources = try? JSONDecoder().decode([String: SavedFrameResource].self, from: data) else {
                return [:]
            }
            return resources
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: savedFrameResourcesKey)
        }
    }

    private func rememberSavedAsset(
        _ identifier: String,
        metadata: SavedFrameMetadata,
        imageData: Data?,
        image: UIImage
    ) {
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
        cacheFrame(
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
        let regularFilenames: Set<String>
        if let directoryURL = localFramesDirectoryURL,
           let regularFiles = PhotoLibraryCachePath.regularFileURLs(in: directoryURL) {
            regularFilenames = Set(regularFiles.map(\.lastPathComponent))
        } else {
            regularFilenames = []
        }
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
            if let regularFiles = PhotoLibraryCachePath.regularFileURLs(in: directoryURL) {
                hasLocalCache = !regularFiles.isEmpty
            } else {
                hasLocalCache = FileManager.default.fileExists(atPath: directoryURL.path)
            }
        } else {
            hasLocalCache = false
        }
    }

    private func cacheFrame(identifier: String, imageData: Data?, fallbackImage: UIImage) {
        guard let data = imageData, !data.isEmpty,
              let directoryURL = localFramesDirectoryURL else {
            return
        }

        let filename = "\(UUID().uuidString).jpg"
        guard let resourceURL = localFrameURL(for: filename) else { return }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            protectLocalResource(at: directoryURL)
            try data.write(to: resourceURL, options: .atomic)
            protectLocalResource(at: resourceURL)

            var resources = savedFrameResources
            if let previousResource = resources[identifier], previousResource.filename != filename {
                if let previousResourceURL = localFrameURL(for: previousResource.filename) {
                    try? FileManager.default.removeItem(at: previousResourceURL)
                }
            }
            let pixelWidth = fallbackImage.cgImage?.width ?? max(Int(fallbackImage.size.width * fallbackImage.scale), 1)
            let pixelHeight = fallbackImage.cgImage?.height ?? max(Int(fallbackImage.size.height * fallbackImage.scale), 1)
            resources[identifier] = SavedFrameResource(
                filename: filename,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
            savedFrameResources = resources
            trimLocalCacheToBudget()
        } catch {
            // The Photos write remains the source-of-truth save operation. A
            // cache failure must not make the user retry and create a duplicate.
        }
    }

    private func removeCachedFrame(identifier: String) {
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

    private func reconcileLocalCache() {
        guard let directoryURL = localFramesDirectoryURL else { return }
        let indexedFilenames = Set(
            savedFrameResources.values.compactMap { localFrameURL(for: $0.filename)?.lastPathComponent }
        )
        // Reconcile every regular file in the cache directory, including files
        // left behind before their resource index was persisted. Photos remains
        // the source of truth; indexed local copies are retained for offline use.
        _ = PhotoLibraryCachePath.removeRegularFiles(
            in: directoryURL,
            preservingFilenames: indexedFilenames
        )
    }

    private func migrateLocalFrameCacheIfNeeded() {
        guard let legacyURL = legacyLocalFramesDirectoryURL,
              let currentURL = localFramesDirectoryURL,
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
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func trimLocalCacheToBudget() {
        var resources = savedFrameResources
        var totalBytes = 0
        var didRemoveResource = false

        if let directoryURL = localFramesDirectoryURL,
           FileManager.default.fileExists(atPath: directoryURL.path) {
            protectLocalResource(at: directoryURL)
        }

        // savedAssetIdentifiers is newest-first, so evict the oldest local
        // copies first while retaining the Photos originals.
        for identifier in savedAssetIdentifiers {
            guard let resource = resources[identifier] else { continue }
            guard let url = localFrameURL(for: resource.filename) else {
                resources.removeValue(forKey: identifier)
                didRemoveResource = true
                continue
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            guard byteCount > 0 else {
                resources.removeValue(forKey: identifier)
                didRemoveResource = true
                continue
            }

            if totalBytes + byteCount > localCacheMaxBytes {
                do {
                    try FileManager.default.removeItem(at: url)
                    resources.removeValue(forKey: identifier)
                    didRemoveResource = true
                } catch {
                    // Keep the mapping so startup can retry a failed eviction.
                    totalBytes += byteCount
                }
            } else {
                protectLocalResource(at: url)
                totalBytes += byteCount
            }
        }

        if didRemoveResource {
            savedFrameResources = resources
        }
        refreshCachedFrames(excluding: Set(assets.map(\.localIdentifier)))
    }

    /// Removes only Filmy Camera's on-device cached copies, including orphaned
    /// regular files. Photos originals and their saved ownership metadata are
    /// never deleted. Failed file deletions retain their cache mappings so a
    /// later clear can retry them.
    func clearLocalRollCache() {
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
                    manager.writeData(for: resource, toFile: destinationURL, options: options) { [weak self] error in
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
                }
            } catch {
                return nil
            }
        }
    }

    private func pruneTemporaryShareFiles() {
        guard let directoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(shareDirectoryName, isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }

        protectLocalResource(at: directoryURL)

        for fileURL in files {
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

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                albumIdentifierBox.set(request.placeholderForCreatedAssetCollection.localIdentifier)
            }, completionHandler: albumCreationCompletion)
            return
        }

        addAsset(assetIdentifier, to: album, completion: completion)
    }

    private func addAsset(
        _ assetIdentifier: String,
        to album: PHAssetCollection,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject else {
            completion(false)
            return
        }

        let albumAddCompletion = PhotoLibraryCompletionBridge.mainActor(completion)
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
        }, completionHandler: albumAddCompletion)
    }

    func image(for asset: PhotoLibraryGalleryAsset, targetSize: CGSize) async -> UIImage? {
        switch asset {
        case .photos(let photoAsset):
            return await image(for: photoAsset, targetSize: targetSize)
        case .cached(let frame):
            guard let resource = savedFrameResources[frame.assetIdentifier],
                  PhotoLibraryAssetOwnership.contains(frame.assetIdentifier, in: savedAssetIdentifiers),
                  let resourceURL = localFrameURL(for: resource.filename) else {
                return nil
            }
            return await Task.detached(priority: .utility) {
                CachedThumbnail(
                    image: Self.cachedImage(at: resourceURL, targetSize: targetSize)
                )
            }.value.image
        }
    }

    func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let imageManager = PHImageManager.default()
        let state = ImageRequestState(imageManager: imageManager)

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                ) { image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let hasError = info?[PHImageErrorKey] != nil

                    // Photos may deliver a fast degraded image before the final
                    // high-quality result. Resume exactly once, and surface
                    // cancellation/iCloud failures as a nil image.
                    guard !isDegraded || isCancelled || hasError else { return }

                    state.finish(with: isCancelled || hasError ? nil : image)
                }
                state.install(requestID: requestID)
            }
        }, onCancel: {
            state.cancel()
        })
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
            PHPhotoLibrary.requestAuthorization(for: accessLevel) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
