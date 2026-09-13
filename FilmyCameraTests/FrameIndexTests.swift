import CoreImage
import UIKit
import XCTest
@testable import FilmyCamera

@MainActor
final class FrameIndexControlPolicyTests: XCTestCase {
    func testExposureDragQuantizesAndClampsWithoutAccumulatingAppliedValue() {
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: 0, translation: 36), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: 0, translation: -36), -1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: 1, translation: 0), 1)
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: 0, translation: 5), 0)
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: 1, translation: 10_000), 2)
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: -1, translation: -10_000), -2)
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: .nan, translation: 0), 0)
        XCTAssertEqual(ExposureDragControl.dragValue(startingAt: 0, translation: .infinity), 0)
    }

    func testComparisonFractionRejectsNonfiniteInputAndHonorsBothEdges() {
        XCTAssertEqual(PhotoComparisonView.clampedFraction(-1), 0)
        XCTAssertEqual(PhotoComparisonView.clampedFraction(2), 1)
        XCTAssertEqual(PhotoComparisonView.clampedFraction(0.73), 0.73)
        XCTAssertEqual(PhotoComparisonView.clampedFraction(.nan), 0.5)
        XCTAssertEqual(PhotoComparisonView.clampedFraction(.infinity), 0.5)
    }

    func testSplitComparisonRequiresTheSamePhotoGeometry() {
        XCTAssertTrue(PhotoComparisonView.hasMatchingAspect(CGSize(width: 300, height: 400), CGSize(width: 900, height: 1200)))
        XCTAssertFalse(PhotoComparisonView.hasMatchingAspect(CGSize(width: 300, height: 400), CGSize(width: 400, height: 300)))
        // An Instant Print has a different aspect ratio; a split would imply
        // that its white border was aligned with pixels in the original.
        XCTAssertFalse(PhotoComparisonView.hasMatchingAspect(CGSize(width: 1086, height: 1448), CGSize(width: 1164, height: 1618)))
        XCTAssertFalse(PhotoComparisonView.hasMatchingAspect(.zero, CGSize(width: 300, height: 400)))
        XCTAssertFalse(PhotoComparisonView.hasMatchingAspect(CGSize(width: CGFloat.infinity, height: 400), CGSize(width: 300, height: 400)))
    }
}

@MainActor
final class FrameIndexPreviewRenderingTests: XCTestCase {
    func testOriginalPreviewBypassesFilmWithoutChangingFramingOrInputPixels() throws {
        let input = fixture()
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "classic-chrome" })
        for target in [CGSize(width: 72, height: 96), CGSize(width: 96, height: 72), CGSize(width: 80, height: 80)] {
            let frame = CameraFrameLayout.aspectFill(input, in: CGRect(origin: .zero, size: target))
            let original = FilteredCameraPreviewView.displayImage(frame, recipe: recipe, quality: .preview,
                                                                  grainSeed: 17, showsOriginal: true)
            XCTAssertEqual(original.extent, frame.extent)
            XCTAssertEqual(try pixels(original), try pixels(frame), "Original must not apply a neutral-looking substitute recipe")
        }
    }

    func testLookPreviewRetainsTheExactExistingRendererPath() throws {
        let frame = CameraFrameLayout.aspectFill(fixture(), in: CGRect(x: 0, y: 0, width: 72, height: 96))
        for id in ["classic-chrome", "acros-monochrome", "g7x-compact"] {
            let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == id })
            let expected = FilmRenderer.render(frame, recipe: recipe, quality: .preview, grainSeed: 17)
            let actual = FilteredCameraPreviewView.displayImage(frame, recipe: recipe, quality: .preview,
                                                                grainSeed: 17, showsOriginal: false)
            XCTAssertEqual(try pixels(actual), try pixels(expected), id)
        }
    }

    func testComparingDoesNotMutateTheRecipeOrFullResolutionOutput() throws {
        let input = fixture()
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "classic-chrome" })
        let recipeBefore = recipe
        let captureBefore = FilmRenderer.render(input, recipe: recipe, quality: .photo, grainSeed: 17)
        let bytesBefore = try pixels(captureBefore)
        _ = FilteredCameraPreviewView.displayImage(input, recipe: recipe, quality: .preview,
                                                  grainSeed: 17, showsOriginal: true)
        _ = FilteredCameraPreviewView.displayImage(input, recipe: recipe, quality: .preview,
                                                  grainSeed: 17, showsOriginal: false)
        XCTAssertEqual(recipe, recipeBefore)
        XCTAssertEqual(try pixels(FilmRenderer.render(input, recipe: recipe, quality: .photo, grainSeed: 17)), bytesBefore)
        XCTAssertNotEqual(try pixels(input), bytesBefore, "Fixture must distinguish the film treatment from unfiltered pixels")
    }

    private func fixture() -> CIImage {
        // A color-rich, deterministic non-photographic fixture with hard edges
        // makes film color, grain and framing differences observable.
        let base = CIImage(color: CIColor(red: 0.12, green: 0.45, blue: 0.72))
            .cropped(to: CGRect(x: 0, y: 0, width: 144, height: 192))
        let stripe = CIImage(color: CIColor(red: 0.84, green: 0.26, blue: 0.10))
            .cropped(to: CGRect(x: 35, y: 20, width: 57, height: 146))
        let light = CIImage(color: CIColor(red: 0.93, green: 0.88, blue: 0.73))
            .cropped(to: CGRect(x: 70, y: 95, width: 62, height: 61))
        return light.composited(over: stripe.composited(over: base)).cropped(to: base.extent)
    }

    private func pixels(_ image: CIImage) throws -> Data {
        let extent = image.extent.integral
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let width = Int(extent.width), height = Int(extent.height)
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            CIContext(options: FilmRenderer.testContextOptions).render(image, toBitmap: bytes.baseAddress!,
                rowBytes: width * 4, bounds: extent, format: .RGBA8, colorSpace: colorSpace)
        }
        return data
    }
}
