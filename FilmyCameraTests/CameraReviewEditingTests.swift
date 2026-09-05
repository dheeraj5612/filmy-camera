import Combine
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import FilmyCamera

@MainActor
final class CameraReviewEditingTests: XCTestCase {
    func testLookEditDefersFullRenderUntilSaveAndFreezesSaveDescriptor() async throws {
        let sourceData = try orientedQuadrantJPEG(orientation: 6)
        let previewProbe = RenderProbe<CameraViewModel.ReviewPreview> { source, recipe, _ in
            Self.preview(source: source, recipe: recipe)
        }
        let fullProbe = RenderProbe<CameraViewModel.RenderedPhoto> { source, recipe, _ in
            Self.fullRender(source: source, recipe: recipe)
        }
        let (viewModel, defaults, suite) = try makeViewModel(
            previewRenderer: previewProbe.call,
            fullRenderer: fullProbe.call
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let initialRecipe = try recipe(id: "classic-chrome")
        let editedRecipe = try recipe(id: "acros-monochrome")
        viewModel.select(recipe: initialRecipe)
        await viewModel.importPhoto(data: sourceData)

        let initialReview = try XCTUnwrap(viewModel.reviewImage)
        let saver = ControlledPhotoSaver()
        viewModel.applyReviewRecipe(editedRecipe)
        await viewModel.waitForReviewWorkToDrainForTesting()

        XCTAssertEqual(previewProbe.recipeIDs, [editedRecipe.id])
        XCTAssertTrue(fullProbe.recipeIDs.isEmpty, "Auditioning a look must not render or encode the full source")
        XCTAssertEqual(viewModel.reviewRecipe, editedRecipe)
        XCTAssertEqual(viewModel.selectedRecipeID, initialRecipe.id)
        XCTAssertFalse(viewModel.isRenderingReview)
        XCTAssertNil(viewModel.pendingReviewRecipeID)
        XCTAssertFalse(viewModel.reviewImage === initialReview)

        viewModel.saveReview(photoLibrary: saver)
        XCTAssertTrue(viewModel.isSaving)
        viewModel.applyReviewRecipe(initialRecipe)
        viewModel.discardReview()
        await viewModel.waitForReviewWorkToDrainForTesting()

        let request = try XCTUnwrap(saver.requests.last)
        let outputData = try XCTUnwrap(request.imageData)
        XCTAssertEqual(fullProbe.recipeIDs, [editedRecipe.id])
        XCTAssertEqual(request.recipe, editedRecipe)
        XCTAssertEqual(request.capturedAt, fullProbe.capturedDates.single)
        XCTAssertEqual(viewModel.reviewRecipe, editedRecipe, "The review must stay frozen while its save is in flight")
        try assertUprightDimensions(data: outputData, width: 40, height: 80)
        XCTAssertEqual(try provenanceRecipeID(in: outputData), editedRecipe.id)

        saver.completeLast(with: .failure(.writeFailed))
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNotNil(viewModel.reviewImage)
        viewModel.saveReview(photoLibrary: saver)
        let retry = try XCTUnwrap(saver.requests.last)
        XCTAssertEqual(retry.imageData, request.imageData)
        XCTAssertEqual(retry.recipe, request.recipe)
        XCTAssertEqual(retry.capturedAt, request.capturedAt)
    }

    func testOriginalPreviewIsBoundedAndDoesNotChangeCachedSave() async throws {
        let sourceData = try wideJPEG(width: 2_000, height: 1_000, orientation: 6)
        let (viewModel, defaults, suite) = try makeViewModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let selected = try recipe(id: "provia-standard")
        viewModel.select(recipe: selected)
        await viewModel.importPhoto(data: sourceData)
        let saver = ControlledPhotoSaver()
        viewModel.saveReview(photoLibrary: saver)
        let before = try XCTUnwrap(saver.requests.last)
        saver.completeLast(with: .failure(.writeFailed))

        await viewModel.prepareReviewOriginal()

        let original = try XCTUnwrap(viewModel.reviewOriginalImage?.cgImage)
        XCTAssertLessThanOrEqual(max(original.width, original.height), 1_800)
        XCTAssertEqual(Double(original.height) / Double(original.width), 2, accuracy: 0.01)
        XCTAssertEqual(viewModel.reviewRecipe, selected)
        XCTAssertFalse(viewModel.isPreparingReviewOriginal)

        viewModel.saveReview(photoLibrary: saver)
        let after = try XCTUnwrap(saver.requests.last)
        XCTAssertEqual(after.imageData, before.imageData)
        XCTAssertEqual(after.recipe, before.recipe)
        XCTAssertEqual(after.capturedAt, before.capturedAt)
    }

    func testRapidLookChangesAreSerializedLatestWinsAndSaveIsGuarded() async throws {
        let blocker = BlockingPreviewRenderer()
        let (viewModel, defaults, suite) = try makeViewModel(previewRenderer: blocker.call)
        defer {
            blocker.releaseAll()
            defaults.removePersistentDomain(forName: suite)
        }
        let initial = try recipe(id: "provia-standard")
        let first = try recipe(id: "classic-chrome")
        let replaced = try recipe(id: "velvia-vivid")
        let latest = try recipe(id: "acros-monochrome")
        viewModel.select(recipe: initial)
        await viewModel.importPhoto(data: try orientedQuadrantJPEG(orientation: 1))

        let firstStarted = expectation(description: "first preview started")
        blocker.setOnStart { id in
            if id == first.id { firstStarted.fulfill() }
        }
        viewModel.applyReviewRecipe(first)
        await fulfillment(of: [firstStarted], timeout: 2)
        viewModel.applyReviewRecipe(replaced)
        viewModel.applyReviewRecipe(latest)
        let saver = ControlledPhotoSaver()
        viewModel.saveReview(photoLibrary: saver)
        XCTAssertTrue(saver.requests.isEmpty)

        let latestStarted = expectation(description: "latest preview started")
        blocker.setOnStart { id in
            if id == latest.id { latestStarted.fulfill() }
        }
        blocker.releaseNext()
        await fulfillment(of: [latestStarted], timeout: 2)
        blocker.releaseNext()
        await viewModel.waitForReviewWorkToDrainForTesting()

        XCTAssertEqual(blocker.recipeIDs, [first.id, latest.id])
        XCTAssertEqual(blocker.maximumConcurrentCalls, 1)
        XCTAssertEqual(viewModel.reviewRecipe, latest)
        XCTAssertFalse(viewModel.isRenderingReview)
    }

    func testDiscardResumesQueuedOriginalAndStalePreviewCannotRestoreReview() async throws {
        let blocker = BlockingPreviewRenderer()
        let (viewModel, defaults, suite) = try makeViewModel(previewRenderer: blocker.call)
        defer {
            blocker.releaseAll()
            defaults.removePersistentDomain(forName: suite)
        }
        let initial = try recipe(id: "provia-standard")
        let edited = try recipe(id: "classic-chrome")
        viewModel.select(recipe: initial)
        await viewModel.importPhoto(data: try orientedQuadrantJPEG(orientation: 1))

        let previewStarted = expectation(description: "preview started")
        blocker.setOnStart { _ in previewStarted.fulfill() }
        viewModel.applyReviewRecipe(edited)
        await fulfillment(of: [previewStarted], timeout: 2)
        viewModel.applyReviewRecipe(initial)

        let originalBecamePending = expectation(description: "original became pending")
        var observation: AnyCancellable?
        observation = viewModel.$isPreparingReviewOriginal
            .dropFirst()
            .filter { $0 }
            .sink { _ in originalBecamePending.fulfill() }
        let originalTask = Task { @MainActor in
            await viewModel.prepareReviewOriginal()
        }
        await fulfillment(of: [originalBecamePending], timeout: 2)

        viewModel.discardReview()
        await originalTask.value
        observation?.cancel()
        XCTAssertNil(viewModel.reviewImage)
        XCTAssertNil(viewModel.reviewOriginalImage)
        XCTAssertFalse(viewModel.isPreparingReviewOriginal)

        blocker.releaseNext()
        await viewModel.waitForReviewWorkToDrainForTesting()
        XCTAssertNil(viewModel.reviewImage, "A completed stale render must not resurrect a discarded review")
        XCTAssertNil(viewModel.reviewRecipe)
    }

    func testRenderFailuresPreserveReviewSettleFlagsAndAllowRetry() async throws {
        let initial = try recipe(id: "provia-standard")
        let failingPreview = try recipe(id: "velvia-vivid")
        let successfulPreview = try recipe(id: "classic-chrome")
        let fullProbe = RenderProbe<CameraViewModel.RenderedPhoto> { _, _, _ in nil }
        let (viewModel, defaults, suite) = try makeViewModel(
            previewRenderer: { source, recipe, _ in
                recipe.id == failingPreview.id ? nil : Self.preview(source: source, recipe: recipe)
            },
            fullRenderer: fullProbe.call,
            originalRenderer: { _ in nil }
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        viewModel.select(recipe: initial)
        await viewModel.importPhoto(data: try orientedQuadrantJPEG(orientation: 1))
        let validReview = try XCTUnwrap(viewModel.reviewImage)

        viewModel.applyReviewRecipe(failingPreview)
        await viewModel.waitForReviewWorkToDrainForTesting()
        XCTAssertTrue(viewModel.reviewImage === validReview)
        XCTAssertEqual(viewModel.reviewRecipe, initial)
        XCTAssertFalse(viewModel.isRenderingReview)
        XCTAssertNotNil(viewModel.reviewRenderErrorMessage)

        await viewModel.prepareReviewOriginal()
        XCTAssertNil(viewModel.reviewOriginalImage)
        XCTAssertFalse(viewModel.isPreparingReviewOriginal)
        XCTAssertTrue(viewModel.reviewImage === validReview)
        XCTAssertNotNil(viewModel.reviewRenderErrorMessage)

        viewModel.applyReviewRecipe(successfulPreview)
        await viewModel.waitForReviewWorkToDrainForTesting()
        let editedReview = try XCTUnwrap(viewModel.reviewImage)
        let saver = ControlledPhotoSaver()
        viewModel.saveReview(photoLibrary: saver)
        await viewModel.waitForReviewWorkToDrainForTesting()
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertTrue(saver.requests.isEmpty)
        XCTAssertTrue(viewModel.reviewImage === editedReview)
        XCTAssertEqual(viewModel.reviewRecipe, successfulPreview)
        XCTAssertNotNil(viewModel.reviewRenderErrorMessage)

        viewModel.saveReview(photoLibrary: saver)
        await viewModel.waitForReviewWorkToDrainForTesting()
        XCTAssertEqual(fullProbe.recipeIDs, [successfulPreview.id, successfulPreview.id])
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertTrue(saver.requests.isEmpty)
    }

    func testCameraSourceRendersPreserveCropOrientationFlashDateAndSubjectMapping() throws {
        let sourceData = try orientedQuadrantJPEG(orientation: 6)
        let capturedAt = Date(timeIntervalSince1970: 1_725_552_645)
        let normalizedFace = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4)
        let source = CameraViewModel.ReviewRenderSource(
            data: sourceData,
            capturedAt: capturedAt,
            mode: .camera(
                viewportSize: CGSize(width: 2, height: 3),
                previewDrawableSize: CGSize(width: 400, height: 600),
                flashFired: true,
                grainSeed: 0x17A3
            ),
            normalizedSubjectRegions: [normalizedFace]
        )
        let recipe = try recipe(id: "g7x-compact")

        let original = try XCTUnwrap(CameraViewModel.renderReviewOriginal(source: source))
        let preview = try XCTUnwrap(
            CameraViewModel.renderReviewPreview(source: source, recipe: recipe)
        )
        let full = try XCTUnwrap(
            CameraViewModel.renderReviewFull(source: source, recipe: recipe)
        )

        let originalCG = try XCTUnwrap(original.cgImage)
        XCTAssertEqual(originalCG.width, 40)
        XCTAssertEqual(originalCG.height, 60)
        XCTAssertEqual(
            try quadrantColors(in: originalCG),
            [.blue, .red, .yellow, .green],
            "The camera review must apply EXIF orientation before its portrait aspect-fill crop"
        )
        XCTAssertEqual(preview.image.cgImage?.width, 40)
        XCTAssertEqual(preview.image.cgImage?.height, 60)
        XCTAssertTrue(preview.isFullResolution)
        XCTAssertTrue(preview.flashFired)
        assertRegion(preview.normalizedSubjectRegions?.single, equals: normalizedFace)

        XCTAssertEqual(full.image.size.width / full.image.size.height, 2.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(full.capturedAt, capturedAt)
        XCTAssertTrue(full.flashFired)
        assertRegion(full.normalizedSubjectRegions?.single, equals: normalizedFace)
        try assertUprightDimensions(data: full.data, width: 40, height: 60)
    }

    func testActualMaxGrainEditMatchesDirectSameSourceRenderAndReusesCachedLook() async throws {
        let sourceData = try orientedQuadrantJPEG(orientation: 6)
        var maxGrain = try recipe(id: "g7x-compact")
        maxGrain.grain = FilmRecipe.Control.grain.editorRange.upperBound
        maxGrain.grainSize = FilmRecipe.Control.grainSize.editorRange.upperBound

        let (direct, directDefaults, directSuite) = try makeViewModel()
        defer { directDefaults.removePersistentDomain(forName: directSuite) }
        direct.update(recipe: maxGrain)
        direct.select(recipe: maxGrain)
        await direct.importPhoto(data: sourceData)
        let directSaver = ControlledPhotoSaver()
        direct.saveReview(photoLibrary: directSaver)
        let directData = try XCTUnwrap(directSaver.requests.single?.imageData)

        let (edited, editedDefaults, editedSuite) = try makeViewModel()
        defer { editedDefaults.removePersistentDomain(forName: editedSuite) }
        let initial = try recipe(id: "classic-chrome")
        edited.select(recipe: initial)
        await edited.importPhoto(data: sourceData)
        let cachedInitialImage = try XCTUnwrap(edited.reviewImage)
        edited.applyReviewRecipe(maxGrain)
        await edited.waitForReviewWorkToDrainForTesting()
        edited.applyReviewRecipe(initial)
        XCTAssertTrue(edited.reviewImage === cachedInitialImage)
        XCTAssertEqual(edited.reviewRecipe, initial)
        XCTAssertFalse(edited.isRenderingReview)
        edited.applyReviewRecipe(maxGrain)
        await edited.waitForReviewWorkToDrainForTesting()
        let editedSaver = ControlledPhotoSaver()
        edited.saveReview(photoLibrary: editedSaver)
        await edited.waitForReviewWorkToDrainForTesting()
        let editedData = try XCTUnwrap(editedSaver.requests.single?.imageData)

        XCTAssertEqual(try decodedPixels(from: editedData), try decodedPixels(from: directData))
    }

    func testInstantPrintUsesFullSourceAndSameRecipeSaveDoesNotReusePlainBytes() async throws {
        let (model, defaults, suite) = try makeViewModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.select(recipe: try recipe(id: "provia-standard"))
        await model.importPhoto(data: try orientedQuadrantJPEG(orientation: 6))
        let saver = ControlledPhotoSaver()
        model.saveReview(photoLibrary: saver)
        let plain = try XCTUnwrap(saver.requests.last?.imageData)
        saver.completeLast(with: .failure(.writeFailed))

        model.applyReviewFinish(.instantPrint)
        await model.waitForReviewWorkToDrainForTesting()
        XCTAssertEqual(model.reviewFinish, .instantPrint)
        XCTAssertEqual(model.reviewImage?.cgImage?.width, 44)
        XCTAssertEqual(model.reviewImage?.cgImage?.height, 87)
        await model.prepareReviewOriginal()
        XCTAssertEqual(model.reviewOriginalImage?.cgImage?.width, 40)
        XCTAssertEqual(model.reviewOriginalImage?.cgImage?.height, 80)
        XCTAssertEqual(model.reviewFinish, .instantPrint, "Original is a comparison, not an export edit")

        model.saveReview(photoLibrary: saver)
        model.applyReviewFinish(.photo)
        await model.waitForReviewWorkToDrainForTesting()
        let printed = try XCTUnwrap(saver.requests.last?.imageData)
        XCTAssertNotEqual(printed, plain, "The same recipe with a new finish needs new export bytes")
        try assertUprightDimensions(data: printed, width: 44, height: 87)
        XCTAssertEqual(model.reviewFinish, .instantPrint, "Save freezes the entire edit descriptor")
        saver.completeLast(with: .failure(.writeFailed))
        model.saveReview(photoLibrary: saver)
        XCTAssertEqual(saver.requests.last?.imageData, printed, "Retry must reuse exact encoded bytes")
        saver.completeLast(with: .failure(.writeFailed))

        model.applyReviewFinish(.photo)
        await model.waitForReviewWorkToDrainForTesting()
        model.saveReview(photoLibrary: saver)
        await model.waitForReviewWorkToDrainForTesting()
        let restored = try XCTUnwrap(saver.requests.last?.imageData)
        try assertUprightDimensions(data: restored, width: 40, height: 80)
        XCTAssertEqual(try decodedPixels(from: restored), try decodedPixels(from: plain),
                       "Removing the border must return to the pristine source, never crop a previous JPEG")
        saver.completeLast(with: .success(()))
        XCTAssertEqual(model.reviewFinish, .photo)
        XCTAssertNil(model.pendingReviewFinish)
        XCTAssertNil(model.reviewImage)
    }

    func testPendingCustomizedLookAndFinishRemainOneLatestEdit() async throws {
        let blocker = BlockingPreviewRenderer()
        let (model, defaults, suite) = try makeViewModel(previewRenderer: blocker.call)
        defer { blocker.releaseAll(); defaults.removePersistentDomain(forName: suite) }
        model.select(recipe: try recipe(id: "provia-standard"))
        await model.importPhoto(data: try orientedQuadrantJPEG(orientation: 1))
        var customized = try recipe(id: "classic-chrome")
        customized.saturation = 0.72
        let started = expectation(description: "first look started")
        blocker.setOnStart { _ in started.fulfill() }
        model.applyReviewRecipe(customized)
        await fulfillment(of: [started], timeout: 2)
        model.applyReviewFinish(.instantPrint)
        model.applyReviewFinish(.photo)
        model.applyReviewFinish(.instantPrint)
        XCTAssertEqual(model.pendingReviewFinish, .instantPrint)
        let saver = ControlledPhotoSaver()
        model.saveReview(photoLibrary: saver)
        XCTAssertTrue(saver.requests.isEmpty)
        let latest = expectation(description: "latest pair started")
        blocker.setOnStart { _ in latest.fulfill() }
        blocker.releaseNext()
        await fulfillment(of: [latest], timeout: 2)
        blocker.releaseNext()
        await model.waitForReviewWorkToDrainForTesting()
        XCTAssertEqual(model.reviewRecipe, customized, "Finish changes must retain pending custom recipe values")
        XCTAssertEqual(model.reviewFinish, .instantPrint)
        XCTAssertNil(model.pendingReviewFinish)
        XCTAssertEqual(blocker.recipeIDs.count, 2, "Superseded work must not run")
        XCTAssertEqual(blocker.maximumConcurrentCalls, 1)
    }

    func testPrintPreviewFailureKeepsExistingPhotoSavable() async throws {
        let (model, defaults, suite) = try makeViewModel(
            previewRenderer: { source, recipe, finish in
                finish == .instantPrint ? nil : Self.preview(source: source, recipe: recipe)
            }
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.importPhoto(data: try orientedQuadrantJPEG(orientation: 1))
        let previous = model.reviewImage
        model.applyReviewFinish(.instantPrint)
        await model.waitForReviewWorkToDrainForTesting()
        XCTAssertTrue(model.reviewImage === previous)
        XCTAssertEqual(model.reviewFinish, .photo)
        XCTAssertNil(model.pendingReviewFinish)
        XCTAssertFalse(model.isRenderingReview)
        XCTAssertNotNil(model.reviewRenderErrorMessage)
        let saver = ControlledPhotoSaver()
        model.saveReview(photoLibrary: saver)
        XCTAssertEqual(saver.requests.count, 1)
        saver.completeLast(with: .failure(.writeFailed))
        model.discardReview()
        XCTAssertNil(model.reviewImage)
        XCTAssertEqual(model.reviewFinish, .photo)
    }

    func testPrintEligibilityUsesNativeMetadataInsteadOfThumbnailDimensions() throws {
        let cameraMode = CameraViewModel.ReviewRenderSource.Mode.camera(
            viewportSize: .zero, previewDrawableSize: .zero, flashFired: false, grainSeed: 0)
        let native = try XCTUnwrap(CameraViewModel.reviewExportExtent(
            sourceSize: CGSize(width: 10_000, height: 10_000), orientation: 1, mode: cameraMode))
        XCTAssertNil(PhotoPrintCompositor.layout(for: native, finish: .instantPrint))
        XCTAssertNotNil(PhotoPrintCompositor.layout(
            for: CGRect(x: 0, y: 0, width: 1_800, height: 1_800), finish: .instantPrint))
        let imported = try XCTUnwrap(CameraViewModel.reviewExportExtent(
            sourceSize: CGSize(width: 10_000, height: 10_000), orientation: 1, mode: .photoLibrary))
        XCTAssertLessThanOrEqual(imported.width * imported.height, 40_000_000)
        XCTAssertNotNil(PhotoPrintCompositor.layout(for: imported, finish: .instantPrint))
        let cropMode = CameraViewModel.ReviewRenderSource.Mode.camera(
            viewportSize: CGSize(width: 2, height: 3), previewDrawableSize: .zero,
            flashFired: false, grainSeed: 0)
        XCTAssertEqual(CameraViewModel.reviewExportExtent(
            sourceSize: CGSize(width: 80, height: 40), orientation: 6, mode: cropMode),
                       CGRect(x: 0, y: 0, width: 40, height: 60))
    }

    private func makeViewModel(
        previewRenderer: CameraViewModel.ReviewPreviewRenderer? = nil,
        fullRenderer: CameraViewModel.ReviewFullRenderer? = nil,
        originalRenderer: CameraViewModel.ReviewOriginalRenderer? = nil
    ) throws -> (CameraViewModel, UserDefaults, String) {
        let suite = "CameraReviewEditingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (
            CameraViewModel(
                defaults: defaults,
                reviewPreviewRenderer: previewRenderer,
                reviewFullRenderer: fullRenderer,
                reviewOriginalRenderer: originalRenderer
            ),
            defaults,
            suite
        )
    }

    private func recipe(id: String) throws -> FilmRecipe {
        try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == id })
    }

    fileprivate nonisolated static func preview(
        source: CameraViewModel.ReviewRenderSource,
        recipe: FilmRecipe
    ) -> CameraViewModel.ReviewPreview? {
        guard let cgImage = orientedCGImage(from: source.data) else { return nil }
        return CameraViewModel.ReviewPreview(
            image: UIImage(cgImage: cgImage),
            isFullResolution: true,
            flashFired: false
        )
    }

    private nonisolated static func fullRender(
        source: CameraViewModel.ReviewRenderSource,
        recipe: FilmRecipe
    ) -> CameraViewModel.RenderedPhoto? {
        guard let cgImage = orientedCGImage(from: source.data),
              let data = PhotoOutputEncoder.jpegData(
                for: cgImage,
                sourceData: source.data,
                capturedAt: source.capturedAt,
                recipe: recipe
              ) else { return nil }
        return CameraViewModel.RenderedPhoto(
            image: UIImage(cgImage: cgImage),
            data: data,
            capturedAt: source.capturedAt
        )
    }

    private nonisolated static func orientedCGImage(from data: Data) -> CGImage? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return nil
        }
        return FilmRenderer.outputCGImage(image, from: image.extent)
    }

    private func assertUprightDimensions(data: Data, width: Int, height: Int) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        )
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
        XCTAssertEqual(
            (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue,
            1
        )
    }

    private func provenanceRecipeID(in data: Data) throws -> String {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        )
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let comment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment as String] as? String)
        let metadata = try JSONDecoder().decode(
            PhotoOutputEncoder.RecipeProvenanceMetadata.self,
            from: Data(comment.utf8)
        )
        return metadata.recipeID
    }

    private func decodedPixels(from data: Data) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = Data(count: image.width * image.height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drew)
        return bytes
    }

    private func assertRegion(_ actual: CGRect?, equals expected: CGRect) {
        guard let actual else {
            XCTFail("Expected one normalized subject region")
            return
        }
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001)
    }

    private func quadrantColors(in image: CGImage) throws -> [QuadrantColor] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return [
            (image.width / 4, image.height / 4),
            (image.width * 3 / 4, image.height / 4),
            (image.width / 4, image.height * 3 / 4),
            (image.width * 3 / 4, image.height * 3 / 4)
        ].map { x, y in
            let offset = (y * image.width + x) * 4
            return QuadrantColor(
                red: pixels[offset],
                green: pixels[offset + 1],
                blue: pixels[offset + 2]
            )
        }
    }

    private func orientedQuadrantJPEG(orientation: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            UIColor.green.setFill()
            context.fill(CGRect(x: 40, y: 0, width: 40, height: 20))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 20, width: 40, height: 20))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 40, y: 20, width: 40, height: 20))
        }
        return try jpegData(for: try XCTUnwrap(image.cgImage), orientation: orientation)
    }

    private func wideJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor(red: 0.1, green: 0.35, blue: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor(red: 0.9, green: 0.55, blue: 0.1, alpha: 1).setFill()
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
        return try jpegData(for: try XCTUnwrap(image.cgImage), orientation: orientation)
    }

    private func jpegData(for image: CGImage, orientation: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation as String: orientation] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private enum QuadrantColor: Equatable {
        case red
        case green
        case blue
        case yellow

        init(red: UInt8, green: UInt8, blue: UInt8) {
            let red = Double(red)
            let green = Double(green)
            let blue = Double(blue)
            if blue > red * 1.2, blue > green * 1.2 {
                self = .blue
            } else if green > red * 1.2, green > blue * 1.2 {
                self = .green
            } else if red > green * 1.3, red > blue * 1.2 {
                self = .red
            } else {
                self = .yellow
            }
        }
    }
}

private final class RenderProbe<Output>: @unchecked Sendable {
    private let lock = NSLock()
    private let renderer: @Sendable (CameraViewModel.ReviewRenderSource, FilmRecipe, PhotoFinish) -> Output?
    private var recordedRecipeIDs: [String] = []
    private var recordedDates: [Date] = []

    init(renderer: @escaping @Sendable (CameraViewModel.ReviewRenderSource, FilmRecipe, PhotoFinish) -> Output?) {
        self.renderer = renderer
    }

    var call: @Sendable (CameraViewModel.ReviewRenderSource, FilmRecipe, PhotoFinish) -> Output? {
        { [weak self] source, recipe, finish in
            guard let self else { return nil }
            self.lock.lock()
            self.recordedRecipeIDs.append(recipe.id)
            self.recordedDates.append(source.capturedAt)
            self.lock.unlock()
            return self.renderer(source, recipe, finish)
        }
    }

    var recipeIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRecipeIDs
    }

    var capturedDates: [Date] {
        lock.lock()
        defer { lock.unlock() }
        return recordedDates
    }
}

private final class BlockingPreviewRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [DispatchSemaphore] = []
    private var activeCalls = 0
    private var maxCalls = 0
    private var recordedRecipeIDs: [String] = []
    private var onStart: (@Sendable (String) -> Void)?

    var call: CameraViewModel.ReviewPreviewRenderer {
        { [weak self] source, recipe, finish in
            guard let self else { return nil }
            let gate = DispatchSemaphore(value: 0)
            self.lock.lock()
            self.gates.append(gate)
            self.recordedRecipeIDs.append(recipe.id)
            self.activeCalls += 1
            self.maxCalls = max(self.maxCalls, self.activeCalls)
            let callback = self.onStart
            self.lock.unlock()
            callback?(recipe.id)
            gate.wait()
            self.lock.lock()
            self.activeCalls -= 1
            self.lock.unlock()
            return CameraReviewEditingTests.preview(source: source, recipe: recipe)
        }
    }

    func releaseNext() {
        lock.lock()
        let gate = gates.isEmpty ? nil : gates.removeFirst()
        lock.unlock()
        gate?.signal()
    }

    func setOnStart(_ callback: @escaping @Sendable (String) -> Void) {
        lock.lock()
        onStart = callback
        lock.unlock()
    }

    func releaseAll() {
        lock.lock()
        let pending = gates
        gates.removeAll()
        lock.unlock()
        pending.forEach { $0.signal() }
    }

    var recipeIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRecipeIDs
    }

    var maximumConcurrentCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return maxCalls
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
