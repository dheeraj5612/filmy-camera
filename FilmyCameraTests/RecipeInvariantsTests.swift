import Foundation
import XCTest
@testable import FilmyCamera

final class RecipeInvariantsTests: XCTestCase {
    private let selectedRecipeKey = "selectedRecipeID"
    private let recipeOverridesKey = "recipeOverrides"
    private var hadSelectedRecipeValue = false
    private var previousSelectedRecipeID: String?
    private var hadRecipeOverridesValue = false
    private var previousRecipeOverrides: Data?

    override func setUp() {
        super.setUp()

        let defaults = UserDefaults.standard
        hadSelectedRecipeValue = defaults.object(forKey: selectedRecipeKey) != nil
        previousSelectedRecipeID = defaults.string(forKey: selectedRecipeKey)
        hadRecipeOverridesValue = defaults.object(forKey: recipeOverridesKey) != nil
        previousRecipeOverrides = defaults.data(forKey: recipeOverridesKey)
        defaults.removeObject(forKey: selectedRecipeKey)
        defaults.removeObject(forKey: recipeOverridesKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard

        if hadSelectedRecipeValue {
            defaults.set(previousSelectedRecipeID, forKey: selectedRecipeKey)
        } else {
            defaults.removeObject(forKey: selectedRecipeKey)
        }

        if hadRecipeOverridesValue {
            defaults.set(previousRecipeOverrides, forKey: recipeOverridesKey)
        } else {
            defaults.removeObject(forKey: recipeOverridesKey)
        }

        super.tearDown()
    }

    func testBuiltInRecipesHaveUniqueStableIdentityAndDisplayValues() {
        let recipes = FilmRecipe.builtIns

        XCTAssertFalse(recipes.isEmpty)
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count)
        XCTAssertEqual(Set(recipes.map(\.name)).count, recipes.count)

        for recipe in recipes {
            XCTAssertFalse(recipe.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(recipe.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testEverySelectableMonochromeFilterHasABuiltInRecipe() {
        let builtInBases = Set(FilmRecipe.builtIns.map(\.filmBase))
        XCTAssertTrue(builtInBases.contains(.acros))
        XCTAssertTrue(builtInBases.contains(.acrosYellow))
        XCTAssertTrue(builtInBases.contains(.acrosRed))
        XCTAssertTrue(builtInBases.contains(.acrosGreen))
        XCTAssertTrue(builtInBases.contains(.monochrome))
    }

    func testBuiltInRecipeControlsStayWithinNormalizedEditorBounds() {
        for recipe in FilmRecipe.builtIns {
            XCTAssertTrue(FilmRecipe.DynamicRange.allCases.contains(recipe.dynamicRange), recipe.id)

            for control in FilmRecipe.Control.allCases {
                let value = control.value(in: recipe)
                XCTAssertTrue(
                    control.editorRange.contains(value),
                    "\(recipe.id): \(control.rawValue)=\(value) outside editor range"
                )
            }

            XCTAssertTrue(recipe.isValid, "\(recipe.id): \(recipe.validationIssues)")
        }
    }

    func testBuiltInRecipeControlsAreFinite() {
        for recipe in FilmRecipe.builtIns {
            let values = [
                recipe.exposure,
                recipe.tone.highlight,
                recipe.tone.shadow,
                recipe.saturation,
                recipe.contrast,
                Double(recipe.dynamicRange.rawValue),
                recipe.whiteBalance.temperature,
                recipe.whiteBalance.tint,
                recipe.colorChrome,
                recipe.blueResponse,
                recipe.fxBlue,
                recipe.sharpness,
                recipe.noiseReduction,
                recipe.clarity,
                recipe.grain,
                recipe.grainSize,
                recipe.vignette,
                recipe.halation,
                recipe.palette.redBias,
                recipe.palette.greenBias,
                recipe.palette.blueBias,
                recipe.palette.redGreenMix,
                recipe.palette.greenBlueMix,
                recipe.palette.blueRedMix,
                recipe.palette.saturation
            ]

            XCTAssertTrue(values.allSatisfy(\.isFinite), recipe.id)
        }
    }

    func testRecipeRoundTripsThroughPersistentRepresentation() throws {
        let original = FilmRecipe.builtIns[0]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilmRecipe.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, FilmRecipe.currentSchemaVersion)
        XCTAssertEqual(decoded.provenance, FilmRecipe.currentProvenance)
    }

    @MainActor
    func testPersistedOverridesMigrateToCurrentNamesAndUserProvenance() throws {
        let original = FilmRecipe.builtIns[1]
        let encoded = try JSONEncoder().encode(original)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject["schemaVersion"] = 2
        legacyObject["name"] = "Classic Chrome"
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let overrides = try JSONEncoder().encode([
            original.id: try JSONDecoder().decode(FilmRecipe.self, from: legacyData)
        ])

        UserDefaults.standard.set(original.id, forKey: selectedRecipeKey)
        UserDefaults.standard.set(overrides, forKey: recipeOverridesKey)

        let viewModel = CameraViewModel()

        XCTAssertEqual(viewModel.selectedRecipe.name, "Muted Color")
        XCTAssertEqual(viewModel.selectedRecipe.provenance.source, .userModified)
        XCTAssertEqual(viewModel.selectedRecipe.provenance.parentRecipeID, original.id)
        XCTAssertEqual(viewModel.selectedRecipe.schemaVersion, FilmRecipe.currentSchemaVersion)
    }

    func testBuiltInRecipesExposeCompleteApproximationProvenance() {
        for recipe in FilmRecipe.builtIns {
            XCTAssertEqual(recipe.schemaVersion, FilmRecipe.currentSchemaVersion, recipe.id)
            XCTAssertTrue(recipe.provenance.isComplete, recipe.id)
            XCTAssertEqual(recipe.provenance.source, .publicOfficialDocumentation, recipe.id)
            XCTAssertEqual(recipe.provenance.implementation, .originalParametricApproximation, recipe.id)
            XCTAssertEqual(recipe.provenance.calibration, .notCalibratedToFujifilmHardware, recipe.id)
            XCTAssertEqual(recipe.provenance.references, FilmRecipe.PublicReference.allCases, recipe.id)

            for reference in recipe.provenance.references {
                XCTAssertTrue(reference.url.hasPrefix("https://"), reference.rawValue)
                XCTAssertFalse(reference.title.isEmpty, reference.rawValue)
                XCTAssertFalse(reference.scope.isEmpty, reference.rawValue)
            }

            let disclaimer = recipe.provenance.disclaimer
            XCTAssertTrue(disclaimer.contains("original approximations"), recipe.id)
            XCTAssertTrue(disclaimer.contains("not pixel-identical"), recipe.id)
            XCTAssertTrue(disclaimer.contains("not affiliated"), recipe.id)
            XCTAssertTrue(disclaimer.contains("no proprietary LUTs"), recipe.id)
        }
    }

    func testControlContractHasStableSemanticsAndUniqueIdentifiers() {
        let controls = FilmRecipe.Control.allCases
        XCTAssertFalse(controls.isEmpty)
        XCTAssertEqual(Set(controls.map(\.rawValue)).count, controls.count)

        for control in controls {
            XCTAssertLessThan(control.editorRange.lowerBound, control.editorRange.upperBound, control.rawValue)
            XCTAssertFalse(control.displayName.isEmpty, control.rawValue)
            XCTAssertFalse(control.semanticDescription.isEmpty, control.rawValue)
        }

        XCTAssertEqual(FilmRecipe.Control.exposure.unit, .exposureEV)
        XCTAssertEqual(FilmRecipe.Control.color.unit, .multiplier)
        XCTAssertEqual(FilmRecipe.Control.grainSize.unit, .normalizedSize)
        XCTAssertEqual(FilmRecipe.Control.exposure.editorRange, -2.0...2.0)
        XCTAssertEqual(FilmRecipe.Control.grainSize.editorRange, 0.35...2.5)
    }

    func testLegacyRecipeWithoutProvenanceRemainsReadableButFailsAudit() throws {
        let original = FilmRecipe.builtIns[0]
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "schemaVersion")
        object.removeValue(forKey: "provenance")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(FilmRecipe.self, from: legacyData)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.subtitle, original.subtitle)
        XCTAssertEqual(decoded.filmBase, original.filmBase)
        XCTAssertEqual(decoded.exposure, original.exposure)
        XCTAssertEqual(decoded.tone, original.tone)
        XCTAssertEqual(decoded.saturation, original.saturation)
        XCTAssertEqual(decoded.contrast, original.contrast)
        XCTAssertEqual(decoded.dynamicRange, original.dynamicRange)
        XCTAssertEqual(decoded.whiteBalance, original.whiteBalance)
        XCTAssertEqual(decoded.palette, original.palette)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.provenance, FilmRecipe.legacyProvenance)
        XCTAssertFalse(decoded.provenance.isComplete)
        XCTAssertTrue(decoded.validationIssues.contains { $0.code == .provenanceUnavailable })
        XCTAssertFalse(decoded.isValid)
    }

    func testValidationFindsNonFiniteAndMonochromeInvariantViolations() {
        var nonFinite = FilmRecipe.builtIns[0]
        nonFinite.exposure = .infinity
        XCTAssertTrue(nonFinite.validationIssues.contains {
            $0.code == .nonFiniteControl && $0.control == .exposure
        })

        var coloredMonochrome = FilmRecipe.builtIns.first { $0.filmBase == .acros }!
        coloredMonochrome.saturation = 0.25
        coloredMonochrome.palette.saturation = 0.25
        XCTAssertTrue(coloredMonochrome.validationIssues.contains { $0.code == .monochromeColorMustBeZero })
        XCTAssertTrue(coloredMonochrome.validationIssues.contains { $0.code == .monochromePaletteSaturationMustBeZero })
    }

    func testSelectedRecipePersistsAcrossViewModelInstances() async {
        let expected = FilmRecipe.builtIns[2]
        let model = await CameraViewModel()

        await model.select(recipe: expected)

        let storedID = UserDefaults.standard.string(forKey: selectedRecipeKey)
        let reloadedModel = await CameraViewModel()
        let reloadedID = await reloadedModel.selectedRecipeID
        let reloadedRecipe = await reloadedModel.selectedRecipe

        XCTAssertEqual(storedID, expected.id)
        XCTAssertEqual(reloadedID, expected.id)
        XCTAssertEqual(reloadedRecipe, expected)
    }

    func testCustomizedRecipePersistsAndResetRestoresBuiltIn() async {
        let original = FilmRecipe.builtIns[1]
        var customized = original
        customized.exposure = 1.25
        customized.tone = FilmRecipe.Tone(highlight: -0.45, shadow: 0.60)
        customized.grain = 0.72
        customized.palette.blueBias = 0.18

        let model = await CameraViewModel()
        await model.select(recipe: original)
        await model.update(recipe: customized)

        let reloadedModel = await CameraViewModel()
        let reloadedRecipe = await reloadedModel.selectedRecipe
        let isCustomizedBeforeReset = await reloadedModel.isCustomized(original)

        XCTAssertEqual(reloadedRecipe.exposure, customized.exposure)
        XCTAssertEqual(reloadedRecipe.tone, customized.tone)
        XCTAssertEqual(reloadedRecipe.grain, customized.grain)
        XCTAssertEqual(reloadedRecipe.palette, customized.palette)
        XCTAssertEqual(reloadedRecipe.provenance.source, .userModified)
        XCTAssertEqual(reloadedRecipe.provenance.parentRecipeID, original.id)
        XCTAssertEqual(reloadedRecipe.provenance.rendererVersion, FilmRecipe.rendererVersion)
        XCTAssertTrue(reloadedRecipe.provenance.isComplete)
        XCTAssertTrue(isCustomizedBeforeReset)

        await reloadedModel.reset(recipeID: original.id)

        let resetRecipe = await reloadedModel.selectedRecipe
        let isCustomizedAfterReset = await reloadedModel.isCustomized(original)
        XCTAssertEqual(resetRecipe, original)
        XCTAssertFalse(isCustomizedAfterReset)
    }

    func testUnknownPersistedSelectionFallsBackToFirstBuiltInRecipe() async {
        UserDefaults.standard.set("recipe-that-no-longer-exists", forKey: selectedRecipeKey)

        let model = await CameraViewModel()
        let persistedID = await model.selectedRecipeID
        let resolvedRecipe = await model.selectedRecipe

        XCTAssertEqual(persistedID, "recipe-that-no-longer-exists")
        XCTAssertEqual(resolvedRecipe, FilmRecipe.builtIns[0])
    }

    func testCaptureFailureReturnsToIdleWithoutLeavingAReviewFrame() async {
        let model = await CameraViewModel()
        let camera = CameraService()

        // The session is intentionally never started. CameraService must
        // report this as a clean, recoverable capture failure on any device.
        await model.capture(camera: camera)

        for _ in 0..<100 {
            if await model.isCapturing == false { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let isCapturing = await model.isCapturing
        let reviewImage = await model.reviewImage
        let reviewRecipe = await model.reviewRecipe
        let toastMessage = await model.toastMessage
        let toastStyle = await model.toastStyle

        XCTAssertFalse(isCapturing)
        XCTAssertNil(reviewImage)
        XCTAssertNil(reviewRecipe)
        XCTAssertEqual(toastMessage, "Capture could not be completed. Resume the camera and try again.")
        XCTAssertEqual(toastStyle, .error)
    }

    func testSchemaTwoRecordWithCurrentLookingProvenanceFailsCurrentAudit() throws {
        let original = FilmRecipe.builtIns[0]
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 2
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(FilmRecipe.self, from: legacyData)

        XCTAssertEqual(decoded.provenance.rendererVersion, FilmRecipe.rendererVersion)
        XCTAssertTrue(decoded.provenance.isComplete)
        XCTAssertTrue(decoded.validationIssues.contains { $0.code == .provenanceUnavailable })
        XCTAssertFalse(decoded.isValid)
    }
}
