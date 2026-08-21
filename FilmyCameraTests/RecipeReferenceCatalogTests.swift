import Foundation
import XCTest
@testable import FilmyCamera

final class RecipeReferenceCatalogTests: XCTestCase {
    func testCatalogCoversTheSixteenCoreReferenceLooks() {
        let entries = FilmRecipeReferenceCatalog.entries

        XCTAssertEqual(FilmRecipeReferenceCatalog.referenceLookCount, 16)
        XCTAssertEqual(entries.count, 16)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(Set(entries.map(\.currentRecipeID)).count, entries.count)
        XCTAssertEqual(
            Set(entries.map(\.currentRecipeID)),
            Set(FilmRecipe.builtIns.map(\.id).filter {
                !["sepia-archive", "g7x-compact"].contains($0)
            })
        )
        XCTAssertEqual(
            FilmRecipeReferenceCatalog.document.intentionallyUnlistedBuiltInRecipeIDs,
            ["sepia-archive", "g7x-compact"]
        )
    }

    func testCatalogEntriesResolveToCurrentRecipeAndPublicFilmBase() {
        for entry in FilmRecipeReferenceCatalog.entries {
            let recipe = try? XCTUnwrap(entry.currentRecipe)
            XCTAssertNotNil(recipe, entry.currentRecipeID)
            XCTAssertEqual(recipe?.id, entry.currentRecipeID)
            XCTAssertEqual(recipe?.filmBase, entry.currentFilmBase, entry.currentRecipeID)
            XCTAssertTrue(
                entry.canonicalPublicName.hasPrefix(entry.currentFilmBase.officialName),
                entry.currentRecipeID
            )
            XCTAssertFalse(entry.note.isEmpty, entry.currentRecipeID)
        }
    }

    func testPriorPresetSnapshotsPreserveEveryPublicControl() {
        let expected: [String: FilmRecipeReferenceCatalog.PublicControls] = [
            "provia-standard": .init(
                filmSimulation: "provia", dynamicRange: "auto", highlightTone: 0, shadowTone: 0, color: 0,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: 0, noiseReduction: 0, clarity: 0,
                grainEffect: "off", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "classic-chrome": .init(
                filmSimulation: "classic_chrome", dynamicRange: "dr200", highlightTone: 0, shadowTone: 1, color: -1,
                colorChromeEffect: "weak", colorChromeFXBlue: "off", sharpness: 0, noiseReduction: 0, clarity: 0,
                grainEffect: "weak", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "velvia-vivid": .init(
                filmSimulation: "velvia", dynamicRange: "dr200", highlightTone: 0, shadowTone: 0, color: 2,
                colorChromeEffect: "weak", colorChromeFXBlue: "weak", sharpness: 1, noiseReduction: 0, clarity: 1,
                grainEffect: "off", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "astia-soft": .init(
                filmSimulation: "astia", dynamicRange: "dr200", highlightTone: -1, shadowTone: 0, color: 0,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: -1, noiseReduction: 1, clarity: -1,
                grainEffect: "off", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 1,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0.3
            ),
            "pro-neg-high": .init(
                filmSimulation: "pro_neg_hi", dynamicRange: "dr200", highlightTone: 1, shadowTone: -1, color: -1,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: 1, noiseReduction: 0, clarity: 1,
                grainEffect: "off", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "pro-neg-standard": .init(
                filmSimulation: "pro_neg_std", dynamicRange: "dr200", highlightTone: -1, shadowTone: 1, color: -1,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: -1, noiseReduction: 1, clarity: -1,
                grainEffect: "off", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 1,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "eterna-cinema": .init(
                filmSimulation: "eterna", dynamicRange: "dr400", highlightTone: -2, shadowTone: 2, color: -2,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: -1, noiseReduction: 0, clarity: 0,
                grainEffect: "off", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "eterna-bleach-bypass": .init(
                filmSimulation: "eterna_bleach_bypass", dynamicRange: "dr200", highlightTone: 2, shadowTone: -1, color: -3,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: 1, noiseReduction: 0, clarity: 2,
                grainEffect: "weak", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "acros-neutral-filter": .init(
                filmSimulation: "acros", dynamicRange: "dr200", highlightTone: 0, shadowTone: 0, color: 0,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: 1, noiseReduction: 0, clarity: 1,
                grainEffect: "weak", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "acros-yellow-filter": .init(
                filmSimulation: "acros_ye", dynamicRange: "dr200", highlightTone: 1, shadowTone: 0, color: 0,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: 1, noiseReduction: 0, clarity: 1,
                grainEffect: "weak", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "acros-red-filter": .init(
                filmSimulation: "acros_r", dynamicRange: "dr200", highlightTone: 2, shadowTone: -1, color: 0,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: 2, noiseReduction: 0, clarity: 2,
                grainEffect: "weak", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "acros-green-filter": .init(
                filmSimulation: "acros_g", dynamicRange: "dr200", highlightTone: -1, shadowTone: 1, color: 0,
                colorChromeEffect: "off", colorChromeFXBlue: "off", sharpness: 0, noiseReduction: 1, clarity: 0,
                grainEffect: "weak", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 0, exposureCompensationEV: 0
            ),
            "classic-negative": .init(
                filmSimulation: "classic_neg", dynamicRange: "dr200", highlightTone: 0, shadowTone: 2, color: 2,
                colorChromeEffect: "strong", colorChromeFXBlue: "weak", sharpness: 0, noiseReduction: 0, clarity: 0,
                grainEffect: "weak", grainSize: "small", whiteBalance: "daylight", whiteBalanceShiftRed: 3,
                whiteBalanceShiftBlue: -2, exposureCompensationEV: 0.3
            ),
            "nostalgic-negative": .init(
                filmSimulation: "nostalgic_neg", dynamicRange: "dr200", highlightTone: -1, shadowTone: 2, color: 1,
                colorChromeEffect: "weak", colorChromeFXBlue: "weak", sharpness: 0, noiseReduction: 0, clarity: 0,
                grainEffect: "weak", grainSize: "large", whiteBalance: "daylight", whiteBalanceShiftRed: 4,
                whiteBalanceShiftBlue: -3, exposureCompensationEV: 0
            ),
            "reala-ace": .init(
                filmSimulation: "reala_ace", dynamicRange: "dr200", highlightTone: 0, shadowTone: 0, color: -1,
                colorChromeEffect: "off", colorChromeFXBlue: "weak", sharpness: 0, noiseReduction: 0, clarity: 0,
                grainEffect: "off", grainSize: "small", whiteBalance: "auto", whiteBalanceShiftRed: 0,
                whiteBalanceShiftBlue: 1, exposureCompensationEV: 0
            )
        ]

        XCTAssertEqual(expected.count, 15)
        for entry in FilmRecipeReferenceCatalog.entries where entry.settingsSource == .priorPrivateRepositoryPresetSnapshot {
            XCTAssertEqual(entry.publicControls, expected[entry.currentRecipeID], entry.currentRecipeID)
            XCTAssertNotNil(entry.priorPresetID, entry.currentRecipeID)
            XCTAssertNotNil(entry.priorPresetName, entry.currentRecipeID)
            XCTAssertNotNil(entry.priorPresetOrdinal, entry.currentRecipeID)
        }
    }

    func testCurrentOnlyBaselineAndApproximationDisclosureAreExplicit() {
        let baseline = FilmRecipeReferenceCatalog.entries.first { $0.currentRecipeID == "acros-monochrome" }
        XCTAssertEqual(baseline?.settingsSource, .currentAppPublicBaseline)
        XCTAssertNil(baseline?.publicControls)
        XCTAssertTrue(baseline?.note.contains("normalized baseline") == true)

        let disclosure = FilmRecipeReferenceCatalog.document.disclosure
        XCTAssertTrue(disclosure.contains("original approximations"))
        XCTAssertTrue(disclosure.contains("not pixel-identical"))
        XCTAssertTrue(disclosure.contains("not affiliated"))
        XCTAssertTrue(disclosure.contains("no proprietary LUTs"))
        XCTAssertFalse(disclosure.contains("exact hardware"))
    }

    func testCatalogJSONRoundTripsWithStableSourceProvenance() throws {
        let data = try FilmRecipeReferenceCatalog.jsonData(prettyPrinted: true)
        let decoded = try JSONDecoder().decode(FilmRecipeReferenceCatalog.Document.self, from: data)

        XCTAssertEqual(decoded, FilmRecipeReferenceCatalog.document)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.sourceSnapshot.commit, "8d2698881f602c37ddce0585890cbf729db867ca")
        XCTAssertEqual(
            decoded.sourceSnapshot.path,
            "FilmyCam/FilmyCam/Domain/Models/FujifilmRecipe+Presets.swift"
        )
    }
}
