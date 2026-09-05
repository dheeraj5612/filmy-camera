import CoreGraphics
import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

private actor PhotoLibraryTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor PhotoLibraryTestFlag {
    private var value = false

    func set() { value = true }
    func read() -> Bool { value }
}

final class PhotoLibraryMetadataTests: XCTestCase {
    func testPhotoLibraryCompletionBridgeHopsToMainActor() async {
        let completionExpectation = expectation(description: "Main actor completion")
        let callback = PhotoLibraryCompletionBridge.mainActor { success in
            MainActor.assertIsolated()
            XCTAssertTrue(success)
            completionExpectation.fulfill()
        }

        DispatchQueue(label: "PhotoLibraryMetadataTests.callback").async {
            callback(true, nil)
        }

        await fulfillment(of: [completionExpectation], timeout: 2)
    }

    func testAsyncCompletionBridgeCanDelayPublishedSuccessUntilCommitFinishes() async throws {
        let enteredCommit = expectation(description: "Entered cache commit")
        let publishedSuccess = expectation(description: "Published save success")
        let commitGate = PhotoLibraryTestGate()
        let didPublish = PhotoLibraryTestFlag()
        let callback = PhotoLibraryCompletionBridge.mainActorAsync { success in
            MainActor.assertIsolated()
            XCTAssertTrue(success)
            enteredCommit.fulfill()
            await commitGate.wait()
            await didPublish.set()
            publishedSuccess.fulfill()
        }

        DispatchQueue(label: "PhotoLibraryMetadataTests.asyncCallback").async {
            callback(true, nil)
        }

        await fulfillment(of: [enteredCommit], timeout: 2)
        try await Task.sleep(for: .milliseconds(100))
        let publishedBeforeCommit = await didPublish.read()
        XCTAssertFalse(publishedBeforeCommit)

        await commitGate.open()
        await fulfillment(of: [publishedSuccess], timeout: 2)
    }

    func testSavedFrameMetadataPreservesRecipeAndCaptureDate() throws {
        let recipe = FilmRecipe.builtIns[3]
        let capturedAt = Date(timeIntervalSince1970: 1_754_000_123.456)
        let original = SavedFrameMetadata(recipe: recipe, capturedAt: capturedAt)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedFrameMetadata.self, from: data)

        XCTAssertEqual(decoded.recipe, recipe)
        XCTAssertEqual(decoded.capturedAt, capturedAt)
    }

    func testPhotoLibraryMutationErrorsExplainRecovery() {
        XCTAssertTrue(PhotoLibraryServiceError.accessDenied.localizedDescription.contains("Settings"))
        XCTAssertTrue(PhotoLibraryServiceError.notOwned.localizedDescription.contains("created"))
        XCTAssertTrue(PhotoLibraryServiceError.changeFailed.localizedDescription.contains("Try again"))
    }

    func testSaveFailuresDistinguishAuthorizationFromPhotoKitWriteFailure() {
        XCTAssertEqual(PhotoLibrarySaveError.failure(for: .denied), .accessDenied)
        XCTAssertEqual(PhotoLibrarySaveError.failure(for: .restricted), .accessDenied)
        XCTAssertEqual(PhotoLibrarySaveError.failure(for: .authorized), .writeFailed)
        XCTAssertTrue(PhotoLibrarySaveError.accessDenied.localizedDescription.contains("Settings"))
        XCTAssertTrue(PhotoLibrarySaveError.writeFailed.localizedDescription.contains("try again"))
    }

    func testCachedFrameDimensionsComeFromFullResolutionJPEG() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 40,
            height: 30,
            bitsPerComponent: 8,
            bytesPerRow: 40 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let downsampledFallback = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3)).image { _ in }
        XCTAssertEqual(
            PhotoLibraryService.pixelDimensions(
                in: data as Data,
                fallbackImage: downsampledFallback
            ),
            PhotoPixelDimensions(width: 40, height: 30)
        )
    }

    func testCachePersistenceReturnsAfterAtomicJPEGIsReadable() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resourceURL = directory.appendingPathComponent("saved-frame.jpg")
        let expected = Data((0..<4_096).map { UInt8($0 % 251) })
        defer { try? fileManager.removeItem(at: directory) }

        let didWrite = await PhotoLibraryService.persistCachedFrameData(
            expected,
            directoryURL: directory,
            resourceURL: resourceURL
        )

        XCTAssertTrue(didWrite)
        XCTAssertEqual(try Data(contentsOf: resourceURL), expected)
    }

    @MainActor
    func testPhysicalAddOnlySaveCallbackHasReadablePersistentCache() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Add-only cache integration requires a physical iOS device")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_ADD_ONLY_CACHE_QA"] == "1",
            "Set FILMY_RUN_ADD_ONLY_CACHE_QA=1 after configuring Add Photos Only access"
        )

        let service = PhotoLibraryService()
        try XCTSkipUnless(
            service.canSaveToPhotos,
            "Grant Add Photos Only access in Settings before running this opt-in test"
        )
        try XCTSkipUnless(
            !PhotoLibraryAuthorizationPolicy.canRead(
                PHPhotoLibrary.authorizationStatus(for: .readWrite)
            ),
            "Configure Photos access as Add Photos Only so this test exercises the local Roll cache"
        )

        service.refresh()
        let identifiersBeforeSave = Set(service.localSavedFrames.map(\.assetIdentifier))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            UIColor(red: 0.18, green: 0.42, blue: 0.68, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            UIColor(red: 0.92, green: 0.58, blue: 0.24, alpha: 1).setFill()
            context.fill(CGRect(x: 32, y: 0, width: 32, height: 48))
        }
        let imageData = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))

        let (saveResult, frameAtCallback) = await withCheckedContinuation { continuation in
            service.save(
                image: image,
                imageData: imageData,
                recipe: FilmRecipe.builtIns[0]
            ) { result in
                let newFrame = service.localSavedFrames.first {
                    !identifiersBeforeSave.contains($0.assetIdentifier)
                }
                continuation.resume(returning: (result, newFrame))
            }
        }
        try saveResult.get()

        let newFrame = try XCTUnwrap(
            frameAtCallback,
            "Save success must publish only after the new local cache is indexed"
        )
        let resolvedCacheURL = await service.shareURL(for: .cached(newFrame))
        let cacheURL = try XCTUnwrap(
            resolvedCacheURL,
            "Save success must publish only after the local JPEG is readable"
        )
        XCTAssertEqual(try Data(contentsOf: cacheURL), imageData)

        let recreatedService = PhotoLibraryService()
        recreatedService.refresh()
        let recreatedFrame = try XCTUnwrap(
            recreatedService.localSavedFrames.first {
                $0.assetIdentifier == newFrame.assetIdentifier
            },
            "A new service instance must restore the committed local cache index"
        )
        let resolvedRecreatedURL = await recreatedService.shareURL(for: .cached(recreatedFrame))
        let recreatedURL = try XCTUnwrap(resolvedRecreatedURL)
        XCTAssertEqual(try Data(contentsOf: recreatedURL), imageData)
        #endif
    }

    func testReadWriteAuthorizationAllowsFullAndLimitedAccess() {
        XCTAssertTrue(PhotoLibraryAuthorizationPolicy.canRead(.authorized))
        XCTAssertTrue(PhotoLibraryAuthorizationPolicy.canRead(.limited))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canRead(.notDetermined))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canRead(.denied))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canRead(.restricted))
    }

    func testAddOnlyAuthorizationIsDistinctFromLimitedReadAccess() {
        XCTAssertTrue(PhotoLibraryAuthorizationPolicy.canAdd(.authorized))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canAdd(.limited))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canAdd(.notDetermined))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canAdd(.denied))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canAdd(.restricted))
    }

    func testLimitedReadAccessCannotManageAnAppAlbum() {
        XCTAssertTrue(PhotoLibraryAuthorizationPolicy.canManageCollections(.authorized))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canManageCollections(.limited))
        XCTAssertFalse(PhotoLibraryAuthorizationPolicy.canManageCollections(.denied))
    }

    func testAssetOwnershipFailsClosedForUnknownAndEmptyIdentifiers() {
        let savedIdentifiers = ["asset-created-by-filmy-camera"]

        XCTAssertTrue(PhotoLibraryAssetOwnership.contains(
            "asset-created-by-filmy-camera",
            in: savedIdentifiers
        ))
        XCTAssertFalse(PhotoLibraryAssetOwnership.contains("user-owned-asset", in: savedIdentifiers))
        XCTAssertFalse(PhotoLibraryAssetOwnership.contains("", in: savedIdentifiers))
    }

    func testAssetOwnershipPersistsNewestUniqueBoundedIdentifiers() {
        let savedIdentifiers = ["oldest", "middle", "newest"]

        XCTAssertEqual(
            PhotoLibraryAssetOwnership.adding("middle", to: savedIdentifiers, limit: 3),
            ["middle", "oldest", "newest"]
        )
        XCTAssertEqual(
            PhotoLibraryAssetOwnership.adding("created-now", to: savedIdentifiers, limit: 2),
            ["created-now", "oldest"]
        )
        XCTAssertEqual(
            PhotoLibraryAssetOwnership.adding("", to: ["", "known", "known"], limit: 10),
            ["known"]
        )
    }

    func testAssetOwnershipRemovalIsExact() {
        XCTAssertEqual(
            PhotoLibraryAssetOwnership.removing(
                "created-by-filmy-camera",
                from: ["created-by-filmy-camera", "user-owned-asset"]
            ),
            ["user-owned-asset"]
        )
        XCTAssertEqual(
            PhotoLibraryAssetOwnership.removing("unknown", from: ["known"]),
            ["known"]
        )
    }

    func testLocalCachePathRejectsTraversalAndAbsolutePaths() {
        let directory = URL(fileURLWithPath: "/tmp/FilmyCameraFrames", isDirectory: true)

        XCTAssertEqual(
            PhotoLibraryCachePath.fileURL(filename: "frame.jpg", in: directory)?.path,
            "/tmp/FilmyCameraFrames/frame.jpg"
        )
        XCTAssertNil(PhotoLibraryCachePath.fileURL(filename: "../frame.jpg", in: directory))
        XCTAssertNil(PhotoLibraryCachePath.fileURL(filename: "nested/frame.jpg", in: directory))
        XCTAssertNil(PhotoLibraryCachePath.fileURL(filename: "/tmp/frame.jpg", in: directory))
        XCTAssertNil(PhotoLibraryCachePath.fileURL(filename: "", in: directory))
    }

    func testLocalCacheReconciliationRemovesOrphansButPreservesIndexedFiles() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let indexedURL = directory.appendingPathComponent("indexed.jpg")
        let orphanURL = directory.appendingPathComponent("orphan.jpg")
        let hiddenOrphanURL = directory.appendingPathComponent(".orphan.jpg")
        let nestedDirectory = directory.appendingPathComponent("nested", isDirectory: true)
        let nestedFileURL = nestedDirectory.appendingPathComponent("nested.jpg")
        try Data([1]).write(to: indexedURL)
        try Data([2]).write(to: orphanURL)
        try Data([3]).write(to: hiddenOrphanURL)
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data([4]).write(to: nestedFileURL)

        let result = PhotoLibraryCachePath.removeRegularFiles(
            in: directory,
            preservingFilenames: [indexedURL.lastPathComponent]
        )

        XCTAssertEqual(result?.removedFilenames, [orphanURL.lastPathComponent, hiddenOrphanURL.lastPathComponent])
        XCTAssertTrue(fileManager.fileExists(atPath: indexedURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: orphanURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: hiddenOrphanURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: nestedDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: nestedFileURL.path))
    }

    func testLocalCacheCleanupKeepsRetryableFilesWhenDeletionFails() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let retryableURL = directory.appendingPathComponent("retryable.jpg")
        let removableURL = directory.appendingPathComponent("removable.jpg")
        try Data([1]).write(to: retryableURL)
        try Data([2]).write(to: removableURL)

        let result = PhotoLibraryCachePath.removeRegularFiles(in: directory) { url in
            if url.lastPathComponent == retryableURL.lastPathComponent {
                throw NSError(domain: "PhotoLibraryMetadataTests", code: 1)
            }
            try fileManager.removeItem(at: url)
        }

        XCTAssertEqual(result?.failedFilenames, [retryableURL.lastPathComponent])
        XCTAssertEqual(result?.removedFilenames, [removableURL.lastPathComponent])
        XCTAssertTrue(fileManager.fileExists(atPath: retryableURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: removableURL.path))
    }

    func testGalleryImagePolicyReloadsPhotosAssetsAfterAuthorizationChanges() {
        let deniedKey = PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: "photos-asset",
            isPhotosAsset: true,
            authorizationStatus: .denied
        )
        let authorizedKey = PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: "photos-asset",
            isPhotosAsset: true,
            authorizationStatus: .authorized
        )

        XCTAssertFalse(PhotoLibraryGalleryImagePolicy.canLoad(
            isPhotosAsset: true,
            authorizationStatus: .denied
        ))
        XCTAssertTrue(PhotoLibraryGalleryImagePolicy.canLoad(
            isPhotosAsset: true,
            authorizationStatus: .authorized
        ))
        XCTAssertNotEqual(deniedKey, authorizedKey)
    }

    func testGalleryImagePolicyKeepsCachedFramesIndependentOfPhotosAuthorization() {
        let deniedKey = PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: "cached-frame",
            isPhotosAsset: false,
            authorizationStatus: .denied
        )
        let authorizedKey = PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: "cached-frame",
            isPhotosAsset: false,
            authorizationStatus: .authorized
        )

        XCTAssertTrue(PhotoLibraryGalleryImagePolicy.canLoad(
            isPhotosAsset: false,
            authorizationStatus: .denied
        ))
        XCTAssertEqual(deniedKey, authorizedKey)
    }

    func testCachedThumbnailPixelSizeIsFiniteBoundedAndRoundedUp() {
        XCTAssertEqual(
            PhotoLibraryService.thumbnailMaxPixelSize(
                for: CGSize(width: 360.1, height: 440.1)
            ),
            441
        )
        XCTAssertEqual(
            PhotoLibraryService.thumbnailMaxPixelSize(
                for: CGSize(width: CGFloat.nan, height: CGFloat.infinity)
            ),
            1
        )
        XCTAssertEqual(
            PhotoLibraryService.thumbnailMaxPixelSize(
                for: CGSize(width: 20_000, height: 100)
            ),
            8_192
        )
        XCTAssertEqual(
            PhotoLibraryService.thumbnailMaxPixelSize(
                for: CGSize(width: -1, height: 0)
            ),
            1
        )
    }

    func testThumbnailCacheKeyBypassesUnsafeOrDetailSizedRequests() {
        let base: (CGSize) -> String? = { targetSize in
            PhotoLibraryThumbnailCachePolicy.key(
                assetIdentifier: "asset",
                targetSize: targetSize,
                contentMode: .aspectFill,
                authorizationStatus: .authorized,
                revision: "revision"
            )
        }

        XCTAssertNotNil(base(CGSize(width: 600, height: 480)))
        XCTAssertNil(base(CGSize(width: 601, height: 480)))
        XCTAssertNil(base(CGSize(width: CGFloat.infinity, height: 480)))
        XCTAssertNil(base(CGSize(width: CGFloat.nan, height: 480)))
    }

    func testThumbnailCacheKeySeparatesAssetRevisions() {
        let key = { revision in
            PhotoLibraryThumbnailCachePolicy.key(
                assetIdentifier: "asset",
                targetSize: CGSize(width: 400, height: 400),
                contentMode: .aspectFill,
                authorizationStatus: .authorized,
                revision: revision
            )
        }

        XCTAssertNotEqual(key("2000x1500|1"), key("2000x1500|2"))
        XCTAssertNotEqual(key("2000x1500|1"), key("3000x2000|1"))
    }

    @MainActor
    func testImageRequestStateOnlyCachesConfirmedFinalResults() async {
        let fallback = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        let failedState = PhotoLibraryService.ImageRequestState(
            imageManager: PHImageManager.default()
        )
        failedState.rememberFallback(fallback)
        let failedResult: UIImage? = await withCheckedContinuation { continuation in
            failedState.install(continuation)
            // Models a degraded preview followed by a final nil/error result.
            failedState.finish(with: nil, allowFallback: true)
        }
        XCTAssertEqual(failedResult?.pngData(), fallback.pngData())
        XCTAssertFalse(failedState.canCacheResult())

        let finalImage = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let successState = PhotoLibraryService.ImageRequestState(
            imageManager: PHImageManager.default()
        )
        let successResult: UIImage? = await withCheckedContinuation { continuation in
            successState.install(continuation)
            successState.finish(with: finalImage, cacheable: true)
        }
        XCTAssertEqual(successResult?.pngData(), finalImage.pngData())
        XCTAssertTrue(successState.canCacheResult())

        let cancelledState = PhotoLibraryService.ImageRequestState(
            imageManager: PHImageManager.default()
        )
        cancelledState.rememberFallback(fallback)
        let cancelledResult: UIImage? = await withCheckedContinuation { continuation in
            cancelledState.install(continuation)
            cancelledState.cancel()
        }
        XCTAssertNil(cancelledResult)
        XCTAssertFalse(cancelledState.canCacheResult())
    }
}
