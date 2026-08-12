import Combine
@preconcurrency import Photos
import UIKit

@MainActor
final class PhotoLibraryService: ObservableObject {
    private final class IdentifierBox: @unchecked Sendable {
        var value: String?
    }

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false

    private let albumTitle = "Filmy Camera"
    private let savedAssetIdentifiersKey = "filmyCamera.savedAssetIdentifiers"
    private let isUITesting: Bool

    init() {
        isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
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
            assets = result.objects(at: IndexSet(integersIn: 0..<result.count))
        } else {
            assets = fetchSavedAssets(options: options)
        }
    }

    func save(image: UIImage, completion: @escaping @MainActor (Bool) -> Void) {
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
            let existingAlbum = canManageAppAlbum ? appAlbum() : nil
            let albumTitle = self.albumTitle
            let assetIdentifierBox = IdentifierBox()

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    guard let placeholder = request.placeholderForCreatedAsset else { return }
                    assetIdentifierBox.value = placeholder.localIdentifier

                    if let existingAlbum {
                        PHAssetCollectionChangeRequest(for: existingAlbum)?.addAssets([placeholder] as NSArray)
                    } else if canManageAppAlbum {
                        let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                            withTitle: albumTitle
                        )
                        albumRequest.addAssets([placeholder] as NSArray)
                    }
                }
            } catch {
                completion(false)
                return
            }

            guard let assetIdentifier = assetIdentifierBox.value else {
                completion(false)
                return
            }

            rememberSavedAsset(assetIdentifier)
            self.refresh()
            completion(true)
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

    private func rememberSavedAsset(_ identifier: String) {
        savedAssetIdentifiers = [identifier] + savedAssetIdentifiers.filter { $0 != identifier }
    }

    private func fetchSavedAssets(options: PHFetchOptions) -> [PHAsset] {
        let identifiers = savedAssetIdentifiers
        guard !identifiers.isEmpty else { return [] }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: options)
        let fetched = result.objects(at: IndexSet(integersIn: 0..<result.count))
        let assetsByIdentifier = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        let accessibleIdentifiers = identifiers.filter { assetsByIdentifier[$0] != nil }
        if accessibleIdentifiers != identifiers {
            savedAssetIdentifiers = accessibleIdentifiers
        }
        return accessibleIdentifiers.compactMap { assetsByIdentifier[$0] }
    }

    func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: accessLevel) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
