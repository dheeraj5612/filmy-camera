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
}
