import CoreGraphics
import UIKit
import XCTest
@testable import FilmyCamera

final class CameraViewModelRenderingTests: XCTestCase {
    @MainActor
    func testImportedPhotoKeepsItsFramingAndSelectedRecipe() async throws {
        let sourceSize = CGSize(width: 80, height: 40)
        let image = UIGraphicsImageRenderer(size: sourceSize).image { context in
            UIColor(red: 0.72, green: 0.28, blue: 0.16, alpha: 1).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: sourceSize))
        }
        let sourceData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let viewModel = CameraViewModel()
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first(where: { $0.id == "classic-chrome" }))
        viewModel.select(recipe: recipe)

        await viewModel.importPhoto(data: sourceData)

        let reviewImage = try XCTUnwrap(viewModel.reviewImage)
        XCTAssertEqual(reviewImage.size.width / reviewImage.size.height, 2, accuracy: 0.01)
        XCTAssertEqual(viewModel.reviewRecipe?.id, recipe.id)
        XCTAssertEqual(viewModel.reviewSource, .photoLibrary)
        XCTAssertFalse(viewModel.isImporting)
    }

    @MainActor
    func testInvalidImportedPhotoDoesNotCreateAReview() async {
        let viewModel = CameraViewModel()

        await viewModel.importPhoto(data: Data("not an image".utf8))

        XCTAssertNil(viewModel.reviewImage)
        XCTAssertEqual(viewModel.toastStyle, .error)
        XCTAssertFalse(viewModel.isImporting)
    }

    func testScaledGrainPhasePreservesValuesBeyondSeedBitRange() {
        let seed = UInt32(0x1FF) | (UInt32(0x1FF) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            grainSize: 1,
            previewSize: CGSize(width: 300, height: 600),
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 2044, accuracy: 0.001)
        XCTAssertEqual(phase.y, 2044, accuracy: 0.001)
    }

    func testScaledGrainPhaseUsesClampedRendererScaleForLargeGrain() {
        let phase = CameraViewModel.scaledGrainPhase(
            10 | (UInt32(20) << 9),
            grainSize: 2.5,
            previewSize: CGSize(width: 1080, height: 1080),
            stillSize: CGSize(width: 4320, height: 4320)
        )

        // Preview scale = 2.5; capture scale = min(2.5 * 4, 8) = 8.
        XCTAssertEqual(phase.x, 32, accuracy: 0.001)
        XCTAssertEqual(phase.y, 64, accuracy: 0.001)
        XCTAssertNotEqual(phase.x, 40, accuracy: 0.001)
        XCTAssertNotEqual(phase.y, 80, accuracy: 0.001)
    }

    func testScaledGrainPhaseFallsBackToPreviewPhaseForInvalidSizes() {
        let seed = UInt32(17) | (UInt32(29) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            grainSize: 1,
            previewSize: .zero,
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 17, accuracy: 0.001)
        XCTAssertEqual(phase.y, 29, accuracy: 0.001)
    }
}
