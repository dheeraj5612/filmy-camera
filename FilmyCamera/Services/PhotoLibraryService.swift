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
        guard let album = appAlbum() else {
            assets = []
            return
        }

        let result = PHAsset.fetchAssets(in: album, options: options)
        assets = result.objects(at: IndexSet(integersIn: 0..<result.count))
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

            let assetIdentifierBox = IdentifierBox()
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                assetIdentifierBox.value = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { [weak self] success, _ in
                guard let self else { return }
                Task { @MainActor in
                    guard success, let assetIdentifier = assetIdentifierBox.value else {
                        completion(false)
                        return
                    }

                    self.addToAppAlbum(assetIdentifier: assetIdentifier) {
                        self.refresh()
                        completion(true)
                    }
                }
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

    private func addToAppAlbum(assetIdentifier: String, completion: @escaping @MainActor () -> Void) {
        if let album = appAlbum() {
            addAsset(assetIdentifier, to: album, completion: completion)
            return
        }

        let albumIdentifierBox = IdentifierBox()
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumTitle)
            albumIdentifierBox.value = request.placeholderForCreatedAssetCollection.localIdentifier
        } completionHandler: { [weak self] success, _ in
            guard let self else { return }
            Task { @MainActor in
                guard success,
                      let albumIdentifier = albumIdentifierBox.value,
                      let album = PHAssetCollection.fetchAssetCollections(
                          withLocalIdentifiers: [albumIdentifier],
                          options: nil
                      ).firstObject else {
                    completion()
                    return
                }
                self.addAsset(assetIdentifier, to: album, completion: completion)
            }
        }
    }

    private func addAsset(
        _ assetIdentifier: String,
        to album: PHAssetCollection,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject else {
            completion()
            return
        }

        PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
        } completionHandler: { _ , _ in
            Task { @MainActor in
                completion()
            }
        }
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
