import CoreImage
import Foundation
import ImageIO
import XCTest
@testable import FilmyCamera

@MainActor
final class FilmyPhotoStoreTests: XCTestCase {
    private func fixture() throws -> Data {
        let image = CIImage(color: CIColor(red: 0.7, green: 0.3, blue: 0.15)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        let output = try XCTUnwrap(FilmRenderer.outputCGImage(image, from: image.extent))
        return try XCTUnwrap(PhotoOutputEncoder.jpegData(for: output, sourceData: Data(), capturedAt: Date(timeIntervalSince1970: 0),
            recipe: FilmRecipe.builtIns[0]))
    }
    private func edit() -> FilmyPhotoEdit {
        FilmyPhotoEdit(recipe: FilmRecipe.builtIns[0], finish: .photo, options: ProCaptureOptions(),
            viewport: CGSize(width: 4, height: 3), previewDrawable: CGSize(width: 400, height: 300), grainSeed: 31, flashFired: false)
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testOriginalAndRAWSurviveRelaunchAndMultipleEditsByteForByte() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = FilmyPhotoStore(root: location)
        let source = try fixture()
        let raw = Data([0x49, 0x49, 0x2a, 0, 17, 21])
        let project = try await store.insert(original: source, raw: raw, movieURL: nil, capturedAt: Date(timeIntervalSince1970: 5),
            dimensions: .init(width: 64, height: 48), edit: edit())
        let committed = try await store.commitRendition(project.id, data: source, edit: edit(), expectedRevision: 0)
        XCTAssertEqual(committed.revision, 1)
        let restarted = FilmyPhotoStore(root: location)
        let original = try await restarted.original(project.id)
        let rawOriginal = try await restarted.original(project.id, raw: true)
        XCTAssertEqual(original, source)
        XCTAssertEqual(rawOriginal, raw)
        var changed = edit(); changed.recipe = FilmRecipe.builtIns[1]
        let next = try await restarted.render(project.id, edit: changed, expectedRevision: 1)
        XCTAssertEqual(next.revision, 2)
        let reverted = try await restarted.render(project.id, edit: project.initialEdit, expectedRevision: 2)
        XCTAssertEqual(reverted.edit, project.initialEdit)
        let unchanged = try await restarted.original(project.id)
        XCTAssertEqual(unchanged, source)
        let listing = try await restarted.list()
        XCTAssertEqual(listing.photos.count, 1)
        XCTAssertEqual(listing.unreadableCount, 0)
    }
    func testStaleRevisionAndFailedRenditionLeaveCommittedManifestUntouched() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = FilmyPhotoStore(root: location)
        let source = try fixture()
        let project = try await store.insert(original: source, raw: nil, movieURL: nil, capturedAt: Date(),
            dimensions: .init(width: 64, height: 48), edit: edit())
        let valid = try await store.commitRendition(project.id, data: source, edit: edit(), expectedRevision: 0)
        do {
            _ = try await store.commitRendition(project.id, data: source, edit: edit(), expectedRevision: 0)
            XCTFail("A stale save must not overwrite another revision")
        } catch { XCTAssertEqual(error as? FilmyPhotoStoreError, .conflict) }
        do {
            _ = try await store.commitRendition(project.id, data: Data([1, 2]), edit: edit(), expectedRevision: 1)
            XCTFail("Invalid pixels must not commit a manifest")
        } catch { XCTAssertEqual(error as? FilmyPhotoStoreError, .renderFailed) }
        let current = try await store.load(project.id)
        XCTAssertEqual(current, valid)
        let original = try await store.original(project.id)
        XCTAssertEqual(original, source)
    }
    func testCorruptOriginalIsDetectedWithoutDeletingIt() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = FilmyPhotoStore(root: location)
        let project = try await store.insert(original: fixture(), raw: nil, movieURL: nil, capturedAt: Date(),
            dimensions: .init(width: 64, height: 48), edit: edit())
        let url = try await store.resourceURL(project.id, filename: project.originalFilename)
        try Data([3, 4, 5]).write(to: url)
        do { _ = try await store.original(project.id); XCTFail("Integrity validation was bypassed") }
        catch { XCTAssertEqual(error as? FilmyPhotoStoreError, .corruptOriginal) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testLiveMovieIsCopiedNotMovedBeforeTemporaryResourceIsReleased() async throws {
        let location = root()
        let movie = root().appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: location); try? FileManager.default.removeItem(at: movie) }
        try Data([1, 3, 5]).write(to: movie)
        let store = FilmyPhotoStore(root: location)
        let project = try await store.insert(original: fixture(), raw: nil, movieURL: movie, capturedAt: Date(),
            dimensions: .init(width: 64, height: 48), edit: edit())
        let savedMovie = try await store.resourceURL(project.id, filename: XCTUnwrap(project.movieFilename))
        try FileManager.default.removeItem(at: movie)
        XCTAssertEqual(try Data(contentsOf: savedMovie), Data([1, 3, 5]))
    }
    func testInterruptedStagingIsNotPresentedAsAnEmptyOrFinishedPhoto() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        try FileManager.default.createDirectory(at: location.appendingPathComponent(".staging-interrupted"), withIntermediateDirectories: true)
        let listing = try await FilmyPhotoStore(root: location).list()
        XCTAssertTrue(listing.photos.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.appendingPathComponent(".staging-interrupted").path))
    }
    func testStaleSweepKeepsPendingDirectoryWithManifestAndRemovesOneWithout() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let files = FileManager.default
        let kept = location.appendingPathComponent(".\(UUID().uuidString).pending")
        let removed = location.appendingPathComponent(".staging-\(UUID().uuidString)")
        for url in [kept, removed] { try files.createDirectory(at: url, withIntermediateDirectories: true) }
        try Data("{}".utf8).write(to: kept.appendingPathComponent("document.json"))
        let old = Date().addingTimeInterval(-7200)
        for url in [kept, removed] { try files.setAttributes([.modificationDate: old], ofItemAtPath: url.path) }
        _ = try await FilmyPhotoStore(root: location).list()
        XCTAssertTrue(files.fileExists(atPath: kept.path))
        XCTAssertFalse(files.fileExists(atPath: removed.path))
    }
    func testCorruptDerivativeAliasCannotDeleteOriginal() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = FilmyPhotoStore(root: location)
        let bytes = try fixture()
        var project = try await store.insert(original: bytes, raw: nil, movieURL: nil, capturedAt: Date(),
            dimensions: ProPhotoDimensions(width: 16, height: 16), edit: edit())
        let directory = location.appendingPathComponent(project.id.uuidString)
        project.renditionFilename = project.originalFilename
        try JSONEncoder().encode(project).write(to: directory.appendingPathComponent("project.json"), options: .atomic)
        do {
            _ = try await store.commitRendition(project.id, data: bytes, edit: edit(), expectedRevision: 0)
            XCTFail("A derivative alias must not be accepted")
        } catch { XCTAssertEqual(error as? FilmyPhotoStoreError, .invalidManifest) }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(project.originalFilename)), bytes)
    }
    func testManifestPathValidationPreventsTraversal() {
        for name in ["", "../original.dng", "/tmp/data", "a/b.jpg", "a\\b.jpg", ".project", "photo..jpg"] {
            XCTAssertFalse(FilmyPhotoStore.isSafeFilename(name))
        }
        XCTAssertTrue(FilmyPhotoStore.isSafeFilename("original.heic"))
    }

    func testLoadingOlderVersionRestoresItsOutputSettingsWithoutChangingLatestRevision() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = FilmyPhotoStore(root: location)
        let source = try fixture()
        var firstSettings = ProCaptureSettings()
        firstSettings.resolution = .mp12
        firstSettings.format = .jpeg
        firstSettings.colorGamut = .sRGB
        let document = try await store.create(
            processed: source, raw: nil, liveMovieURL: nil, capturedAt: Date(),
            geometry: FilmyRenderGeometry(viewportWidth: 4, viewportHeight: 3,
                                          previewWidth: 400, previewHeight: 300,
                                          grainSeed: 1, flashFired: false),
            recipe: FilmRecipe.builtIns[0], finish: .photo, settings: firstSettings
        )
        let firstID = try XCTUnwrap(document.currentRevision?.id)
        var laterSettings = ProCaptureSettings()
        laterSettings.resolution = .mp48
        laterSettings.format = .jpeg
        let updated = try await store.addRevision(
            document.id, expectedRevisionID: firstID, recipe: FilmRecipe.builtIns[0],
            finish: .photo, settings: laterSettings, renderedData: source
        )

        XCTAssertEqual(updated.revisionForEditing(firstID)?.output, firstSettings)
        XCTAssertEqual(updated.revisionForEditing(nil)?.output, laterSettings)
        XCTAssertEqual(updated.revisionForEditing(UUID())?.output, laterSettings)
        XCTAssertEqual(updated.currentRevision?.id, updated.revisionForEditing(nil)?.id)
    }
    func testReceiptDecisionAdoptsOnlyResolvingIdentifiers() {
        XCTAssertEqual(PhotosExportReceipt.decision(pending: nil) { _ in true }, .create)
        XCTAssertEqual(PhotosExportReceipt.decision(pending: "A/L0/001") { _ in true }, .adopt("A/L0/001"))
        XCTAssertEqual(PhotosExportReceipt.decision(pending: "A/L0/001") { _ in false }, .clearAndCreate)
    }

    func testPendingReceiptIsAdoptedWhenResolvingAndClearedWhenNot() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = FilmyPhotoStore(root: location)
        // Receipts belong to documents, the format the Photos exporter links.
        var settings = ProCaptureSettings()
        settings.resolution = .mp12
        settings.format = .jpeg
        settings.colorGamut = .sRGB
        let created = try await store.create(
            processed: try fixture(), raw: nil, liveMovieURL: nil, capturedAt: Date(timeIntervalSince1970: 5),
            geometry: FilmyRenderGeometry(viewportWidth: 4, viewportHeight: 3,
                                          previewWidth: 400, previewHeight: 300,
                                          grainSeed: 1, flashFired: false),
            recipe: FilmRecipe.builtIns[0], finish: .photo, settings: settings
        )
        let receipt = await store.photosReceiptURL(for: created.id)
        PhotosExportReceipt.record("A/L0/001", at: receipt)
        XCTAssertEqual(PhotosExportReceipt.adoptable(at: receipt) { _ in true }, "A/L0/001")
        XCTAssertNotNil(PhotosExportReceipt.pending(at: receipt))
        XCTAssertNil(PhotosExportReceipt.adoptable(at: receipt) { _ in false })
        XCTAssertNil(PhotosExportReceipt.pending(at: receipt))
        // The manifest has no receipt field, so older documents decode unchanged.
        let document = try await store.loadDocument(created.id)
        XCTAssertNil(document.photosAssetIdentifier)
    }

    func testFujiLibraryReportsUnreadableRecordsAndKeepsFiles() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let library = FujiCaptureLibrary(root: location)
        let folder = location.appendingPathComponent("originals").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("source.jpg"))
        try Data("{".utf8).write(to: folder.appendingPathComponent("record.json"))
        let listed = try await library.originals()
        let unreadable = try await library.unreadableOriginals()
        XCTAssertTrue(listed.isEmpty)
        XCTAssertEqual(unreadable.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("source.jpg").path))
    }
}
