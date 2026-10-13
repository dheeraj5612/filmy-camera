import CoreImage
import ImageIO
@preconcurrency import Photos
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

final class RuntimeHardeningTests: XCTestCase {
    @MainActor
    func testPhotoRequestTimeoutReturnsDegradedFallbackWithoutCachingIt() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let state = PhotoLibraryService.ImageRequestState(imageManager: PHImageManager.default())
        state.rememberFallback(image)
        let result: UIImage? = await withCheckedContinuation { continuation in
            XCTAssertTrue(state.install(continuation))
            state.expire()
            state.finish(with: image, cacheable: true)
            state.cancel()
        }
        XCTAssertTrue(result === image)
        XCTAssertFalse(state.canCacheResult())
    }

    @MainActor
    func testPhotoRequestDeadlineActuallyResumesAStalledRequest() async {
        let state = PhotoLibraryService.ImageRequestState(imageManager: PHImageManager.default())
        let result: UIImage? = await withCheckedContinuation { continuation in
            state.install(continuation)
            state.startTimeout(after: 0.01)
        }
        XCTAssertNil(result)
        XCTAssertFalse(state.canCacheResult())
    }

    @MainActor
    func testPhotoRequestCancelledBeforeInstallDeclinesNativeWork() async {
        let state = PhotoLibraryService.ImageRequestState(imageManager: PHImageManager.default())
        state.cancel()
        let result: UIImage? = await withCheckedContinuation { continuation in
            XCTAssertFalse(state.install(continuation))
            state.startTimeout(after: 0)
        }
        XCTAssertNil(result)
    }

    @MainActor
    func testHiddenPreviewDoesNotRetainCameraBuffers() {
        let preview = FilteredCameraPreviewView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), device: nil)
        preview.display(image: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)))
        XCTAssertFalse(preview.hasRetainedFrame)
        preview.draw(in: preview)
        XCTAssertFalse(preview.hasRetainedFrame)
    }

    @MainActor
    func testPreviewReleasesFramesOnBackgroundMemoryWarningAndWindowRemoval() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let preview = FilteredCameraPreviewView(frame: window.bounds, device: nil)
        window.addSubview(preview)
        let notifications = NotificationCenter.default
        defer { notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil) }
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        preview.display(image: image)
        XCTAssertTrue(preview.hasRetainedFrame)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(preview.hasRetainedFrame)
        preview.display(image: image)
        XCTAssertFalse(preview.hasRetainedFrame)
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        preview.display(image: image)
        XCTAssertTrue(preview.hasRetainedFrame)
        notifications.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertFalse(preview.hasRetainedFrame)
        preview.display(image: image)
        XCTAssertTrue(preview.hasRetainedFrame)
        preview.removeFromSuperview()
        XCTAssertFalse(preview.hasRetainedFrame)
    }

    @MainActor
    func testPreviewDrawableDimensionsAreFiniteAndStrictlyBudgeted() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 2_732, height: 2_048), CGSize(width: 7_680, height: 4_320)] {
            let target = try XCTUnwrap(FilteredCameraPreviewView.boundedDrawableSize(for: size, screenScale: 3))
            XCTAssertLessThanOrEqual(target.width * target.height, FilteredCameraPreviewView.previewPixelBudget)
            XCTAssertLessThanOrEqual(max(target.width, target.height), 4_096)
        }
        XCTAssertNil(FilteredCameraPreviewView.boundedDrawableSize(for: CGSize(width: CGFloat.nan, height: 100), screenScale: 3))
        XCTAssertEqual(FilteredCameraPreviewView.drawableScale(for: .zero, screenScale: .infinity), 0)
    }

    func testThumbnailAPIRejectsInvalidDimensionsWithoutRendering() {
        let recipe = FilmRecipe.builtIns[0]
        for dimension in [CGFloat.nan, .infinity, -.infinity, -1, 0] {
            let size = CGSize(width: dimension, height: 100)
            XCTAssertNil(FilmRenderer.thumbnail(for: recipe, size: size))
            XCTAssertNil(FilmRenderer.thumbnailCacheDigest(for: recipe, size: size))
        }
        XCTAssertNil(FilmRenderer.previewThumbnail(for: recipe, over: CIImage(color: .white)))
        XCTAssertNil(FilmRenderer.outputCGImage(CIImage(color: .white)))
    }

    func testThumbnailCacheDigestUsesTheSameBoundedSizeAsRendering() {
        let recipe = FilmRecipe.builtIns[0]
        XCTAssertEqual(
            FilmRenderer.thumbnailCacheDigest(for: recipe, size: CGSize(width: 4_096, height: 2_048)),
            FilmRenderer.thumbnailCacheDigest(for: recipe, size: CGSize(width: 1_024, height: 512))
        )
    }

    func testPurgingTransientCachesPreservesRecipeAndThumbnailOutputSize() throws {
        let recipe = FilmRecipe.builtIns[0]
        let size = CGSize(width: 32, height: 24)
        let before = try XCTUnwrap(FilmRenderer.thumbnail(for: recipe, size: size))
        let digest = FilmRenderer.thumbnailCacheDigest(for: recipe, size: size)
        FilmRenderer.purgeTransientCaches()
        let after = try XCTUnwrap(FilmRenderer.thumbnail(for: recipe, size: size))
        XCTAssertEqual(before.cgImage?.width, after.cgImage?.width)
        XCTAssertEqual(before.cgImage?.height, after.cgImage?.height)
        XCTAssertEqual(digest, FilmRenderer.thumbnailCacheDigest(for: recipe, size: size))
    }

    func testImportPreparationRejectsCorruptOrEmptyEncodedData() {
        XCTAssertNil(CameraViewModel.preparedImportInput(data: Data()))
        XCTAssertNil(CameraViewModel.preparedImportInput(data: Data("not an image".utf8)))
    }

    func testSmallImportPreservesFullResolutionAndOrientation() throws {
        let data = try jpeg(width: 32, height: 24, orientation: 6)
        let prepared = try XCTUnwrap(CameraViewModel.preparedImportInput(data: data))
        XCTAssertTrue(prepared.isFullResolution)
        XCTAssertEqual(prepared.image.extent.size, CGSize(width: 24, height: 32))
    }

    func testThinEncodedPanoramaIsDownsampledBeforeCoreImageRendering() throws {
        for orientation in [1, 6] {
            let data = try jpeg(width: 40_000, height: 4, orientation: orientation)
            let prepared = try XCTUnwrap(CameraViewModel.preparedImportInput(data: data))
            XCTAssertFalse(prepared.isFullResolution)
            XCTAssertEqual(max(prepared.image.extent.width, prepared.image.extent.height), CameraViewModel.importMaximumDimension)
            let expected = CameraViewModel.reviewExportExtent(
                sourceSize: CGSize(width: 40_000, height: 4), orientation: UInt32(orientation), mode: .photoLibrary
            )
            XCTAssertEqual(prepared.image.extent, expected)
        }
    }

    func testCaptureWatchdogAllowsLongExposuresButAlwaysHasAFiniteDeadline() {
        XCTAssertEqual(CameraService.captureTimeout(exposureSeconds: 1.0 / 120), 30)
        XCTAssertEqual(CameraService.captureTimeout(exposureSeconds: 30), 75)
        XCTAssertEqual(CameraService.captureTimeout(exposureSeconds: 300), 120)
        XCTAssertEqual(CameraService.captureTimeout(exposureSeconds: .greatestFiniteMagnitude), 120)
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(CameraService.captureTimeout(exposureSeconds: invalid), 30)
        }
    }

    private func jpeg(width: Int, height: Int, orientation: Int) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
