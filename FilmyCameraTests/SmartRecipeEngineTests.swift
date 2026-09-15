import XCTest
@testable import FilmyCamera

final class SmartRecipeEngineTests: XCTestCase {
    private var profiles: [SmartRecipeProfile] {
        [.init(id: "portrait", family: "astia", contrast: 0.98),
         .init(id: "natural", family: "realaAce"), .init(id: "daylight", family: "provia"),
         .init(id: "vivid", family: "velvia", contrast: 1.08, saturation: 1.16),
         .init(id: "cinema", family: "eterna", contrast: 0.96, saturation: 0.90),
         .init(id: "street", family: "classicChrome"), .init(id: "warm", family: "nostalgicNegative", warmth: 0.12),
         .init(id: "bw", family: "acros"), .init(id: "mono", family: "monochrome"), .init(id: "sepia", family: "sepia")]
    }
    private func scene(_ kind: SmartSceneKind, faces: Bool = false, metrics: SmartSceneMetrics = .init()) -> SmartScene {
        SmartScene(kind: kind, evidence: 0.9, metrics: metrics, hasFaces: faces)
    }
    func testFacesFavorGentlePortraitControls() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.people, faces: true), profiles: profiles).first?.id, "portrait")
    }
    func testNatureOffersVividColor() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.landscape), profiles: profiles).first?.id, "vivid")
    }
    func testFoodFavorsNaturalColor() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.food), profiles: profiles).first?.id, "natural")
    }
    func testStreetFavorsRestrainedPalette() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.architecture), profiles: profiles).first?.id, "street")
    }
    func testWarmLightFavorsWarmNegativeFamily() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.warmLight), profiles: profiles).first?.id, "warm")
    }
    func testLowLightPenalizesGrainWithoutInferringSensorISO() {
        let dark = SmartSceneMetrics(luminance: 0.18, low: 0.04, high: 0.50)
        let candidates = [SmartRecipeProfile(id: "clean", family: "eterna"), .init(id: "grainy", family: "eterna", grain: 0.9)]
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.night, metrics: dark), profiles: candidates).first?.id, "clean")
    }
    func testHighContrastRewardsGentlerHighlights() {
        let metrics = SmartSceneMetrics(luminance: 0.5, low: 0.03, high: 0.95)
        let candidates = [SmartRecipeProfile(id: "hard", family: "realaAce", highlights: 0.3),
                          .init(id: "soft", family: "realaAce", highlights: -0.2, highlightProtection: 0.3)]
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday, metrics: metrics), profiles: candidates).first?.id, "soft")
    }
    func testNaturalIntentAvoidsExtremeWarmth() {
        let candidates = [SmartRecipeProfile(id: "neutral", family: "realaAce"), .init(id: "warm", family: "realaAce", warmth: 0.9)]
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: candidates, intent: .natural).first?.id, "neutral")
    }
    func testExplicitVividIntentWinsOverGeneralPreference() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles, intent: .vivid).first?.id, "vivid")
    }
    func testCinemaIntentOffersCinemaFamily() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles, intent: .cinematic).first?.id, "cinema")
    }
    func testMonochromeIntentNeverReturnsColorOrSepia() {
        XCTAssertEqual(Set(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles, intent: .monochrome).map(\.id)), ["bw", "mono"])
    }
    func testColorIntentsNeverReturnMonochrome() {
        for intent in [SmartRecipeIntent.natural, .vivid, .cinematic] {
            XCTAssertTrue(Set(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles, intent: intent).map(\.id))
                .isDisjoint(with: ["bw", "mono", "sepia"]))
        }
    }
    func testBalancedOffersAtMostOneMonochromeAlternative() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles.filter(\.isMonochrome)).count, 1)
    }
    func testEmptyCatalogAndInvalidLimitAreEmpty() {
        XCTAssertTrue(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: []).isEmpty)
        XCTAssertTrue(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles, limit: 0).isEmpty)
        XCTAssertTrue(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles, limit: -1).isEmpty)
    }
    func testOnlyAvailableUniqueIDsAreReturned() {
        let available = Array(profiles.prefix(2))
        let result = SmartRecipeEngine.rank(scene: scene(.everyday), profiles: available + available)
        XCTAssertEqual(Set(result.map(\.id)), Set(available.map(\.id)))
        XCTAssertEqual(result.count, available.count)
    }
    func testAlwaysCapsSuggestionsAtThree() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: profiles, limit: 100).count, 3)
    }
    func testStableTiesIgnoreCatalogOrder() {
        let a = SmartRecipeProfile(id: "a", family: "provia")
        let b = SmartRecipeProfile(id: "b", family: "provia")
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: [b, a]).map(\.id), ["a", "b"])
    }
    func testRecipeEditsChangeRankingWithoutMatchingNames() {
        let original = SmartRecipeProfile(id: "original", family: "astia", contrast: 0.98)
        var edited = original
        edited.saturation = 2
        edited.contrast = 1.6
        let fallback = SmartRecipeProfile(id: "fallback", family: "realaAce")
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.people, faces: true), profiles: [original, fallback]).first?.id, "original")
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.people, faces: true), profiles: [edited, fallback]).first?.id, "fallback")
    }
    func testDiversityPrefersDifferentFamiliesOverNearDuplicates() {
        let input = [SmartRecipeProfile(id: "a", family: "realaAce"), .init(id: "b", family: "realaAce"),
                     .init(id: "c", family: "realaAce"), .init(id: "d", family: "provia")]
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.everyday), profiles: input)[1].id, "d")
    }
    func testFavoriteBonusIsSmallAndCannotOverrideBadFit() {
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.people, faces: true), profiles: profiles, favoriteIDs: ["vivid"]).first?.id, "portrait")
    }
    func testNonfiniteControlsAndOverflowScoresAreExcluded() {
        let invalid = [SmartRecipeProfile(id: "nan", family: "astia", contrast: .nan),
                       .init(id: "infinite", family: "astia", saturation: .infinity),
                       .init(id: "huge", family: "astia", saturation: .greatestFiniteMagnitude)]
        XCTAssertTrue(SmartRecipeEngine.rank(scene: scene(.people, faces: true), profiles: invalid).isEmpty)
    }
    func testInvalidImageMetricsAreRejected() {
        XCTAssertNil(SmartScene.interpret(metrics: .init(luminance: .nan), classifications: []))
        XCTAssertTrue(SmartRecipeEngine.rank(scene: scene(.everyday, metrics: .init(high: .infinity)), profiles: profiles).isEmpty)
    }
    func testConfidentVisionLabelsClassifyScenes() {
        let cases: [(String, SmartSceneKind)] = [("food", .food), ("city_street", .architecture), ("mountain", .landscape),
                                               ("sunset", .warmLight), ("flower", .flowers), ("beach", .water), ("snow", .snow)]
        for (label, expected) in cases {
            XCTAssertEqual(SmartScene.interpret(metrics: .init(), classifications: [.init(identifier: label, confidence: 0.8)])?.kind, expected)
        }
    }
    func testWeakSynonymsDoNotInventConfidence() {
        let labels = ["forest", "mountain", "nature"].map { SmartSceneClassification(identifier: $0, confidence: 0.26) }
        XCTAssertEqual(SmartScene.interpret(metrics: .init(), classifications: labels)?.kind, .everyday)
    }
    func testUnknownOrInvalidLabelsUseLightFallback() {
        let labels = [SmartSceneClassification(identifier: "food", confidence: .nan), .init(identifier: "dog", confidence: 0.99)]
        XCTAssertEqual(SmartScene.interpret(metrics: .init(), classifications: labels)?.kind, .everyday)
    }
    func testDetectedFaceProtectsPortraitEvenInFoliage() {
        let interpreted = SmartScene.interpret(metrics: .init(greenFraction: 0.8),
            classifications: [.init(identifier: "forest", confidence: 0.8)], faceCount: 1, faceCoverage: 0.15)
        XCTAssertEqual(interpreted?.kind, .people)
        XCTAssertEqual(interpreted?.hasFaces, true)
    }
    func testPaletteAloneDoesNotAssertAnOutdoorScene() {
        XCTAssertEqual(SmartScene.interpret(metrics: .init(greenFraction: 0.8), classifications: [])?.kind, .everyday)
        XCTAssertEqual(SmartScene.interpret(metrics: .init(warmth: 0.25), classifications: [])?.kind, .warmLight)
    }
    func testDarkMetricsGiveConservativeLowLightLabel() {
        XCTAssertEqual(SmartScene.interpret(metrics: .init(luminance: 0.15, low: 0.03, high: 0.4), classifications: [])?.kind, .night)
    }
    func testBlackWhiteTransparentAndMalformedPixelsDoNotProduceSuggestions() {
        for pixel: [UInt8] in [[0, 0, 0, 255], [255, 255, 255, 255]] {
            XCTAssertFalse(SmartSceneMetrics.measure(rgba: Array(repeating: pixel, count: 64).flatMap { $0 })?.isUsable ?? true)
        }
        XCTAssertNil(SmartSceneMetrics.measure(rgba: [UInt8](repeating: 0, count: 256)))
        XCTAssertNil(SmartSceneMetrics.measure(rgba: [1, 2, 3]))
        XCTAssertNil(SmartSceneMetrics.measure(rgba: [UInt8](repeating: 128, count: 65)))
    }
    func testPixelMetricsMeasurePaletteAndExcludeTransparentSamples() throws {
        let bytes = Array(repeating: [UInt8](arrayLiteral: 40, 150, 50, 255), count: 32).flatMap { $0 }
            + Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 0), count: 32).flatMap { $0 }
        let metrics = try XCTUnwrap(SmartSceneMetrics.measure(rgba: bytes))
        XCTAssertEqual(metrics.greenFraction, 1, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.luminance, 0.4)
        XCTAssertTrue(metrics.isUsable)
    }
    func testStabilizerRequiresTwoObservationsAndDwell() {
        var stabilizer = SmartRecipeStabilizer()
        XCTAssertFalse(stabilizer.shouldPublish(signature: "a", now: 0))
        XCTAssertTrue(stabilizer.shouldPublish(signature: "a", now: 1.5))
        XCTAssertFalse(stabilizer.shouldPublish(signature: "b", now: 2))
        XCTAssertFalse(stabilizer.shouldPublish(signature: "b", now: 3.5))
        XCTAssertTrue(stabilizer.shouldPublish(signature: "b", now: 5))
        XCTAssertFalse(stabilizer.shouldPublish(signature: "b", now: 7))
    }
    func testStabilizerResetsWhenFrameContextChanges() {
        var stabilizer = SmartRecipeStabilizer()
        XCTAssertTrue(stabilizer.shouldPublish(signature: "a", now: 1, force: true))
        stabilizer.reset()
        XCTAssertFalse(stabilizer.shouldPublish(signature: "a", now: 2))
        XCTAssertNil(stabilizer.displayed)
        XCTAssertFalse(stabilizer.shouldPublish(signature: "a", now: .nan))
    }
    func testInFlightGateDropsExtraFramesAndRejectsStaleCompletion() throws {
        var gate = SmartRecipeAnalysisGate()
        let ticket = try XCTUnwrap(gate.begin(now: 0, interval: 1.5))
        XCTAssertNil(gate.begin(now: 2, interval: 1.5))
        gate.invalidate()
        XCTAssertNil(gate.begin(now: 3, interval: 1.5))
        XCTAssertFalse(gate.finish(ticket))
        XCTAssertNotNil(gate.begin(now: 3, interval: 1.5))
    }
    func testGateHonorsThrottleAndNeverReleasesAnotherRequestsLease() throws {
        var gate = SmartRecipeAnalysisGate()
        let old = try XCTUnwrap(gate.begin(now: 0, interval: 4))
        XCTAssertTrue(gate.finish(old))
        XCTAssertNil(gate.begin(now: 3, interval: 4))
        let current = try XCTUnwrap(gate.begin(now: 4, interval: 4))
        XCTAssertFalse(gate.finish(old))
        XCTAssertEqual(gate.inFlight, current)
        XCTAssertTrue(gate.finish(current))
        XCTAssertNil(gate.begin(now: .nan, interval: 1.5))
        XCTAssertNil(gate.begin(now: 10, interval: 0))
    }
    func testUndoNeverOverwritesSubsequentManualSelection() {
        let undo = SmartRecipeUndo(previousID: "a", appliedID: "b")
        XCTAssertEqual(undo.target(currentID: "b", availableIDs: ["a", "b"]), "a")
        XCTAssertNil(undo.target(currentID: "c", availableIDs: ["a", "b", "c"]))
        XCTAssertNil(undo.target(currentID: "b", availableIDs: ["b"]))
    }
    func testEverySceneAndIntentHasDeterministicFiniteResults() {
        for kind in SmartSceneKind.allCases {
            for intent in SmartRecipeIntent.allCases {
                let first = SmartRecipeEngine.rank(scene: scene(kind), profiles: profiles, intent: intent)
                XCTAssertEqual(first, SmartRecipeEngine.rank(scene: scene(kind), profiles: profiles.reversed(), intent: intent))
                XCTAssertTrue(first.allSatisfy { $0.score.isFinite && !$0.reason.isEmpty })
            }
        }
    }
}
