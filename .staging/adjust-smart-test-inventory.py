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
