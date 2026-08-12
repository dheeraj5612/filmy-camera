import Combine
@preconcurrency import Photos
import UIKit

struct SavedFrameMetadata: Codable, Hashable, Sendable {
    let recipe: FilmRecipe
    let capturedAt: Date
}

enum PhotoLibraryServiceError: LocalizedError, Sendable {
    case accessDenied
    case changeFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photos access is needed to manage this frame. Enable it in Settings, then try again."
        case .changeFailed:
            return "Photos could not update this frame. Try again in a moment."
        }
    }
}

@MainActor
final class PhotoLibraryService: ObservableObject {
    private final class IdentifierBox: @unchecked Sendable {
        var value: String?
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

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false

    private let albumTitle = "Filmy Camera"
    private let savedAssetIdentifiersKey = "filmyCamera.savedAssetIdentifiers"
    private let savedFrameMetadataKey = "filmyCamera.savedFrameMetadata"
    private let isUITesting: Bool

    private(set) var metadataByAssetIdentifier: [String: SavedFrameMetadata]

    init() {
        isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        metadataByAssetIdentifier = Self.loadMetadata(forKey: savedFrameMetadataKey)
        authorizationStatus = isUITesting
            ? .denied
            : PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccessIfNeeded() async -> Bool {
        if isUITesting {
            authorizationStatus = .denied
            assets = []
            return false
        }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if currentStatus == .notDetermined {
            authorizationStatus = await requestAuthorization(for: .readWrite)
        } else {
            authorizationStatus = currentStatus
        }

        if authorizationStatus == .authorized || authorizationStatus == .limited {
            refresh()
            return true
        }
        return false
    }

    func refresh() {
        if isUITesting {
            authorizationStatus = .denied
            assets = []
            return
        }

        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            return
        }

        let options = PHFetchOptions()
        options.fetchLimit = 60
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if authorizationStatus == .authorized, let album = appAlbum() {
            let result = PHAsset.fetchAssets(in: album, options: options)
            let albumAssets = result.objects(at: IndexSet(integersIn: 0..<result.count))
            let knownAssets = fetchSavedAssets(options: options)
            let albumIdentifiers = Set(albumAssets.map(\.localIdentifier))
            assets = Array((albumAssets + knownAssets.filter { !albumIdentifiers.contains($0.localIdentifier) }).prefix(60))
        } else {
            assets = Array(fetchSavedAssets(options: options).prefix(60))
        }
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
            let canSave: Bool

            if status == .notDetermined {
                canSave = await requestAuthorization(for: .addOnly) == .authorized
            } else {
                canSave = status == .authorized || status == .limited
            }

            guard canSave else {
                completion(false)
                return
            }

            // Limited and add-only access cannot create or fetch user albums. The
            // newly created asset is still available to the app under limited access.
            let canManageAppAlbum = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
            let assetIdentifierBox = IdentifierBox()
            let metadata = SavedFrameMetadata(recipe: recipe, capturedAt: capturedAt)

            PHPhotoLibrary.shared().performChanges {
                let request: PHAssetChangeRequest
                if let imageData, !imageData.isEmpty {
                    let creationRequest = PHAssetCreationRequest()
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                    request = creationRequest
                } else {
                    request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                request.creationDate = capturedAt
                assetIdentifierBox.value = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { [weak self] success, _ in
                guard let self else { return }
                Task { @MainActor in
                    guard success, let assetIdentifier = assetIdentifierBox.value else {
                        completion(false)
                        return
                    }

                    self.rememberSavedAsset(assetIdentifier, metadata: metadata)
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
            }
        }
    }

    func metadata(for asset: PHAsset) -> SavedFrameMetadata? {
        metadataByAssetIdentifier[asset.localIdentifier]
    }

    func delete(
        asset: PHAsset,
        completion: @escaping @MainActor (Result<Void, PhotoLibraryServiceError>) -> Void
    ) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            completion(.failure(.accessDenied))
            return
        }

        let assetIdentifier = asset.localIdentifier
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        } completionHandler: { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }
                guard success else {
                    completion(.failure(.changeFailed))
                    return
                }

                self.forgetSavedAsset(assetIdentifier)
                self.refresh()
                completion(.success(()))
            }
        }
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
        get { UserDefaults.standard.stringArray(forKey: savedAssetIdentifiersKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(120)), forKey: savedAssetIdentifiersKey) }
    }

    private func rememberSavedAsset(_ identifier: String, metadata: SavedFrameMetadata) {
        let identifiers = [identifier] + savedAssetIdentifiers.filter { $0 != identifier }
        savedAssetIdentifiers = Array(identifiers.prefix(120))
        metadataByAssetIdentifier[identifier] = metadata
        let retainedIdentifiers = Set(savedAssetIdentifiers)
        metadataByAssetIdentifier = metadataByAssetIdentifier.filter { retainedIdentifiers.contains($0.key) }
        persistMetadata()
    }

    private func forgetSavedAsset(_ identifier: String) {
        savedAssetIdentifiers = savedAssetIdentifiers.filter { $0 != identifier }
        metadataByAssetIdentifier.removeValue(forKey: identifier)
        persistMetadata()
    }

    private func fetchSavedAssets(options: PHFetchOptions) -> [PHAsset] {
        let identifiers = savedAssetIdentifiers
        guard !identifiers.isEmpty else { return [] }

        // Reconcile all persisted identifiers before applying the gallery's
        // display limit. Otherwise a missing asset beyond the first 60 can
        // remain in UserDefaults indefinitely and its recipe sidecar can no
        // longer be trusted.
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
        if accessibleIdentifiers != identifiers {
            savedAssetIdentifiers = accessibleIdentifiers
            pruneMetadata(keeping: accessibleIdentifiers)
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
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                albumIdentifierBox.value = request.placeholderForCreatedAssetCollection.localIdentifier
            } completionHandler: { [weak self] success, _ in
                guard let self else { return }
                Task { @MainActor in
                    guard success,
                          let albumIdentifier = albumIdentifierBox.value,
                          let createdAlbum = PHAssetCollection.fetchAssetCollections(
                              withLocalIdentifiers: [albumIdentifier],
                              options: nil
                          ).firstObject else {
                        completion(false)
                        return
                    }
                    self.addAsset(assetIdentifier, to: createdAlbum, completion: completion)
                }
            }
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

        PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
        } completionHandler: { success, _ in
            Task { @MainActor in
                completion(success)
            }
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

    private func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: accessLevel) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
