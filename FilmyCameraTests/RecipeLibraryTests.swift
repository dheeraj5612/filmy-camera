import Foundation
import XCTest
@testable import FilmyCamera

final class RecipeLibraryTests: XCTestCase {
    func testBundledSourcesAreCompleteBoundedAndIndividuallyTraceable() throws {
        XCTAssertTrue(RecipeCatalog.loadIssues.isEmpty, "\(RecipeCatalog.loadIssues)")
        XCTAssertGreaterThanOrEqual(RecipeCatalog.records.count, 500)
        XCTAssertEqual(Set(RecipeCatalog.records.map(\.id)).count, RecipeCatalog.records.count)
        XCTAssertEqual(Set(RecipeCatalog.records.map { $0.source.url }).count, RecipeCatalog.records.count)
        XCTAssertEqual(RecipeCatalog.cameraBaselines.count, 20)
        XCTAssertEqual(FilmRecipe.builtIns.count, 148 + RecipeCatalog.records.count)
        for record in RecipeCatalog.records {
            XCTAssertTrue(record.isValid, record.id)
            XCTAssertNotNil(record.source.sourceURL, record.id)
            XCTAssertTrue(record.recipe.provenance.isComplete, record.id)
            XCTAssertEqual(record.recipe.provenance.cameraSource, record.source)
            XCTAssertEqual(record.recipe.exposure, 0, "Metering advice is not an extra rendered exposure: \(record.id)")
            XCTAssertEqual(record.recipe.halation, 0, record.id)
            XCTAssertEqual(record.recipe.vignette, 0, record.id)
            XCTAssertEqual(record.recipe.blueResponse, 0, record.id)
            XCTAssertEqual(try JSONDecoder().decode(FilmRecipe.self, from: JSONEncoder().encode(record.recipe)), record.recipe)
            for control in FilmRecipe.Control.allCases {
                XCTAssertTrue(control.editorRange.contains(control.value(in: record.recipe)), "\(record.id): \(control)")
            }
        }
    }

    func testPackOwnershipPartitionsTheEntireCatalogAndDefaultsPreserveOriginals() {
        let ids = RecipeCatalog.packs.flatMap(\.recipeIDs)
        XCTAssertEqual(ids.count, FilmRecipe.builtIns.count)
        XCTAssertEqual(Set(ids), Set(FilmRecipe.builtIns.map(\.id)))
        let preferences = RecipeLibraryPreferences()
        let enabled = FilmRecipe.builtIns.filter { preferences.isEnabled($0.id) }.map(\.id)
        XCTAssertEqual(enabled, (FilmRecipe.legacyBuiltIns + FilmRecipe.originalCreativeLooks).map(\.id))
        XCTAssertTrue(RecipeCatalog.cameraBaselines.allSatisfy { !preferences.isEnabled($0.id) })
        XCTAssertTrue(RecipeCatalog.records.allSatisfy { !preferences.isEnabled($0.id) })
    }

    func testWholePackIntentClearsExceptionsAndIndividualSelectionWorksInsideDisabledPack() throws {
        let pack = try XCTUnwrap(RecipeCatalog.packs.first { $0.recipeIDs.count > 1 && !$0.enabledByDefault })
        let first = pack.recipeIDs[0]
        var state = RecipeLibraryPreferences()
        XCTAssertEqual(state.state(of: pack), .off)
        state.setRecipe(first, enabled: true, in: pack)
        XCTAssertEqual(state.state(of: pack), .mixed)
        XCTAssertEqual(state.enabledCount(in: pack), 1)
        state.setPack(pack, enabled: true)
        XCTAssertEqual(state.state(of: pack), .on)
        state.setRecipe(first, enabled: false, in: pack)
        XCTAssertEqual(state.state(of: pack), .mixed)
        XCTAssertFalse(state.isEnabled(first))
        state.setPack(pack, enabled: false)
        XCTAssertEqual(state.state(of: pack), .off)
        XCTAssertTrue(state.recipeOverrides.isEmpty)
        state.setPack(pack, enabled: true)
        XCTAssertTrue(state.isEnabled(first))
    }

    func testAllAndNoneHaveNoCatalogSizeTruncationAndRoundTrip() {
        var state = RecipeLibraryPreferences()
        state.setAll(RecipeCatalog.packs, enabled: true)
        XCTAssertTrue(FilmRecipe.builtIns.allSatisfy { state.isEnabled($0.id) })
        XCTAssertEqual(RecipeLibraryPreferences.decode(state.encoded()), state)
        state.setAll(RecipeCatalog.packs, enabled: false)
        XCTAssertTrue(FilmRecipe.builtIns.allSatisfy { !state.isEnabled($0.id) })
        XCTAssertEqual(RecipeLibraryPreferences.decode(state.encoded()), state)
        state.restoreDefaults()
        XCTAssertEqual(state, RecipeLibraryPreferences())
    }

    func testPreferencesSupport4096IndividualChoicesAndRetainUnknownIDs() throws {
        let ids = (0..<4096).map { "future-recipe-\($0)" }
        let unknownPack = RecipePack(id: "future-pack", title: "Future", subtitle: "Test", recipeIDs: ids,
                                     enabledByDefault: false, sortOrder: 9)
        var state = RecipeLibraryPreferences()
        for id in ids { state.setRecipe(id, enabled: true, in: unknownPack) }
        XCTAssertEqual(state.recipeOverrides.count, 4096)
        let restored = RecipeLibraryPreferences.decode(state.encoded())
        XCTAssertEqual(restored, state)
        XCTAssertTrue(restored.isEnabled(ids.last!, in: unknownPack))
        XCTAssertFalse(restored.isEnabled(ids.last!), "Unknown IDs are retained, not presented as real recipes")
        let favorites = Set(ids)
        XCTAssertEqual(LookLibraryIndex.favorites(from: LookLibraryIndex.encodeFavorites(favorites)), favorites)
    }

    func testCorruptFutureOversizedAndOutOfBoundsDataFailSafely() throws {
        XCTAssertEqual(RecipeLibraryPreferences.decode(Data("broken".utf8)), .init())
        XCTAssertEqual(RecipeLibraryPreferences.decode(Data(repeating: 0, count: RecipeLibraryPreferences.maximumBytes + 1)), .init())
        let future = Data(#"{"schemaVersion":99,"packOverrides":{"camera-bases":true},"recipeOverrides":{}}"#.utf8)
        XCTAssertEqual(RecipeLibraryPreferences.decode(future), .init())
        XCTAssertFalse(RecipeCatalog.decode(Data("broken".utf8)).issues.isEmpty)
        XCTAssertFalse(RecipeCatalog.decode(Data(repeating: 0, count: RecipeCatalog.maximumBytes + 1)).issues.isEmpty)
        let record = try XCTUnwrap(RecipeCatalog.records.first)
        let duplicate = RecipeCatalog.Envelope(schemaVersion: 1, records: [record, record])
        let decoded = RecipeCatalog.decode(try JSONEncoder().encode(duplicate))
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.issues.count, 1)
    }

    func testKnownPublishedCameraUnitsAreNotLostInNormalization() throws {
        let kodachrome = try XCTUnwrap(RecipeCatalog.records.first {
            $0.source.url == "https://fujixweekly.com/2020/05/27/my-fujifilm-x100v-kodachrome-64-film-simulation-recipe/"
        })
        XCTAssertEqual(kodachrome.controls.filmBase, .classicChrome)
        XCTAssertEqual(kodachrome.controls.dynamicRange, .dr200)
        XCTAssertEqual(kodachrome.controls.highlight, 0)
        XCTAssertEqual(kodachrome.controls.shadow, 0)
        XCTAssertEqual(kodachrome.controls.color, 2)
        XCTAssertEqual(kodachrome.controls.redShift, 2)
        XCTAssertEqual(kodachrome.controls.blueShift, -5)
        XCTAssertEqual(kodachrome.controls.clarity, 3)
        XCTAssertEqual(kodachrome.controls.colorChrome, .strong)
        XCTAssertEqual(kodachrome.controls.fxBlue, .weak)
        let gold = try XCTUnwrap(RecipeCatalog.records.first {
            $0.source.url == "https://film.recipes/2026/07/19/kodak-gold-ii-classic-kodak-film-recipe/"
        })
        XCTAssertEqual(gold.controls.colorChrome, .weak, "Abbreviated Col. Chr. Effect must not disappear")
        XCTAssertEqual(gold.controls.fxBlue, .off)
        XCTAssertEqual(gold.controls.redShift, 4)
        XCTAssertEqual(gold.controls.blueShift, -5)
        XCTAssertEqual(gold.controls.shadow, 1, "Use the numeric table, not conflicting prose about lifted shadows")
        XCTAssertEqual(gold.controls.noiseReduction, -4)
        XCTAssertEqual(gold.source.publisher, .filmRecipes)
        XCTAssertTrue(gold.recipe.provenance.references.contains(.filmRecipesLibrary))
        XCTAssertFalse(gold.recipe.provenance.references.contains(.fujiXWeeklyRecipeLibrary))
        let emerald = try XCTUnwrap(RecipeCatalog.records.first {
            $0.source.url == "https://film.recipes/2022/08/01/emerald-mono-a-toned-mono-for-nature/"
        })
        XCTAssertEqual(emerald.controls.highlight, -0.5)
        XCTAssertEqual(emerald.controls.shadow, 0.5)
        XCTAssertEqual(emerald.controls.monochromaticWarmCool, 4)
        XCTAssertEqual(emerald.controls.monochromaticGreenMagenta, 8)
        XCTAssertEqual(emerald.recipe.monochromaticColor.greenMagenta, -8.0 / 18, accuracy: 0.000001,
                       "Camera +MG means green; the existing Filmy editor's positive axis means magenta")

    }

    func testCameraFoundationsCoverAllMonochromeFiltersWithoutCreativeFinishing() {
        let bases = Set(RecipeCatalog.cameraBaselines.map(\.filmBase))
        XCTAssertTrue(bases.isSuperset(of: [.monochromeYellow, .monochromeRed, .monochromeGreen,
                                         .acrosYellow, .acrosRed, .acrosGreen]))
        for recipe in RecipeCatalog.cameraBaselines {
            XCTAssertEqual(recipe.grain, 0)
            XCTAssertEqual(recipe.vignette, 0)
            XCTAssertEqual(recipe.halation, 0)
            XCTAssertEqual(recipe.whiteBalance.temperature, 0)
            XCTAssertEqual(recipe.whiteBalance.tint, 0)
            XCTAssertEqual(recipe.dynamicRange, .dr100)
        }
    }

    func testMembershipFilteringSearchesSourcesWithoutHidingTheFullCatalog() throws {
        var state = RecipeLibraryPreferences()
        let record = try XCTUnwrap(RecipeCatalog.records.first { $0.source.publisher == .filmRecipes })
        let results = RecipeMembershipFilter.results(FilmRecipe.builtIns, query: record.source.url,
                                                     filter: .hidden, preferences: state, favorites: [])
        XCTAssertEqual(results.map(\.id), [record.id])
        state.setRecipe(record.id, enabled: true)
        let active = RecipeMembershipFilter.results(FilmRecipe.builtIns, query: record.source.url,
                                                    filter: .active, preferences: state, favorites: [])
        XCTAssertEqual(active.map(\.id), [record.id])
        XCTAssertTrue(RecipeMembershipFilter.results(FilmRecipe.builtIns, query: record.source.url,
                                                     filter: .hidden, preferences: state, favorites: []).isEmpty)
    }
}

@MainActor
final class RecipeLibraryPersistenceTests: XCTestCase {
    func testHidingCurrentCustomizedLookDoesNotChangeCaptureReviewOrPersistence() throws {
        let suite = "RecipeLibraryPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CameraViewModel(defaults: defaults)
        var selected = try XCTUnwrap(RecipeCatalog.sourcedRecipes.first)
        selected.exposure = 0.75
        model.update(recipe: selected)
        model.select(recipe: selected)
        model.libraryPreferences.setAll(RecipeCatalog.packs, enabled: false)
        XCTAssertTrue(model.quickRecipes.isEmpty)
        XCTAssertEqual(model.selectedRecipeID, selected.id)
        XCTAssertEqual(model.selectedRecipe.exposure, 0.75)
        XCTAssertEqual(model.recipes.count, FilmRecipe.builtIns.count, "Review keeps hidden looks available")
        XCTAssertEqual(model.quickNavigationRecipes.map(\.id), [selected.id])
        let reopened = CameraViewModel(defaults: defaults)
        XCTAssertEqual(reopened.libraryPreferences, model.libraryPreferences)
        XCTAssertTrue(reopened.quickRecipes.isEmpty)
        XCTAssertEqual(reopened.selectedRecipe, model.selectedRecipe)
        XCTAssertEqual(reopened.selectedRecipe.provenance.cameraSource, selected.provenance.cameraSource)
        reopened.libraryPreferences.restoreDefaults()
        XCTAssertEqual(reopened.quickRecipes.count, 128)
        XCTAssertEqual(reopened.selectedRecipe.exposure, 0.75, "Membership reset must not reset tuning")
    }

    func testHiddenCurrentLookIsOnlyANavigationAnchorUntilTheUserSwipes() throws {
        let suite = "RecipeLibraryNavigation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CameraViewModel(defaults: defaults)
        let looks = Array(FilmRecipe.builtIns.prefix(3))
        model.select(recipe: looks[1])
        model.libraryPreferences.setAll(RecipeCatalog.packs, enabled: false)
        model.libraryPreferences.setRecipe(looks[0].id, enabled: true)
        model.libraryPreferences.setRecipe(looks[2].id, enabled: true)
        XCTAssertEqual(model.quickRecipes.map(\.id), [looks[0].id, looks[2].id])
        XCTAssertEqual(model.selectedRecipeID, looks[1].id)
        XCTAssertEqual(CameraPreviewGesturePolicy.targetRecipe(in: model.quickNavigationRecipes,
            selectedIdentifier: model.selectedRecipeID, direction: .next)?.id, looks[2].id)
        XCTAssertEqual(CameraPreviewGesturePolicy.targetRecipe(in: model.quickNavigationRecipes,
            selectedIdentifier: model.selectedRecipeID, direction: .previous)?.id, looks[0].id)
    }
}
