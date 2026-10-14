import CoreMedia
import CoreImage
import CoreLocation
import ImageIO
import SwiftUI
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

    func testCameraCaptureSavesImmediatelyWithoutPresentingImportReview() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CameraViewModel(defaults: defaults)
        let saver = ControlledPhotoSaver()
        let photo = try capturedPhoto()
        let recipe = model.selectedRecipe

        model.saveCapturedPhoto(photo, recipe: recipe, finish: .instantPrint, photoLibrary: saver)

        XCTAssertEqual(saver.requests.count, 1, "The capture must start saving without a UI Save action")
        XCTAssertTrue(model.isSaving)
        XCTAssertTrue(model.hasPendingCapture)
        XCTAssertFalse(model.isReviewingImport)
        XCTAssertFalse(model.isRenderingReview)
        XCTAssertEqual(model.reviewFinish, .instantPrint)
        XCTAssertEqual(saver.requests[0].imageData, photo.data)
        XCTAssertEqual(saver.requests[0].capturedAt, photo.capturedAt)
        saver.completeLast(with: .success(()))
        XCTAssertFalse(model.hasPendingCapture)
        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.reviewImage)
        XCTAssertEqual(model.lastCaptureDate, photo.capturedAt)
    }

    func testCameraSaveFailureRetainsExactBytesAndBlocksOverwritingTheFrame() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CameraViewModel(defaults: defaults)
        let saver = ControlledPhotoSaver()
        let photo = try capturedPhoto()
        let recipe = model.selectedRecipe
        model.saveCapturedPhoto(photo, recipe: recipe, finish: .instantPrint, photoLibrary: saver)
        saver.completeLast(with: .failure(.accessDenied))
        XCTAssertFalse(model.isSaving)
        XCTAssertFalse(model.isReviewingImport, "Failure must not bring back Retake/Save review")
        XCTAssertTrue(model.hasPendingCapture)
        XCTAssertTrue(model.saveErrorRequiresSettings)

        model.select(recipe: try XCTUnwrap(model.recipes.first { $0.id != recipe.id }))
        model.saveCapturedPhoto(try capturedPhoto(), recipe: model.selectedRecipe, photoLibrary: saver)
        XCTAssertEqual(saver.requests.count, 1, "A failed photo must not be replaced by a new shutter result")
        XCTAssertTrue(model.reviewImage === photo.image)
        model.saveReview(photoLibrary: saver)
        XCTAssertEqual(saver.requests.count, 2)
        XCTAssertEqual(saver.requests[1].imageData, photo.data)
        XCTAssertEqual(saver.requests[1].recipe, recipe)
        XCTAssertEqual(saver.requests[1].capturedAt, photo.capturedAt)
        XCTAssertEqual(model.reviewFinish, .instantPrint)
        saver.completeLast(with: .success(()))
        XCTAssertFalse(model.hasPendingCapture)
    }

    func testRepeatedAndLateSaveCallbacksCannotSettleAnotherAttempt() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CameraViewModel(defaults: defaults)
        let saver = ControlledPhotoSaver()
        let photo = try capturedPhoto()
        model.saveCapturedPhoto(photo, recipe: model.selectedRecipe, photoLibrary: saver)
        let first = try XCTUnwrap(saver.requests.first)
        model.saveReview(photoLibrary: saver)
        model.saveCapturedPhoto(photo, recipe: model.selectedRecipe, photoLibrary: saver)
        XCTAssertEqual(saver.requests.count, 1)
        first.completion(.failure(.writeFailed))
        first.completion(.success(()))
        XCTAssertTrue(model.hasPendingCapture, "A duplicate completion must not override a failed save")
        XCTAssertNil(model.lastCaptureDate)
        model.saveReview(photoLibrary: saver)
        first.completion(.success(()))
        XCTAssertTrue(model.isSaving, "An old callback cannot settle a newer retry")
        XCTAssertTrue(model.hasPendingCapture)
        saver.completeLast(with: .success(()))
        first.completion(.failure(.accessDenied))
        XCTAssertNil(model.saveErrorMessage)
        XCTAssertFalse(model.hasPendingCapture)
    }

    func testCameraCaptureCannotReplaceAnImportedPhotoBeingEdited() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = try await makeImportedReview(defaults: defaults)
        let original = model.reviewImage
        let saver = ControlledPhotoSaver()
        model.saveCapturedPhoto(try capturedPhoto(), recipe: model.selectedRecipe, photoLibrary: saver)
        XCTAssertTrue(saver.requests.isEmpty)
        XCTAssertTrue(model.isReviewingImport)
        XCTAssertTrue(model.reviewImage === original)
    }

    private func captureSourcePhoto(data: Data? = nil) throws -> CameraService.CapturedPhoto {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let bytes = try data ?? XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        return CameraService.CapturedPhoto(
            fileData: bytes, capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            dimensions: CMVideoDimensions(width: 40, height: 30)
        )
    }

    func testSidewaysCaptureBakesStillViewportIntoGeometryAndSavesWideFrame() async throws {
        func develop(
            viewport: CGSize?, angle: CGFloat?
        ) async throws -> (geometry: CGSize, saved: CGSize) {
            let (defaults, suiteName) = try makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = FilmyPhotoStore(root: root)
            let model = CameraViewModel(defaults: defaults, photoStore: store)
            let saver = ControlledPhotoSaver()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }
            let photo = try captureSourcePhoto(data: XCTUnwrap(image.jpegData(compressionQuality: 0.9)))
            let result: Bool
            if let viewport {
                result = await model.developCapturedPhotoForTesting(
                    photo, recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver,
                    viewport: viewport, previewRotationAngle: angle
                )
            } else {
                result = await model.developCapturedPhotoForTesting(
                    photo, recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver
                )
            }
            XCTAssertTrue(result)
            for _ in 0..<200 where saver.requests.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
            let request = try XCTUnwrap(saver.requests.last)
            let data = try XCTUnwrap(request.imageData)
            let saved = try XCTUnwrap(CameraFrameLayout.orientedPixelSize(of: data))
            let inventory = try await store.inventory()
            let geometry = try XCTUnwrap(inventory.documents.first).geometry
            saver.completeLast(with: .success(()))
            return (CGSize(width: geometry.viewportWidth, height: geometry.viewportHeight), saved)
        }

        let portraitViewport = CGSize(width: 393, height: 524)
        let sideways = try await develop(viewport: portraitViewport, angle: 90)
        XCTAssertEqual(sideways.geometry, CGSize(width: 524, height: 393))
        XCTAssertEqual(sideways.saved, CGSize(width: 40, height: 30))

        let unknownAngle = try await develop(viewport: portraitViewport, angle: nil)
        XCTAssertEqual(unknownAngle.geometry, portraitViewport)
        XCTAssertEqual(unknownAngle.saved, CGSize(width: 22, height: 30))

        let defaults = try await develop(viewport: nil, angle: nil)
        XCTAssertEqual(defaults.geometry, CGSize(width: 100, height: 100))
    }

    func testFailedOriginalWriteKeepsRetryableCaptureAndRetryIsExplicit() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0]).write(to: root)
        let model = CameraViewModel(defaults: defaults, photoStore: FilmyPhotoStore(root: root))
        let saver = ControlledPhotoSaver()
        let camera = CameraService()

        let first = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: camera, photoLibrary: saver
        )
        XCTAssertFalse(first)
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.toastStyle, .error)
        XCTAssertTrue(saver.requests.isEmpty)

        try FileManager.default.removeItem(at: root)
        model.capture(camera: camera, photoLibrary: saver)
        XCTAssertTrue(model.isCapturing)
        XCTAssertEqual(model.toastStyle, .info)
        XCTAssertEqual(model.toastMessage, "Saving your earlier photo. No new photo is taken.")
        for _ in 0..<200 where saver.requests.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(saver.requests.count, 1)
        XCTAssertFalse(model.isCapturing)
        saver.completeLast(with: .success(()))
        XCTAssertFalse(model.hasPendingCapture)
    }

    func testUndevelopableCaptureRetainsOriginalAndReleasesShutter() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()
        let source = try captureSourcePhoto()
        // Recognised as JPEG by the store, but cut off before the first
        // start-of-frame marker: header segments only, no dimensions and no
        // scan data, so no decoder on any OS can produce pixels.
        let bytes = [UInt8](source.fileData)
        XCTAssertEqual(bytes[0], 0xFF)
        XCTAssertEqual(bytes[1], 0xD8)
        var keptCount = 2
        while keptCount + 4 <= bytes.count {
            let marker = bytes[keptCount + 1]
            let isStartOfFrame = marker == 0xC0 || marker == 0xC1 || marker == 0xC2
            if bytes[keptCount] != 0xFF || isStartOfFrame { break }
            let segmentLength = (Int(bytes[keptCount + 2]) << 8) | Int(bytes[keptCount + 3])
            keptCount += 2 + segmentLength
        }
        XCTAssertLessThan(keptCount, bytes.count)
        let truncated = Data(bytes.prefix(keptCount))
        XCTAssertNotNil(FilmyPhotoStore.imageExtension(truncated))
        XCTAssertNil(CameraViewModel.render(
            sourceData: truncated, recipe: model.selectedRecipe,
            viewportSize: CGSize(width: 100, height: 100),
            previewDrawableSize: CGSize(width: 100, height: 100),
            capturedAt: source.capturedAt, flashFired: false, grainSeed: 1,
            outputSettings: .legacy
        ))
        let camera = CameraService()

        let result = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(data: truncated), recipe: model.selectedRecipe,
            camera: camera, photoLibrary: saver
        )
        XCTAssertFalse(result)
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.toastStyle, .error)
        XCTAssertEqual(
            model.toastMessage,
            "Original retained in Filmy originals. Open it there to retry developing this look."
        )
        XCTAssertTrue(saver.requests.isEmpty)

        model.capture(camera: camera, photoLibrary: saver)
        // The retry branch sets this info toast synchronously; the normal
        // shutter path clears the toast instead.
        XCTAssertNotEqual(model.toastMessage, "Saving your earlier photo. No new photo is taken.")
        XCTAssertNotEqual(model.toastStyle, .info)
        for _ in 0..<100 where model.isCapturing { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.isCapturing)
        XCTAssertNotEqual(model.toastMessage, "Saving your earlier photo. No new photo is taken.")
        // A retained frame would have been created a second time.
        let inventory = try await store.inventory()
        XCTAssertEqual(inventory.documents.count, 1)
        XCTAssertTrue(saver.requests.isEmpty)
    }

    func testFailedDevelopedRevisionKeepsOriginalAndReleasesShutter() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()
        let camera = CameraService()
        let source = try captureSourcePhoto()
        // Not JPEG or HEIC, so the store refuses it as a rendition.
        let unusable = CameraViewModel.RenderedPhoto(image: UIImage(), data: Data([0]), capturedAt: source.capturedAt)

        let result = await model.developCapturedPhotoForTesting(
            source, recipe: model.selectedRecipe, camera: camera, photoLibrary: saver,
            renderOverride: { unusable }
        )
        XCTAssertFalse(result)
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.toastStyle, .error)
        XCTAssertEqual(
            model.toastMessage,
            "Original retained. Filmy could not save the developed version; retry from Filmy originals."
        )
        XCTAssertTrue(saver.requests.isEmpty)
        let inventory = try await store.inventory()
        XCTAssertEqual(inventory.documents.count, 1)

        model.capture(camera: camera, photoLibrary: saver)
        XCTAssertNotEqual(model.toastMessage, "Saving your earlier photo. No new photo is taken.")
        for _ in 0..<100 where model.isCapturing { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.isCapturing)
    }

    func testLiveMovieIsKeptUntilTheOriginalIsPersisted() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = CameraService.livePhotoTemporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func makeMovie() throws -> URL {
            let url = directory.appendingPathComponent("\(UUID().uuidString).mov")
            try Data([1, 2, 3]).write(to: url)
            return url
        }
        var liveSettings = ProCaptureSettings()
        liveSettings.livePhoto = true
        liveSettings.format = .heif
        liveSettings.resolution = .mp12
        XCTAssertNil(liveSettings.incompatibility)
        let source = try captureSourcePhoto()
        func livePhoto(_ movie: URL) -> CameraService.CapturedPhoto {
            CameraService.CapturedPhoto(
                fileData: source.fileData, capturedAt: source.capturedAt, dimensions: source.dimensions,
                livePhotoMovieURL: movie, outputSettings: liveSettings
            )
        }

        // The original cannot be written (the store root is a plain file): the
        // movie must survive for the explicit retry.
        let blockedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: blockedRoot) }
        try Data([0]).write(to: blockedRoot)
        let blockedModel = CameraViewModel(defaults: defaults, photoStore: FilmyPhotoStore(root: blockedRoot))
        let kept = try makeMovie()
        defer { try? FileManager.default.removeItem(at: kept) }
        let saver = ControlledPhotoSaver()
        let camera = CameraService()
        let failed = await blockedModel.developCapturedPhotoForTesting(
            livePhoto(kept), recipe: blockedModel.selectedRecipe, camera: camera, photoLibrary: saver
        )
        XCTAssertFalse(failed)
        XCTAssertFalse(blockedModel.isCapturing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "The Live movie must outlive a failed original write")
        blockedModel.capture(camera: camera, photoLibrary: saver)
        XCTAssertEqual(blockedModel.toastMessage, "Saving your earlier photo. No new photo is taken.")
        for _ in 0..<100 where blockedModel.isCapturing { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(blockedModel.isCapturing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))

        // Once the original is persisted the owned temporary movie is released.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let released = try makeMovie()
        defer { try? FileManager.default.removeItem(at: released) }
        let unusable = CameraViewModel.RenderedPhoto(image: UIImage(), data: Data([0]), capturedAt: source.capturedAt)
        let result = await model.developCapturedPhotoForTesting(
            livePhoto(released), recipe: model.selectedRecipe, camera: camera, photoLibrary: saver,
            renderOverride: { unusable }
        )
        XCTAssertFalse(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: released.path))
        let inventory = try await store.inventory()
        XCTAssertEqual(inventory.documents.count, 1)
    }

    func testRenderStartsBeforeOriginalWriteOutcomeAndIsDiscardedWhenTheWriteFails() async throws {
        final class RenderCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func increment() { lock.lock(); value += 1; lock.unlock() }
            var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        }
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = CameraService.livePhotoTemporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let movie = directory.appendingPathComponent("\(UUID().uuidString).mov")
        try Data([1, 2, 3]).write(to: movie)
        defer { try? FileManager.default.removeItem(at: movie) }
        var liveSettings = ProCaptureSettings()
        liveSettings.livePhoto = true
        liveSettings.format = .heif
        liveSettings.resolution = .mp12
        XCTAssertNil(liveSettings.incompatibility)
        let source = try captureSourcePhoto()
        let live = CameraService.CapturedPhoto(
            fileData: source.fileData, capturedAt: source.capturedAt, dimensions: source.dimensions,
            livePhotoMovieURL: movie, outputSettings: liveSettings
        )

        // The original cannot be written (the store root is a plain file).
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0]).write(to: root)
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()
        let camera = CameraService()
        let counter = RenderCounter()
        let rendered = CameraViewModel.RenderedPhoto(image: UIImage(), data: Data([9]), capturedAt: source.capturedAt)

        let result = await model.developCapturedPhotoForTesting(
            live, recipe: model.selectedRecipe, camera: camera, photoLibrary: saver,
            renderOverride: { counter.increment(); return rendered }
        )
        XCTAssertFalse(result)
        // Sequential code only renders after the write succeeds, so 1 here proves the render was
        // launched before the write outcome was known. Its result must then be discarded.
        XCTAssertEqual(counter.count, 1, "the render must be launched before the original write outcome is known")
        XCTAssertTrue(saver.requests.isEmpty, "A discarded render must never reach the saver")
        XCTAssertFalse(model.isCapturing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path), "The Live movie must outlive a failed original write")

        // The explicit retry still persists the original and saves a developed photo.
        try FileManager.default.removeItem(at: root)
        model.capture(camera: camera, photoLibrary: saver)
        XCTAssertEqual(model.toastMessage, "Saving your earlier photo. No new photo is taken.")
        for _ in 0..<200 where saver.requests.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(saver.requests.count, 1, "saver requests after the explicit retry")
        XCTAssertFalse(try XCTUnwrap(saver.requests.first?.imageData).isEmpty, "The real retry render must hand the saver image data")
        let inventory = try await store.inventory()
        XCTAssertEqual(inventory.documents.count, 1, "The failed attempt must leave no document; the retry creates exactly one")
        saver.completeLast(with: .success(()))
        XCTAssertFalse(model.hasPendingCapture)
    }

    func testLivePhotoWithInstantPrintIsRefusedBeforeCapturing() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "proCaptureSettings.v1"
        let standard = UserDefaults.standard
        let previous = standard.data(forKey: key)
        var live = ProCaptureSettings()
        live.livePhoto = true
        live.format = .heif
        live.resolution = .mp12
        standard.set(try JSONEncoder().encode(live), forKey: key)
        defer {
            if let previous { standard.set(previous, forKey: key) } else { standard.removeObject(forKey: key) }
        }
        // Read the stored preference only after it is written.
        let camera = CameraService()
        defaults.set("instantPrint", forKey: "captureFinish")
        XCTAssertTrue(MembershipStore.shared.hasFullAccess)
        XCTAssertTrue(camera.proCaptureSettings.livePhoto)
        let model = CameraViewModel(defaults: defaults)
        let saver = ControlledPhotoSaver()

        model.capture(camera: camera, photoLibrary: saver)

        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.toastStyle, .error)
        XCTAssertEqual(model.toastMessage, "Live Photos require Photo finish. Turn off Instant Print before capturing.")
        XCTAssertTrue(saver.requests.isEmpty)
    }

    func testImportIsRefusedWhileACameraCaptureIsSavingOrAwaitsRetry() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CameraViewModel(defaults: defaults)
        let saver = ControlledPhotoSaver()
        let photo = try capturedPhoto()
        let importData = try XCTUnwrap(try capturedPhoto().image.jpegData(compressionQuality: 0.9))
        model.saveCapturedPhoto(photo, recipe: model.selectedRecipe, photoLibrary: saver)
        XCTAssertTrue(model.isSaving)

        await model.importPhoto(data: importData)
        XCTAssertTrue(model.hasPendingCapture)
        XCTAssertFalse(model.isReviewingImport)
        XCTAssertTrue(model.reviewImage === photo.image)
        XCTAssertFalse(model.isImporting)

        saver.completeLast(with: .failure(.accessDenied))
        XCTAssertFalse(model.isSaving)
        XCTAssertNotNil(model.saveErrorMessage)
        await model.importPhoto(data: importData)
        XCTAssertTrue(model.hasPendingCapture, "A failed capture save awaiting retry must survive an import")
        XCTAssertFalse(model.isReviewingImport)
        XCTAssertTrue(model.reviewImage === photo.image)
        XCTAssertFalse(model.isImporting)
    }

    func testImportLoadingCountsAsBusyUntilItEnds() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CameraViewModel(defaults: defaults)
        let saver = ControlledPhotoSaver()
        let camera = CameraService()
        let importData = try XCTUnwrap(try capturedPhoto().image.jpegData(compressionQuality: 0.9))

        model.beginImportLoading()
        XCTAssertTrue(model.isImporting)
        model.capture(camera: camera, photoLibrary: saver)
        XCTAssertFalse(model.isCapturing)
        model.saveCapturedPhoto(try capturedPhoto(), recipe: model.selectedRecipe, photoLibrary: saver)
        XCTAssertTrue(saver.requests.isEmpty)
        XCTAssertFalse(model.hasPendingCapture)

        await model.importPhoto(data: importData)
        XCTAssertTrue(model.isReviewingImport, "The import that is loading must still be able to apply")
        XCTAssertTrue(model.isImporting)
        model.endImportLoading()
        XCTAssertFalse(model.isImporting)
    }

    func testCaptureFailureMessageIgnoresIdleAndSuccessStatuses() {
        XCTAssertEqual(
            CameraViewModel.captureFailureMessage(status: "Start the camera before capturing."),
            "Capture could not be completed. Resume the camera and try again."
        )
        for status in ["", "Camera is ready", "Camera paused", "Photo captured"] {
            XCTAssertEqual(
                CameraViewModel.captureFailureMessage(status: status),
                "Capture could not be completed. Try again."
            )
        }
        XCTAssertEqual(
            CameraViewModel.captureFailureMessage(status: "The photo could not be processed."),
            "The photo could not be processed."
        )
    }

    func testErrorToastsOutlastSuccessAndInfoToasts() {
        XCTAssertGreaterThanOrEqual(CameraViewModel.toastDuration(for: .error), .seconds(6))
        XCTAssertEqual(CameraViewModel.toastDuration(for: .success), .seconds(2.4))
        XCTAssertEqual(CameraViewModel.toastDuration(for: .info), .seconds(2.4))
    }

    func testDevelopedCaptureCarriesShutterLocationAsGPS() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CameraViewModel(defaults: defaults, photoStore: FilmyPhotoStore(root: root))
        let saver = ControlledPhotoSaver()
        let source = try captureSourcePhoto()
        let photo = CameraService.CapturedPhoto(
            fileData: source.fileData, capturedAt: source.capturedAt, dimensions: source.dimensions,
            location: CLLocation(latitude: 37.5, longitude: -122.25)
        )

        let result = await model.developCapturedPhotoForTesting(
            photo, recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver
        )
        XCTAssertTrue(result)
        for _ in 0..<200 where saver.requests.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let request = try XCTUnwrap(saver.requests.last)
        let data = try XCTUnwrap(request.imageData)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitude as String] as? Double ?? 0, 37.5, accuracy: 0.0001)
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitudeRef as String] as? String, "N")
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitude as String] as? Double ?? 0, 122.25, accuracy: 0.0001)
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef as String] as? String, "W")
        saver.completeLast(with: .success(()))
    }

    // MARK: Owed Photos exports

    private func tempStoreRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func markerExists(_ store: FilmyPhotoStore, _ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: store.photosExportOwedURL(for: id).path)
    }

    /// An owed document made straight in the store, as a killed capture leaves it.
    private func createOwedDocument(
        _ store: FilmyPhotoStore, offset: TimeInterval, live: Bool = false,
        developed: Bool = true, owing: Bool = true
    ) async throws -> FilmyPhotoDocument {
        var settings = ProCaptureSettings.legacy
        var movie: URL?
        if live {
            settings = ProCaptureSettings()
            settings.livePhoto = true
            settings.format = .heif
            settings.resolution = .mp12
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
            try Data([1, 2, 3]).write(to: url)
            movie = url
        }
        defer { if let movie { try? FileManager.default.removeItem(at: movie) } }
        let source = try captureSourcePhoto()
        let geometry = FilmyRenderGeometry(
            viewportWidth: 100, viewportHeight: 100, previewWidth: 100, previewHeight: 100,
            grainSeed: 1, flashFired: false
        )
        let created = try await store.create(
            processed: source.fileData, raw: nil, liveMovieURL: movie,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000 + offset),
            geometry: geometry, recipe: FilmRecipe.builtIns[0], finish: .photo, settings: settings,
            owesPhotosExport: owing
        )
        guard developed else { return created }
        let first = try XCTUnwrap(created.currentRevision)
        return try await store.addRevision(
            created.id, expectedRevisionID: first.id, recipe: FilmRecipe.builtIns[0], finish: .photo,
            settings: settings, renderedData: try capturedPhoto().data
        )
    }

    func testDevelopedCaptureOwesPhotosExportUntilDiscarded() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()

        let result = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver
        )
        XCTAssertTrue(result)
        XCTAssertTrue(model.isSaving)
        let owed = await store.photosExportsOwed()
        let id = try XCTUnwrap(owed.first)
        XCTAssertEqual(owed.count, 1)
        XCTAssertTrue(markerExists(store, id))
        XCTAssertTrue(model.pendingPhotosExportIDs.isEmpty, "The capture in review is never offered as owed")

        saver.completeLast(with: .failure(.writeFailed))
        XCTAssertTrue(model.hasPendingCapture)
        XCTAssertTrue(markerExists(store, id), "A failed save keeps the export owed")

        model.discardReview()
        XCTAssertFalse(markerExists(store, id), "Discard clears the marker with no await")
        XCTAssertFalse(model.hasPendingCapture)
        let afterDiscard = await store.photosExportsOwed()
        XCTAssertTrue(afterDiscard.isEmpty)
        _ = try await store.loadDocument(id)
        await model.reconcilePendingPhotosExports()
        XCTAssertTrue(model.pendingPhotosExportIDs.isEmpty)
    }

    func testSuccessfulCaptureSaveClearsOwedMarker() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()

        let result = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver
        )
        XCTAssertTrue(result)
        let owed = await store.photosExportsOwed()
        let id = try XCTUnwrap(owed.first)
        XCTAssertTrue(markerExists(store, id))

        saver.completeLast(with: .success(()))
        XCTAssertFalse(model.isSaving)
        XCTAssertFalse(model.hasPendingCapture)
        XCTAssertFalse(markerExists(store, id))
        await model.reconcilePendingPhotosExports()
        XCTAssertTrue(model.owedPhotosExportIDs.isEmpty)
        XCTAssertTrue(model.pendingPhotosExportIDs.isEmpty)
        XCTAssertFalse(model.showsPendingPhotosExportsNotice)
    }

    func testUndevelopableCaptureStillOwesPhotosExport() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()

        // Render returns nothing: the original is kept and the export stays owed.
        let result = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver,
            renderOverride: { nil }
        )
        XCTAssertFalse(result)
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.toastStyle, .error)
        XCTAssertEqual(
            model.toastMessage,
            "Original retained in Filmy originals. Open it there to retry developing this look."
        )
        XCTAssertTrue(saver.requests.isEmpty)
        let owed = await store.photosExportsOwed()
        let id = try XCTUnwrap(owed.first)
        XCTAssertTrue(markerExists(store, id))
        // No reconcile call: the id was inserted in session.
        XCTAssertEqual(model.pendingPhotosExportIDs, [id])
        XCTAssertTrue(model.showsPendingPhotosExportsNotice)

        // The developed version cannot be stored: same outcome.
        let otherRoot = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStore = FilmyPhotoStore(root: otherRoot)
        let otherModel = CameraViewModel(defaults: defaults, photoStore: otherStore)
        let source = try captureSourcePhoto()
        let unusable = CameraViewModel.RenderedPhoto(image: UIImage(), data: Data([0]), capturedAt: source.capturedAt)
        let second = await otherModel.developCapturedPhotoForTesting(
            source, recipe: otherModel.selectedRecipe, camera: CameraService(), photoLibrary: saver,
            renderOverride: { unusable }
        )
        XCTAssertFalse(second)
        let otherOwed = await otherStore.photosExportsOwed()
        XCTAssertEqual(otherModel.pendingPhotosExportIDs, otherOwed)
        XCTAssertEqual(otherOwed.count, 1)
        otherModel.dismissToast()
        XCTAssertTrue(otherModel.showsPendingPhotosExportsNotice)
    }

    func testReconcileExcludesTheCaptureStillInReview() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()
        let older = try await createOwedDocument(store, offset: -100)

        let result = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver
        )
        XCTAssertTrue(result)
        let owed = await store.photosExportsOwed()
        XCTAssertEqual(owed.count, 2)
        let reviewed = try XCTUnwrap(owed.first(where: { $0 != older.id }))

        await model.reconcilePendingPhotosExports()
        XCTAssertTrue(model.owedPhotosExportIDs.contains(reviewed), "The raw list holds the capture in review")
        XCTAssertEqual(model.pendingPhotosExportIDs, [older.id], "The view never sees the capture in review")
        XCTAssertFalse(model.showsPendingPhotosExportsNotice, "No notice while a save is running")

        saver.completeLast(with: .success(()))
        await model.reconcilePendingPhotosExports()
        XCTAssertEqual(model.pendingPhotosExportIDs, [older.id])
        XCTAssertTrue(model.showsPendingPhotosExportsNotice)
    }

    func testStaleReconcileResultIsDropped() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let document = try await createOwedDocument(store, offset: 0)

        // The first reconcile reads [document]. Before it publishes, the
        // document is linked and a newer reconcile publishes []. The older
        // result must then be dropped, not published over the newer one.
        model.afterOwedReadForTesting = { [unowned model] in
            try? await store.linkPhotosAsset("A/L0/stale", to: document.id)
            await model.reconcilePendingPhotosExports()
        }
        await model.reconcilePendingPhotosExports()

        XCTAssertNil(model.afterOwedReadForTesting)
        XCTAssertTrue(model.owedPhotosExportIDs.isEmpty)
        XCTAssertTrue(model.pendingPhotosExportIDs.isEmpty)
    }

    func testSavePendingPhotosExportsExportsEachOnceAndNeverDiscardedOrLegacy() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let undeveloped = try await createOwedDocument(store, offset: 1, developed: false)
        let developed = try await createOwedDocument(store, offset: 2)
        let discarded = try await createOwedDocument(store, offset: 3)
        store.clearPhotosExportOwed(discarded.id)
        let legacy = try await createOwedDocument(store, offset: 4, owing: false)
        XCTAssertNil(undeveloped.currentRevision?.renditionFilename)
        let stub = PendingExportStub(store: store)

        await model.savePendingPhotosExports(photoLibrary: nil, export: { id in try await stub.export(id) })

        XCTAssertEqual(stub.calls, [undeveloped.id, developed.id])
        XCTAssertFalse(stub.calls.contains(discarded.id))
        XCTAssertFalse(stub.calls.contains(legacy.id))
        let gained = try await store.loadDocument(undeveloped.id)
        XCTAssertNotNil(gained.currentRevision?.renditionFilename, "An undeveloped capture is developed before export")
        XCTAssertFalse(gained.photosAssetIdentifier?.isEmpty ?? true)
        XCTAssertFalse(model.isSavingPendingExports)
        XCTAssertEqual(model.toastStyle, .success)
        XCTAssertEqual(model.toastMessage, "Saved 2 photos to Photos")
        XCTAssertTrue(model.pendingPhotosExportIDs.isEmpty)

        await model.savePendingPhotosExports(photoLibrary: nil, export: { id in try await stub.export(id) })
        XCTAssertEqual(stub.calls.count, 2, "A second run makes no export calls")
    }

    func testSavePendingSkipsIdsNoLongerOwed() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let first = try await createOwedDocument(store, offset: 1)
        let linkedLater = try await createOwedDocument(store, offset: 2)
        let deletedLater = try await createOwedDocument(store, offset: 3)
        let stub = PendingExportStub(store: store)
        // While the first export runs, the other two leave the owed list.
        stub.afterFirstExport = {
            try? await store.linkPhotosAsset("A/L0/elsewhere", to: linkedLater.id)
            try? await store.delete(deletedLater.id)
        }

        await model.savePendingPhotosExports(photoLibrary: nil, export: { id in try await stub.export(id) })

        XCTAssertEqual(stub.calls, [first.id])
        XCTAssertEqual(model.toastStyle, .success)
        XCTAssertEqual(model.toastMessage, "Saved 1 photo to Photos", "A stale id is skipped, never counted failed")
        XCTAssertTrue(model.pendingPhotosExportIDs.isEmpty)
    }

    func testSavePendingSkipsLiveNeedingFullAccessAndExportsStills() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let live = try await createOwedDocument(store, offset: 1, live: true)
        let stillOne = try await createOwedDocument(store, offset: 2)
        let stillTwo = try await createOwedDocument(store, offset: 3)
        XCTAssertTrue(live.hasLivePhoto)
        let stub = PendingExportStub(store: store)
        stub.accessDenied = [live.id]

        await model.savePendingPhotosExports(photoLibrary: nil, export: { id in try await stub.export(id) })

        XCTAssertEqual(stub.calls, [live.id, stillOne.id, stillTwo.id])
        XCTAssertEqual(model.fullAccessBlockedIDs, [live.id])
        XCTAssertEqual(model.pendingPhotosExportIDs, [live.id])
        XCTAssertTrue(model.pendingExportsAwaitFullAccessOnly)
        XCTAssertFalse(model.isSavingPendingExports)
        XCTAssertEqual(model.toastStyle, .error)
        XCTAssertEqual(model.toastMessage, "1 Live Photo needs full Photos access. Allow it in Settings.")
        for id in [stillOne.id, stillTwo.id] {
            let document = try await store.loadDocument(id)
            XCTAssertFalse(document.photosAssetIdentifier?.isEmpty ?? true)
        }
    }

    func testSavePendingStopsWhenAddOnlyAccessIsRefused() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let first = try await createOwedDocument(store, offset: 1)
        let second = try await createOwedDocument(store, offset: 2)
        let third = try await createOwedDocument(store, offset: 3)
        let stub = PendingExportStub(store: store)
        stub.accessDenied = [first.id]

        await model.savePendingPhotosExports(photoLibrary: nil, export: { id in try await stub.export(id) })

        XCTAssertEqual(stub.calls, [first.id], "A refused still stops the run")
        XCTAssertFalse(model.isSavingPendingExports)
        XCTAssertTrue(model.fullAccessBlockedIDs.isEmpty)
        XCTAssertEqual(model.toastStyle, .error)
        XCTAssertEqual(model.toastMessage, "Photo access is needed to save these photos. Allow it in Settings.")
        XCTAssertEqual(model.pendingPhotosExportIDs, [first.id, second.id, third.id])
    }

    func testPendingExportsSummaryWordsEachOutcome() {
        func summary(
            saved: Int = 0, failed: Int = 0, live: Int = 0, stopped: Bool = false
        ) -> (message: String, isError: Bool)? {
            CameraViewModel.pendingExportsSummary(
                saved: saved, failed: failed, needsFullAccess: live, stoppedForAccess: stopped
            )
        }
        XCTAssertNil(summary())
        XCTAssertEqual(summary(saved: 1)?.message, "Saved 1 photo to Photos")
        XCTAssertEqual(summary(saved: 3)?.message, "Saved 3 photos to Photos")
        XCTAssertEqual(summary(saved: 3)?.isError, false)
        XCTAssertEqual(summary(failed: 1)?.message, "1 photo could not be saved. It stays in Filmy originals.")
        XCTAssertEqual(summary(saved: 2, failed: 2)?.message, "2 photos could not be saved. They stay in Filmy originals.")
        XCTAssertEqual(summary(failed: 1)?.isError, true)
        XCTAssertEqual(summary(live: 1)?.message, "1 Live Photo needs full Photos access. Allow it in Settings.")
        XCTAssertEqual(summary(live: 2)?.message, "2 Live Photos need full Photos access. Allow it in Settings.")
        XCTAssertEqual(summary(failed: 1, live: 2)?.message, "2 Live Photos need full Photos access. Allow it in Settings.")
        XCTAssertEqual(summary(live: 1)?.isError, true)
        XCTAssertEqual(
            summary(saved: 1, failed: 1, live: 1, stopped: true)?.message,
            "Photo access is needed to save these photos. Allow it in Settings."
        )
        XCTAssertEqual(summary(stopped: true)?.isError, true)
        XCTAssertEqual(CameraViewModel.pendingExportsTitle(count: 1), "1 photo is not in Photos yet")
        XCTAssertEqual(CameraViewModel.pendingExportsTitle(count: 2), "2 photos are not in Photos yet")

        let messages: [String] = [
            summary(saved: 1), summary(saved: 3), summary(failed: 1), summary(failed: 2), summary(live: 1),
            summary(live: 2), summary(stopped: true)
        ].compactMap { $0?.message } + [
            CameraViewModel.pendingExportsTitle(count: 1), CameraViewModel.pendingExportsTitle(count: 2)
        ]
        XCTAssertEqual(messages.count, 9)
        for message in messages {
            let lowered = message.lowercased()
            for word in ["button", "tap", "show", "later"] {
                XCTAssertFalse(lowered.contains(word), "\(message) names \(word)")
            }
        }
    }

    func testPendingExportsNoticeLaterHidesForSessionOnly() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        _ = try await createOwedDocument(store, offset: 1)

        XCTAssertFalse(model.showsPendingPhotosExportsNotice, "Nothing is read until a reconcile")
        await model.reconcilePendingPhotosExports()
        XCTAssertTrue(model.showsPendingPhotosExportsNotice)
        XCTAssertFalse(model.pendingExportsNoticeDismissed)

        model.dismissPendingPhotosExportsNotice()
        XCTAssertTrue(model.pendingExportsNoticeDismissed)
        XCTAssertFalse(model.showsPendingPhotosExportsNotice)
        await model.reconcilePendingPhotosExports()
        XCTAssertFalse(model.showsPendingPhotosExportsNotice, "Later holds for the rest of the session")
        XCTAssertEqual(model.pendingPhotosExportIDs.count, 1, "The photo is still owed")

        // A cold launch reads the same durable marker and shows the notice again.
        let relaunched = CameraViewModel(defaults: defaults, photoStore: store)
        await relaunched.reconcilePendingPhotosExports()
        XCTAssertFalse(relaunched.pendingExportsNoticeDismissed)
        XCTAssertTrue(relaunched.showsPendingPhotosExportsNotice)
    }

    func testCaptureHoldsBackgroundTimeUntilSaveCompletes() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()
        let camera = CameraService()
        XCTAssertFalse(model.holdsCaptureBackgroundTimeForTesting)

        let first = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: camera, photoLibrary: saver
        )
        XCTAssertTrue(first)
        XCTAssertTrue(model.isSaving)
        XCTAssertTrue(model.holdsCaptureBackgroundTimeForTesting, "Held while the Photos save is pending")
        saver.completeLast(with: .success(()))
        XCTAssertFalse(model.isSaving)
        XCTAssertFalse(model.holdsCaptureBackgroundTimeForTesting)

        let second = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: camera, photoLibrary: saver
        )
        XCTAssertTrue(second)
        XCTAssertTrue(model.holdsCaptureBackgroundTimeForTesting)
        saver.completeLast(with: .failure(.writeFailed))
        XCTAssertFalse(model.isSaving)
        XCTAssertFalse(model.holdsCaptureBackgroundTimeForTesting, "A failed save releases it; the recovery card keeps the copy")
        model.discardReview()
        XCTAssertFalse(model.holdsCaptureBackgroundTimeForTesting)
    }

    func testCaptureRenderInterruptedByBackgroundIsRedoneInForeground() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        let saver = ControlledPhotoSaver()
        let renders = PendingRenderCounter()
        let hookCalls = PendingRenderCounter()
        let rendered = try capturedPhoto()
        // The first render ends with a trip to the background and back.
        model.afterCaptureRenderForTesting = { [unowned model] in
            hookCalls.increment()
            if hookCalls.count == 1 {
                model.sceneDidChange(.background)
                model.sceneDidChange(.active)
            }
        }

        let result = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver,
            renderOverride: { renders.increment(); return rendered }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(renders.count, 2, "The suspect render is discarded and rerun in the foreground")
        XCTAssertEqual(hookCalls.count, 2)
        XCTAssertEqual(model.backgroundEntryCount, 1)
        XCTAssertEqual(saver.requests.count, 1, "Exactly one save is attempted")
        let owed = await store.photosExportsOwed()
        let id = try XCTUnwrap(owed.first)
        XCTAssertTrue(markerExists(store, id), "Owed until the save succeeds")
        saver.completeLast(with: .success(()))
        XCTAssertFalse(markerExists(store, id))
    }

    func testCaptureRedoWaitsForSceneToBecomeActive() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilmyPhotoStore(root: root)
        let model = CameraViewModel(defaults: defaults, photoStore: store)
        model.isApplicationBackgroundedForTesting = { false }
        let saver = ControlledPhotoSaver()
        let renders = PendingRenderCounter()
        let rendersWhenActive = PendingRenderCounter()
        let hookCalls = PendingRenderCounter()
        let rendered = try capturedPhoto()
        // The scene goes to the background and only comes back later.
        model.afterCaptureRenderForTesting = { [unowned model] in
            hookCalls.increment()
            guard hookCalls.count == 1 else { return }
            model.sceneDidChange(.background)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                for _ in 0..<renders.count { rendersWhenActive.increment() }
                model.sceneDidChange(.active)
            }
        }

        let result = await model.developCapturedPhotoForTesting(
            try captureSourcePhoto(), recipe: model.selectedRecipe, camera: CameraService(), photoLibrary: saver,
            renderOverride: { renders.increment(); return rendered }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(rendersWhenActive.count, 1, "The redo waited for the scene to become active")
        XCTAssertEqual(renders.count, 2)
        XCTAssertEqual(model.pendingSceneWaiterCountForTesting, 0)
        XCTAssertEqual(saver.requests.count, 1)
    }

    private func capturedPhoto() throws -> CameraViewModel.RenderedPhoto {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 16)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 16))
        }
        return CameraViewModel.RenderedPhoto(
            image: image, data: try XCTUnwrap(image.jpegData(compressionQuality: 0.9)),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
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

/// Stands in for the Photos exporter: records calls and links like production.
@MainActor
final class PendingExportStub {
    private let store: FilmyPhotoStore
    private(set) var calls: [UUID] = []
    var accessDenied: Set<UUID> = []
    /// Runs once, inside the first export call, after it linked its document.
    var afterFirstExport: (@MainActor () async -> Void)?

    init(store: FilmyPhotoStore) {
        self.store = store
    }

    func export(_ id: UUID) async throws -> String {
        calls.append(id)
        if accessDenied.contains(id) { throw FilmyPhotosExporter.ExportError.accessDenied }
        let identifier = "A/L0/\(calls.count)"
        try await store.linkPhotosAsset(identifier, to: id)
        if let hook = afterFirstExport {
            afterFirstExport = nil
            await hook()
        }
        return identifier
    }
}

final class PendingRenderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
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

final class LookLibraryTests: XCTestCase {
    @MainActor
    func testSamplePreviewUsesTheBundledDemoAndActualRecipeRenderer() async throws {
        let original = try XCTUnwrap(UIImage(named: "LookPreviewCafe")?.cgImage)
        let bounds = CGRect(x: 0, y: 0, width: 384, height: 512)
        let framed = CameraFrameLayout.aspectFill(CIImage(cgImage: original), in: bounds)
        let small = try XCTUnwrap(FilmRenderer.outputCGImage(framed, from: bounds))
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "classic-chrome" })
        let expected = try XCTUnwrap(FilmRenderer.previewThumbnail(for: recipe, over: CIImage(cgImage: small)))
        let renderer = RecipeSwatchRenderer()
        let rendered = await renderer.render(recipe: recipe)
        let actual = try XCTUnwrap(rendered)
        XCTAssertEqual(actual.cgImage?.width, 384)
        XCTAssertEqual(actual.cgImage?.height, 512)
        XCTAssertEqual(actual.pngData(), expected.pngData(), "A swatch must show the real recipe, not a decorative grade")
    }

    @MainActor
    func testSamplePreviewCacheSeparatesCustomizedRecipes() async throws {
        let renderer = RecipeSwatchRenderer()
        let recipe = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "classic-chrome" })
        let firstRender = await renderer.render(recipe: recipe)
        let first = try XCTUnwrap(firstRender)
        let repeated = await renderer.render(recipe: recipe)
        XCTAssertTrue(first === repeated)
        var edited = recipe
        edited.exposure = 1.5
        let editedRender = await renderer.render(recipe: edited)
        let changed = try XCTUnwrap(editedRender)
        XCTAssertFalse(first === changed)
        XCTAssertNotEqual(first.pngData(), changed.pngData())
    }

    func testFavoritesRoundTripStableIDsAndDeterministicEncoding() {
        let ids: Set<String> = ["g7x-compact", "classic-chrome", "acros-monochrome"]
        XCTAssertEqual(LookLibraryIndex.favorites(from: LookLibraryIndex.encodeFavorites(ids)), ids)
        XCTAssertEqual(LookLibraryIndex.encodeFavorites(ids), LookLibraryIndex.encodeFavorites(Set(ids.reversed())))
    }

    func testMalformedFavoritesRecoverWithoutDiscardingTheCatalog() {
        for data in [Data(), Data("not json".utf8), Data("{}".utf8), Data(repeating: 0, count: 262_145)] {
            XCTAssertTrue(LookLibraryIndex.favorites(from: data).isEmpty)
        }
        XCTAssertEqual(
            LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "", filter: .all, favorites: []).count,
            FilmRecipe.builtIns.count
        )
    }

    func testDuplicateAndInvalidFavoriteIDsAreNormalized() {
        let data = Data("[\"classic-chrome\",\"classic-chrome\",\"\"]".utf8)
        XCTAssertEqual(LookLibraryIndex.favorites(from: data), ["classic-chrome"])
        let longID = String(repeating: "x", count: 257)
        let encoded = LookLibraryIndex.encodeFavorites(["classic-chrome", longID, ""])
        XCTAssertEqual(LookLibraryIndex.favorites(from: encoded), ["classic-chrome"])
    }

    func testFavoriteLimitRemainsReadableByTheDecoder() {
        let ids = Set((0..<512).map { String(repeating: "x", count: 240) + String($0) })
        let encoded = LookLibraryIndex.encodeFavorites(ids)
        XCTAssertEqual(LookLibraryIndex.favorites(from: encoded), ids)
    }

    func testFiltersPartitionTheEntireCatalogWithoutLosingSepia() {
        let compact = LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "", filter: .compact, favorites: [])
        let film = LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "", filter: .film, favorites: [])
        let mono = LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "", filter: .monochrome, favorites: [])
        let allIDs = (compact + film + mono).map(\.id)
        XCTAssertEqual(Set(allIDs), Set(FilmRecipe.builtIns.map(\.id)))
        XCTAssertEqual(allIDs.count, Set(allIDs).count)
        XCTAssertTrue(compact.allSatisfy { $0.isDigitalCameraStyle })
        XCTAssertTrue(mono.contains { $0.filmBase == .sepia })
        XCTAssertFalse(film.contains { $0.filmBase.monochromeFilter != nil || $0.filmBase == .sepia })
    }

    func testSearchHandlesCaseWhitespaceAndMissingMatches() {
        let results = LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "  MuTeD   CoLoR \n", filter: .all, favorites: [])
        XCTAssertTrue(results.contains { $0.id == "classic-chrome" })
        XCTAssertTrue(LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "no-such-look-987", filter: .all, favorites: []).isEmpty)
    }

    func testFavoritesIntersectSearchAndIgnoreUnknownIDs() {
        let ids: Set<String> = ["classic-chrome", "missing-recipe"]
        let favoriteResults = LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "", filter: .favorites, favorites: ids)
        XCTAssertEqual(favoriteResults.map(\.id), ["classic-chrome"])
        XCTAssertTrue(LookLibraryIndex.results(in: FilmRecipe.builtIns, query: "G7", filter: .favorites, favorites: ids).isEmpty)
    }

    func testDiscoveryPreservesEffectiveRecipeControlsAndCatalogOrder() throws {
        var customized = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "classic-chrome" })
        customized.exposure = 0.75
        let compact = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let input = [customized, compact]
        let results = LookLibraryIndex.results(in: input, query: "", filter: .all, favorites: [])
        XCTAssertEqual(results.map(\.id), [compact.id, customized.id])
        XCTAssertEqual(results[1], customized)
        XCTAssertEqual(input[0], customized, "Browsing must not mutate or reset the user's tuned recipe")
    }
}
