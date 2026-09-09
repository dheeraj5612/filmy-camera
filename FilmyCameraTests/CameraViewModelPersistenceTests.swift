import Foundation
import XCTest
@testable import FilmyCamera

@MainActor
final class CameraViewModelPersistenceTests: XCTestCase {
    func testLaunchWarmupResolvesTheSelectedCustomLook() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var customized = FilmRecipe.builtIns[1]
        customized.colorChrome = 0.8
        customized.whiteBalance.temperature = 0.5
        defaults.set(customized.id, forKey: CameraViewModel.selectedRecipeIDKey)
        defaults.set(try JSONEncoder().encode([customized.id: customized]),
                     forKey: CameraViewModel.recipeOverridesKey)

        let warmed = CameraViewModel.launchRecipe(defaults: defaults)
        let model = CameraViewModel(defaults: defaults)
        XCTAssertEqual(warmed, model.selectedRecipe)
        XCTAssertEqual(warmed.colorChrome, 0.8)
    }

    func testInvalidSelectedRecipeIDIsNormalizedAndRewritten() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "removed-recipe",
            forKey: CameraViewModel.selectedRecipeIDKey
        )

        let viewModel = CameraViewModel(defaults: defaults)
        let fallbackID = CameraViewModel.defaultRecipeID

        XCTAssertEqual(viewModel.selectedRecipeID, fallbackID)
        XCTAssertEqual(
            defaults.string(forKey: CameraViewModel.selectedRecipeIDKey),
            fallbackID
        )

        viewModel.selectedRecipeID = "still-invalid"
        XCTAssertEqual(viewModel.selectedRecipeID, fallbackID)
        XCTAssertEqual(
            defaults.string(forKey: CameraViewModel.selectedRecipeIDKey),
            fallbackID
        )
    }

    func testValidSelectedRecipeIDIsPreserved() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectedID = FilmRecipe.builtIns[3].id
        defaults.set(
            selectedID,
            forKey: CameraViewModel.selectedRecipeIDKey
        )

        let viewModel = CameraViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.selectedRecipeID, selectedID)
        XCTAssertEqual(viewModel.selectedRecipe.id, selectedID)
    }

    func testCorruptOverrideDoesNotDiscardValidCustomRecipes() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var validRecipe = FilmRecipe.builtIns[1]
        validRecipe.exposure = 1.25
        validRecipe.contrast = 1.4

        let validData = try JSONEncoder().encode(validRecipe)
        let validObject = try JSONSerialization.jsonObject(with: validData)
        let mixedObject: [String: Any] = [
            validRecipe.id: validObject,
            "broken-recipe": ["id": 42]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: mixedObject),
            forKey: CameraViewModel.recipeOverridesKey
        )
        defaults.set(
            validRecipe.id,
            forKey: CameraViewModel.selectedRecipeIDKey
        )

        let viewModel = CameraViewModel(defaults: defaults)

        XCTAssertTrue(viewModel.isCustomized(validRecipe))
        XCTAssertEqual(viewModel.selectedRecipe.exposure, 1.25, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedRecipe.contrast, 1.4, accuracy: 0.0001)

        let rewrittenData = try XCTUnwrap(
            defaults.data(forKey: CameraViewModel.recipeOverridesKey)
        )
        let rewritten = try JSONDecoder().decode(
            [String: FilmRecipe].self,
            from: rewrittenData
        )
        XCTAssertEqual(Set(rewritten.keys), [validRecipe.id])
    }

    func testUnknownUpdatesAreIgnoredAndKnownUpdatesAreSanitized() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = CameraViewModel(defaults: defaults)
        let initialID = viewModel.selectedRecipeID
        let unknownRecipe = FilmRecipe(
            id: "unknown-recipe",
            name: "Unknown",
            subtitle: "Not part of the current catalog"
        )

        viewModel.select(recipe: unknownRecipe)
        viewModel.update(recipe: unknownRecipe)

        XCTAssertEqual(viewModel.selectedRecipeID, initialID)
        XCTAssertFalse(viewModel.isCustomized(unknownRecipe))

        let parent = FilmRecipe.builtIns[2]
        var damagedEdit = parent
        damagedEdit.exposure = .infinity
        damagedEdit.saturation = 99
        viewModel.update(recipe: damagedEdit)
        viewModel.select(recipe: parent)

        XCTAssertEqual(
            viewModel.selectedRecipe.exposure,
            parent.exposure,
            accuracy: 0.0001
        )
        XCTAssertEqual(viewModel.selectedRecipe.saturation, 2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedRecipe.id, parent.id)
    }

    func testRecipeLookupReturnsPersistedOverrideForUnselectedRecipe() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = CameraViewModel(defaults: defaults)
        let parent = FilmRecipe.builtIns[4]
        var customized = parent
        customized.exposure = 0.75

        viewModel.update(recipe: customized)

        XCTAssertTrue(viewModel.isCustomized(parent))
        XCTAssertEqual(
            viewModel.recipe(for: parent.id).exposure,
            0.75,
            accuracy: 0.0001
        )
    }

    func testOnboardingChoicePersistsWithoutResettingCustomControls() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CameraViewModel(defaults: defaults)
        var custom = try XCTUnwrap(model.recipes.first { $0.id == "classic-chrome" })
        custom.exposure = 0.75
        model.update(recipe: custom)
        let choices = OnboardingStore.featuredRecipes(from: model.recipes, selectedRecipeID: model.selectedRecipeID)
        model.select(recipe: try XCTUnwrap(choices.first { $0.id == custom.id }))

        let relaunched = CameraViewModel(defaults: defaults)
        XCTAssertEqual(relaunched.selectedRecipeID, custom.id)
        XCTAssertEqual(relaunched.selectedRecipe.exposure, 0.75, accuracy: 0.0001)
        XCTAssertTrue(relaunched.isCustomized(custom))
        XCTAssertEqual(CameraViewModel.launchRecipe(defaults: defaults), relaunched.selectedRecipe)
    }

    func testOnboardingChoicesAreStableAcrossCatalogReordering() {
        let choices = OnboardingStore.featuredRecipes(from: FilmRecipe.builtIns, selectedRecipeID: "g7x-compact")
        let reversed = OnboardingStore.featuredRecipes(from: Array(FilmRecipe.builtIns.reversed()), selectedRecipeID: "g7x-compact")
        XCTAssertEqual(choices.map(\.id), ["g7x-compact", "classic-chrome", "nostalgic-negative", "acros-monochrome"])
        XCTAssertEqual(choices, reversed)
    }

    func testOnboardingIncludesExistingSelectionWithoutDuplicates() {
        let choices = OnboardingStore.featuredRecipes(from: FilmRecipe.builtIns, selectedRecipeID: "astia-soft")
        XCTAssertEqual(choices.first?.id, "astia-soft")
        XCTAssertEqual(choices.count, 4)
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
    }

    func testOnboardingHandlesMissingAndEmptyCatalogs() {
        XCTAssertTrue(OnboardingStore.featuredRecipes(from: [], selectedRecipeID: "removed").isEmpty)
        let choices = OnboardingStore.featuredRecipes(from: FilmRecipe.builtIns, selectedRecipeID: "removed")
        XCTAssertEqual(choices.first?.id, "g7x-compact")
        XCTAssertEqual(choices.count, 4)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CameraViewModelPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

final class PhotoImportSessionTests: XCTestCase {
    func testOnlyOneImportCanStart() throws {
        var session = PhotoImportSession()
        let id = try XCTUnwrap(session.begin())
        XCTAssertEqual(session.phase, .loading)
        XCTAssertTrue(session.isCurrent(id))
        XCTAssertNil(session.begin())
    }

    func testCancelledDownloadCannotStartRendering() throws {
        var session = PhotoImportSession()
        let id = try XCTUnwrap(session.begin())
        session.cancel()
        XCTAssertFalse(session.isBusy)
        XCTAssertFalse(session.beginApplying(id))
        XCTAssertFalse(session.finish(id))
    }

    func testLateCompletionCannotClearANewerImport() throws {
        var session = PhotoImportSession()
        let stale = try XCTUnwrap(session.begin())
        session.cancel()
        let current = try XCTUnwrap(session.begin())
        XCTAssertNotEqual(stale, current)
        XCTAssertFalse(session.finish(stale))
        XCTAssertFalse(session.beginApplying(stale))
        XCTAssertEqual(session.phase, .loading)
        XCTAssertTrue(session.isCurrent(current))
        XCTAssertTrue(session.beginApplying(current))
    }

    func testRenderingCancellationKeepsControlsLockedUntilDrained() throws {
        var session = PhotoImportSession()
        let id = try XCTUnwrap(session.begin())
        XCTAssertTrue(session.beginApplying(id))
        session.cancel()
        XCTAssertEqual(session.phase, .cancelling)
        XCTAssertTrue(session.isBusy)
        XCTAssertNil(session.begin())
        XCTAssertFalse(session.beginApplying(id))
        XCTAssertTrue(session.finish(id))
        XCTAssertFalse(session.isBusy)
        XCTAssertNotNil(session.begin())
    }

    func testWrongCompletionCannotUnlockRenderer() throws {
        var session = PhotoImportSession()
        let id = try XCTUnwrap(session.begin())
        XCTAssertTrue(session.beginApplying(id))
        session.cancel()
        XCTAssertFalse(session.finish(UUID()))
        XCTAssertEqual(session.phase, .cancelling)
    }

    func testRepeatedCancellationAndCompletionAreSafe() throws {
        var session = PhotoImportSession()
        session.cancel()
        let id = try XCTUnwrap(session.begin())
        XCTAssertTrue(session.beginApplying(id))
        session.cancel()
        session.cancel()
        XCTAssertTrue(session.finish(id))
        XCTAssertFalse(session.finish(id))
        XCTAssertEqual(session.phase, .idle)
    }

    func testSuccessfulImportReturnsToIdle() throws {
        var session = PhotoImportSession()
        let id = try XCTUnwrap(session.begin())
        XCTAssertTrue(session.beginApplying(id))
        XCTAssertFalse(session.beginApplying(id))
        XCTAssertTrue(session.finish(id))
        XCTAssertEqual(session.phase, .idle)
    }
}

final class PhotoImportPolicyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testReadsAnExactLimitFileWithoutChangingBytes() throws {
        let url = directory.appendingPathComponent("photo.bin")
        let data = Data((0..<255).map { UInt8($0) })
        try data.write(to: url)
        XCTAssertEqual(try PhotoImportPolicy.read(from: url, byteLimit: data.count), data)
    }

    func testReadsAcrossChunkBoundaries() throws {
        let url = directory.appendingPathComponent("photo.bin")
        let data = Data(repeating: 0xAB, count: 131_073)
        try data.write(to: url)
        XCTAssertEqual(try PhotoImportPolicy.read(from: url, byteLimit: data.count), data)
    }

    func testRejectsOversizedFileBeforeReading() throws {
        let url = directory.appendingPathComponent("photo.bin")
        try Data(repeating: 1, count: 33).write(to: url)
        XCTAssertThrowsError(try PhotoImportPolicy.read(from: url, byteLimit: 32)) { error in
            guard case PhotoImportFailure.tooLarge = error else { return XCTFail("Expected size error, got \(error)") }
        }
    }

    func testRejectsEmptyFiles() throws {
        let url = directory.appendingPathComponent("photo.bin")
        try Data().write(to: url)
        XCTAssertThrowsError(try PhotoImportPolicy.read(from: url)) { error in
            guard case PhotoImportFailure.emptyFile = error else { return XCTFail("Expected empty-file error, got \(error)") }
        }
    }

    func testRejectsDirectoriesAndMissingFiles() {
        XCTAssertThrowsError(try PhotoImportPolicy.read(from: directory))
        XCTAssertThrowsError(try PhotoImportPolicy.read(from: directory.appendingPathComponent("missing")))
    }

    func testRejectsNonpositiveLimits() throws {
        let url = directory.appendingPathComponent("photo.bin")
        try Data([1]).write(to: url)
        XCTAssertThrowsError(try PhotoImportPolicy.read(from: url, byteLimit: 0))
        XCTAssertThrowsError(try PhotoImportPolicy.read(from: url, byteLimit: -1))
    }

    func testDirectImportFailureHasActionableMessage() {
        XCTAssertEqual(PhotoImportFailure.message(for: PhotoImportFailure.tooLarge), PhotoImportFailure.tooLarge.errorDescription)
    }

    func testWrappedProviderFailurePreservesSizeMessage() {
        let wrapped = NSError(domain: "provider", code: 1, userInfo: [NSUnderlyingErrorKey: PhotoImportFailure.tooLarge])
        XCTAssertEqual(PhotoImportFailure.message(for: wrapped), PhotoImportFailure.tooLarge.errorDescription)
    }

    func testUnknownProviderErrorDoesNotExposePrivatePaths() {
        let error = NSError(domain: "provider", code: 1, userInfo: [NSLocalizedDescriptionKey: "/private/photo-owner/photo.heic"])
        XCTAssertEqual(PhotoImportFailure.message(for: error), PhotoImportFailure.unavailable.errorDescription)
    }

    func testCancelledTaskDoesNotReadFile() async throws {
        let url = directory.appendingPathComponent("photo.bin")
        try Data([1, 2, 3]).write(to: url)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try PhotoImportPolicy.read(from: url)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled reader must throw")
        } catch is CancellationError {
            // Expected: cancellation is checked before file inspection.
        }
    }
}
