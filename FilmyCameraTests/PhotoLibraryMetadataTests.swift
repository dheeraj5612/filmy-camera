import Foundation
import XCTest
@testable import FilmyCamera

final class PhotoLibraryMetadataTests: XCTestCase {
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
}
