import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

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
}
