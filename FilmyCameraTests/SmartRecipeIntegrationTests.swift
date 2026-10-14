import Combine
import CoreImage
import XCTest
@testable import FilmyCamera

final class SmartRecipeIntegrationTests: XCTestCase {
    func testActualCatalogSupportsEverySceneAndIntent() {
        let profiles = FilmRecipe.builtIns.map(SmartRecipeProfile.init(recipe:))
        XCTAssertEqual(profiles.count, FilmRecipe.builtIns.count)
        XCTAssertTrue(profiles.allSatisfy(\.isValid))
        let available = Set(FilmRecipe.builtIns.map(\.id))
        for kind in SmartSceneKind.allCases {
            for intent in SmartRecipeIntent.allCases {
                let scene = SmartScene(kind: kind, evidence: 0.8, metrics: .init(), hasFaces: kind == .people)
                let matches = SmartRecipeEngine.rank(scene: scene, profiles: profiles, intent: intent)
                XCTAssertFalse(matches.isEmpty, "\(kind) / \(intent)")
                XCTAssertLessThanOrEqual(matches.count, 3)
                XCTAssertTrue(Set(matches.map(\.id)).isSubset(of: available))
            }
        }
    }

    @MainActor
    func testStoreOptionsAreEmptyWithoutSnapshotAndSnapshotOptionsRepeat() throws {
        let suite = "SmartRecipeIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        XCTAssertTrue(store.options.isEmpty)
        store.setIntent(.vivid)
        XCTAssertTrue(store.options.isEmpty)

        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let snapshot = SmartRecipeSnapshot(id: UUID(), scene: SmartScene(kind: .people, evidence: 0.8, metrics: .init(), hasFaces: true),
            image: try XCTUnwrap(context.makeImage()), catalog: FilmRecipe.builtIns, favoriteIDs: [], usedVision: false)
        XCTAssertEqual(snapshot.options(intent: .balanced).map(\.id), snapshot.options(intent: .balanced).map(\.id))
        XCTAssertFalse(snapshot.options(intent: .balanced).isEmpty)
    }

    @MainActor
    private func analyzedFrame(kind: SmartSceneKind = .people) throws -> SmartAnalyzedFrame {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return SmartAnalyzedFrame(scene: SmartScene(kind: kind, evidence: 0.8, metrics: .init(), hasFaces: kind == .people),
                                  image: try XCTUnwrap(context.makeImage()), usedVision: false)
    }

    @MainActor
    func testStableSceneTickDoesNotPublish() throws {
        let suite = "SmartRecipeIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        let frame = try analyzedFrame()
        var sends = 0
        let cancellable = store.objectWillChange.sink { sends += 1 }
        defer { cancellable.cancel() }

        // The stabilizer needs two matching observations before it displays a scene.
        store.applyAnalyzed(frame, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced)
        store.applyAnalyzed(frame, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced)
        XCTAssertGreaterThan(sends, 0, "The display transition (nil to scene) must notify observers")
        let firstID = try XCTUnwrap(store.snapshot?.id, "A stable scene must be displayed after two observations")
        let optionIDs = store.options.map(\.id)
        XCTAssertFalse(optionIDs.isEmpty)

        sends = 0
        store.applyAnalyzed(frame, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced)
        XCTAssertEqual(sends, 0, "objectWillChange sends on a repeat tick of an unchanged scene")
        let secondID = try XCTUnwrap(store.snapshot?.id)
        XCTAssertNotEqual(secondID, firstID, "The silent refresh must still store the freshest frame")
        XCTAssertEqual(store.options.map(\.id), optionIDs, "Options must not reshuffle on a repeat tick")
    }

    @MainActor
    func testSceneSwitchPublishesOnceWhileStatusStaysReady() throws {
        let suite = "SmartRecipeIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        let sceneA = try analyzedFrame(kind: .people)
        let sceneB = try analyzedFrame(kind: .landscape)
        let rankedB = SmartRecipeEngine.rank(scene: sceneB.scene, profiles: FilmRecipe.builtIns.map(SmartRecipeProfile.init(recipe:)), intent: .balanced)
        XCTAssertFalse(rankedB.isEmpty)

        store.applyAnalyzed(sceneA, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced, now: 100)
        store.applyAnalyzed(sceneA, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced, now: 101)
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.snapshot?.scene.kind, .people)

        var sends = 0
        let cancellable = store.objectWillChange.sink { sends += 1 }
        defer { cancellable.cancel() }

        // The first observation of the new scene only becomes pending.
        store.applyAnalyzed(sceneB, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced, now: 110)
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(store.snapshot?.scene.kind, .people)

        store.applyAnalyzed(sceneB, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced, now: 111)
        XCTAssertEqual(sends, 1, "A displayed scene switch must notify observers exactly once")
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.snapshot?.scene.kind, .landscape)
        XCTAssertFalse(store.options.isEmpty)
    }

    @MainActor
    func testInvalidateSceneClearsDisplayedSnapshotAndPublishes() throws {
        let suite = "SmartRecipeIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        let frame = try analyzedFrame()
        store.applyAnalyzed(frame, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced)
        store.applyAnalyzed(frame, recipes: FilmRecipe.builtIns, favorites: [], intent: .balanced)
        XCTAssertNotNil(store.snapshot)
        var sends = 0
        let cancellable = store.objectWillChange.sink { sends += 1 }
        defer { cancellable.cancel() }

        store.invalidateScene()
        XCTAssertGreaterThan(sends, 0, "Clearing a displayed snapshot must notify observers")
        XCTAssertNil(store.snapshot)
    }

    @MainActor
    func testRepeatedInvalidateSceneOnActiveStoreDoesNotPublish() throws {
        let suite = "SmartRecipeIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        let camera = CameraService()
        store.configure(camera: camera, active: true, recipes: FilmRecipe.builtIns)
        defer { store.stop() }
        XCTAssertEqual(store.status, .analyzing)
        var sends = 0
        let cancellable = store.objectWillChange.sink { sends += 1 }
        defer { cancellable.cancel() }

        store.invalidateScene()
        store.invalidateScene()
        XCTAssertEqual(sends, 0, "objectWillChange sends on repeated invalidateScene() of an active, empty store")
    }

    @MainActor
    func testInvalidateSceneWithNoSnapshotDoesNotPublish() throws {
        let suite = "SmartRecipeIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        XCTAssertNil(store.snapshot)
        var sends = 0
        let cancellable = store.objectWillChange.sink { sends += 1 }
        defer { cancellable.cancel() }

        store.invalidateScene()
        sends = 0
        store.invalidateScene()
        XCTAssertEqual(sends, 0, "objectWillChange sends on invalidateScene() with no snapshot")
    }

    func testProjectionUsesEffectiveRecipeControls() {
        var recipe = FilmRecipe.builtIns[0]
        recipe.contrast = 0.94
        recipe.saturation = 0.88
        recipe.grain = 0.12
        recipe.tone.highlight = -0.15
        recipe.dynamicRange = .dr400
        let profile = SmartRecipeProfile(recipe: recipe)
        XCTAssertEqual(profile.contrast, recipe.contrast)
        XCTAssertEqual(profile.saturation, recipe.saturation)
        XCTAssertEqual(profile.grain, recipe.grain)
        XCTAssertEqual(profile.highlights, recipe.tone.highlight)
        XCTAssertEqual(profile.highlightProtection, 0.30)
    }

    @MainActor
    func testSuggestionsDoNotSelectARecipeOrModifyStoredControls() throws {
        let suite = "FilmyCameraTests.Smart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let viewModel = CameraViewModel(defaults: defaults)
        let before = viewModel.selectedRecipe
        let persistedBefore = defaults.dictionaryRepresentation() as NSDictionary
        let scene = SmartScene(kind: .people, evidence: 0.9, metrics: .init(), hasFaces: true)
        _ = SmartRecipeEngine.rank(scene: scene, profiles: viewModel.recipes.map(SmartRecipeProfile.init(recipe:)))
        XCTAssertEqual(viewModel.selectedRecipe, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, persistedBefore)
    }

    @MainActor
    func testPreferencesPersistAndDisablingClearsSuggestions() throws {
        let suite = "FilmyCameraTests.Smart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.intent, .balanced)
        store.setIntent(.cinematic)
        store.setEnabled(false)
        XCTAssertEqual(store.status, .off)
        XCTAssertNil(store.snapshot)
        let restored = SmartRecipeStore(defaults: defaults)
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(restored.intent, .cinematic)
    }

    @MainActor
    func testInvalidStoredIntentFallsBackSafely() throws {
        let suite = "FilmyCameraTests.Smart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("invalid", forKey: SmartRecipeStore.intentKey)
        XCTAssertEqual(SmartRecipeStore(defaults: defaults).intent, .balanced)
    }

    @MainActor
    func testUndoReconciliationClearsAfterManualSelection() throws {
        let suite = "FilmyCameraTests.Smart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SmartRecipeStore(defaults: defaults)
        store.recordSelection(previousID: "a", appliedID: "b")
        store.reconcileSelection(currentID: "b", availableIDs: ["a", "b", "c"])
        XCTAssertNotNil(store.undo)
        store.reconcileSelection(currentID: "c", availableIDs: ["a", "b", "c"])
        XCTAssertNil(store.undo)
    }

    func testSnapshotPreservesEditedCatalogRatherThanRehydratingBuiltIns() throws {
        let source = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = try XCTUnwrap(CIContext().createCGImage(source, from: source.extent))
        var recipe = FilmRecipe.builtIns[0]
        recipe.contrast = 0.93
        let snapshot = SmartRecipeSnapshot(id: UUID(), scene: .init(kind: .everyday, evidence: 0.5, metrics: .init(), hasFaces: false),
                                           image: image, catalog: [recipe], favoriteIDs: [], usedVision: false)
        XCTAssertEqual(snapshot.options(intent: .balanced).first?.recipe, recipe)
        XCTAssertEqual(snapshot.options(intent: .balanced).count, 1)
    }

    func testWorkerOwnsBoundedCopyMatchingViewfinderCrop() async throws {
        let worker = SmartRecipeImageWorker()
        let source = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.4))
            .cropped(to: CGRect(x: 20, y: 30, width: 800, height: 600))
        let result = await withCheckedContinuation { continuation in
            worker.analyze(frame: SmartRecipeFrameBox(source), viewport: CGSize(width: 300, height: 400)) {
                continuation.resume(returning: $0)
            }
        }
        let frame = try result.get()
        XCTAssertEqual(frame.image.width, 288)
        XCTAssertEqual(frame.image.height, 384)
        XCTAssertTrue(frame.scene.metrics.isUsable)
    }

    func testWorkerRejectsInfiniteInputWithoutVision() async {
        let worker = SmartRecipeImageWorker()
        let result = await withCheckedContinuation { continuation in
            worker.analyze(frame: SmartRecipeFrameBox(CIImage(color: .black)), viewport: .zero) {
                continuation.resume(returning: $0)
            }
        }
        switch result {
        case .success: XCTFail("An infinite image must not be retained or analyzed")
        case .failure(let error): XCTAssertEqual(error, .renderingUnavailable)
        }
    }

    func testWorkerRejectsCoveredLens() async {
        let worker = SmartRecipeImageWorker()
        let source = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let result = await withCheckedContinuation { continuation in
            worker.analyze(frame: SmartRecipeFrameBox(source), viewport: .zero) { continuation.resume(returning: $0) }
        }
        switch result {
        case .success: XCTFail("A covered lens must not produce confident recommendations")
        case .failure(let error): XCTAssertEqual(error, .unusableFrame)
        }
    }
}
