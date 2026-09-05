import UIKit
import XCTest
@testable import FilmyCamera

@MainActor
final class CameraReviewSaveTests: XCTestCase {
    func testFailedSaveKeepsExactReviewForRetryAndSuccessDismissesIt() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = try await makeImportedReview(defaults: defaults)
        let saver = ControlledPhotoSaver()
        let originalReviewImage = try XCTUnwrap(viewModel.reviewImage)
        let originalReviewRecipe = try XCTUnwrap(viewModel.reviewRecipe)

        viewModel.saveReview(photoLibrary: saver)
        let deniedRequest = try XCTUnwrap(saver.requests.first)
        XCTAssertTrue(viewModel.isSaving)
        saver.completeLast(with: .failure(.accessDenied))

        XCTAssertFalse(viewModel.isSaving)
        XCTAssertTrue(viewModel.reviewImage === originalReviewImage)
        XCTAssertEqual(viewModel.reviewRecipe, originalReviewRecipe)
        XCTAssertEqual(viewModel.saveErrorMessage, PhotoLibrarySaveError.accessDenied.localizedDescription)
        XCTAssertTrue(viewModel.saveErrorRequiresSettings)

        let differentRecipe = try XCTUnwrap(
            FilmRecipe.builtIns.first(where: { $0.id != originalReviewRecipe.id })
        )
        viewModel.select(recipe: differentRecipe)
        viewModel.saveReview(photoLibrary: saver)

        XCTAssertNil(viewModel.saveErrorMessage)
        XCTAssertFalse(viewModel.saveErrorRequiresSettings)
        XCTAssertTrue(viewModel.isSaving)
        saver.completeLast(with: .failure(.writeFailed))
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertTrue(viewModel.reviewImage === originalReviewImage)
        XCTAssertEqual(viewModel.reviewRecipe, originalReviewRecipe)
        XCTAssertEqual(viewModel.saveErrorMessage, PhotoLibrarySaveError.writeFailed.localizedDescription)
        XCTAssertFalse(viewModel.saveErrorRequiresSettings)

        viewModel.saveReview(photoLibrary: saver)
        let successfulRequest = try XCTUnwrap(saver.requests.last)
        saver.completeLast(with: .success(()))

        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNil(viewModel.reviewImage)
        XCTAssertNil(viewModel.reviewRecipe)
        XCTAssertNil(viewModel.saveErrorMessage)
        XCTAssertFalse(viewModel.saveErrorRequiresSettings)
        XCTAssertEqual(viewModel.lastCaptureDate, successfulRequest.capturedAt)
        XCTAssertEqual(viewModel.toastStyle, .success)
        XCTAssertEqual(viewModel.toastMessage, "Saved with \(originalReviewRecipe.name)")

        XCTAssertEqual(saver.requests.count, 3)
        for request in saver.requests {
            XCTAssertTrue(request.image === deniedRequest.image)
            XCTAssertEqual(request.imageData, deniedRequest.imageData)
            XCTAssertEqual(request.recipe, deniedRequest.recipe)
            XCTAssertEqual(request.capturedAt, deniedRequest.capturedAt)
        }
        XCTAssertEqual(successfulRequest.recipe, originalReviewRecipe)
        XCTAssertNotEqual(successfulRequest.recipe.id, viewModel.selectedRecipeID)
    }

    func testSaveAndDiscardAreBlockedWhileSaveIsInFlight() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = CameraViewModel(defaults: defaults)
        let saver = ControlledPhotoSaver()

        viewModel.saveReview(photoLibrary: saver)
        XCTAssertTrue(saver.requests.isEmpty, "Saving without a review must not invoke Photos")

        try await importReview(into: viewModel)
        let reviewImage = try XCTUnwrap(viewModel.reviewImage)
        viewModel.saveReview(photoLibrary: saver)
        XCTAssertEqual(saver.requests.count, 1)
        XCTAssertTrue(viewModel.isSaving)

        viewModel.saveReview(photoLibrary: saver)
        viewModel.discardReview()

        XCTAssertEqual(saver.requests.count, 1, "Repeated Save must not create a duplicate Photos asset")
        XCTAssertTrue(viewModel.reviewImage === reviewImage, "Retake must not discard a frame while its save is unresolved")
        XCTAssertTrue(viewModel.isSaving)

        saver.completeLast(with: .success(()))
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNil(viewModel.reviewImage)
        XCTAssertNil(viewModel.reviewRecipe)
    }

    private func makeImportedReview(defaults: UserDefaults) async throws -> CameraViewModel {
        let viewModel = CameraViewModel(defaults: defaults)
        try await importReview(into: viewModel)
        return viewModel
    }

    private func importReview(into viewModel: CameraViewModel) async throws {
        let recipe = try XCTUnwrap(
            FilmRecipe.builtIns.first(where: { $0.id == "classic-chrome" })
        )
        viewModel.select(recipe: recipe)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8)).image { context in
            UIColor(red: 0.74, green: 0.32, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))

        await viewModel.importPhoto(data: data)

        XCTAssertNotNil(viewModel.reviewImage)
        XCTAssertNotNil(viewModel.reviewRecipe)
        XCTAssertEqual(viewModel.reviewSource, .photoLibrary)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CameraReviewSaveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
final class ControlledPhotoSaver: PhotoSaving {
    struct Request {
        let image: UIImage
        let imageData: Data?
        let recipe: FilmRecipe
        let capturedAt: Date
        let completion: @MainActor (Result<Void, PhotoLibrarySaveError>) -> Void
    }

    private(set) var requests: [Request] = []

    func save(
        image: UIImage,
        imageData: Data?,
        recipe: FilmRecipe,
        capturedAt: Date,
        completion: @escaping @MainActor (Result<Void, PhotoLibrarySaveError>) -> Void
    ) {
        requests.append(Request(
            image: image,
            imageData: imageData,
            recipe: recipe,
            capturedAt: capturedAt,
            completion: completion
        ))
    }

    func completeLast(with result: Result<Void, PhotoLibrarySaveError>) {
        requests.last?.completion(result)
    }
}
