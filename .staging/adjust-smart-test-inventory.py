from pathlib import Path

path = Path('scripts/testing/test_runner.py')
source = path.read_text()
anchor = '            "FilmyCameraUITests/FilmyCameraUITests/testViewfinderFirstChromePreviewKeepsCameraQuiet",\n'
assert source.count(anchor) == 1
source = source.replace(anchor, anchor
    + '            "FilmyCameraUITests/SmartRecipeUITests/testSmartLooksIsDiscoverableAndUnavailableSceneHasNoApplyAction",\n'
    + '            "FilmyCameraUITests/SmartRecipeUITests/testDisablingSuggestionsPersistsAcrossRelaunch",\n', 1)
path.write_text(source)
print('Extended exact simulator-only test inventory while preserving all routing assertions.')

path = Path('FilmyCamera/Models/SmartRecipeEngine.swift')
source = path.read_text()
old = '            (.food, ["food", "meal", "dish", "dessert", "fruit", "bread", "cake", "coffee", "drink", "beverage"]),'
new = '''            (.food, ["food", "meal", "dish", "dessert", "fruit", "bread", "cake", "coffee", "drink", "beverage",
                     "ice_cream", "icecream", "snow_cone", "hot_dog", "street_food", "pizza", "pasta", "sandwich", "salad", "sushi"]),'''
assert source.count(old) == 1
source = source.replace(old, new, 1)
anchor = '            let tokens = Set(normalized.split(separator: "_").map(String.init)).union([normalized])'
assert source.count(anchor) == 1
source = source.replace(anchor, '''            // Whole concepts take precedence: ice cream is food, not evidence of snow.
            if let exact = vocabulary.first(where: { $0.1.contains(normalized) }) {
                evidence[exact.0] = max(evidence[exact.0, default: 0], min(observation.confidence, 1))
                continue
            }
''' + anchor, 1)
old = 'let targetContrast: Double = scene.hasFaces || scene.metrics.isHighContrast || scene.metrics.isDark ? 0.98 : 1.06'
assert source.count(old) == 1
source = source.replace(old, 'let targetContrast: Double = scene.hasFaces || scene.kind == .people\n                || scene.metrics.isHighContrast || scene.metrics.isDark ? 0.98 : 1.06', 1)
old = 'if scene.hasFaces || scene.kind == .food {'
assert source.count(old) == 1
source = source.replace(old, 'if scene.hasFaces || scene.kind == .people || scene.kind == .food {', 1)
path.write_text(source)
path = Path('FilmyCameraTests/SmartRecipeEngineTests.swift')
source = path.read_text()
anchor = '    func testEverySceneAndIntentHasDeterministicFiniteResults() {'
assert source.count(anchor) == 1
source = source.replace(anchor, '''    func testCompoundFoodLabelsDoNotMasqueradeAsSnowOrStreets() {
        for label in ["ice_cream", "ice cream", "icecream", "snow_cone", "hot_dog", "street_food", "pizza", "sushi"] {
            let interpreted = SmartScene.interpret(metrics: .init(),
                classifications: [.init(identifier: label, confidence: 0.9)])
            XCTAssertEqual(interpreted?.kind, .food, label)
        }
        XCTAssertEqual(SmartScene.interpret(metrics: .init(),
            classifications: [.init(identifier: "ice", confidence: 0.9)])?.kind, .snow)
    }

    func testPeopleClassificationProtectsColorWithoutAVisibleFace() {
        let candidates = [SmartRecipeProfile(id: "a-warm", family: "astia", warmth: 0.8),
                          .init(id: "b-neutral", family: "astia")]
        XCTAssertEqual(SmartRecipeEngine.rank(scene: scene(.people), profiles: candidates).first?.id, "b-neutral")
    }

''' + anchor, 1)
path.write_text(source)
print('Added compound-label disambiguation and full-body portrait color protection with regressions.')
