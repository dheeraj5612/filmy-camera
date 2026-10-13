import CoreMedia
import CoreImage
import CoreLocation
import ImageIO
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
        let model = CameraViewModel(defaults: defaults, photoStore: FilmyPhotoStore(root: root))
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
        for _ in 0..<100 where model.isCapturing { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.isCapturing)
        XCTAssertNotEqual(model.toastMessage, "Saving your earlier photo. No new photo is taken.")
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
