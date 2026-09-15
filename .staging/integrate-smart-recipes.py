"""Exact-context integration against the pinned source. Not included in the feature branch."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path.cwd()
staged = Path(__file__).resolve().parent
path = root / 'FilmyCamera/Views/CameraScreen.swift'
data = path.read_bytes()
blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
assert blob == 'd227b5a4a7c2381f4eb076e3c6ebb9a89acd5cd8', f'CameraScreen changed: {blob}; reconcile first'
source = data.decode()

def replace(old, new):
    global source
    assert source.count(old) == 1, f'Expected one integration anchor: {old[:90]!r}'
    source = source.replace(old, new, 1)

replace('    @StateObject private var assists = CompositionAssistStore()\n', '''    @StateObject private var assists = CompositionAssistStore()
    @StateObject private var smartRecipes = SmartRecipeStore()
    @State private var isShowingSmartRecipes = false
    @State private var smartPresentation: SmartRecipeSnapshot?
''')
replace('        .onChange(of: assistOptions, initial: true)', '''        .onChange(of: isSmartRecipeAnalysisActive, initial: true) { _, _ in updateSmartRecipeAnalysis() }
        .onChange(of: viewModel.recipes) { _, _ in updateSmartRecipeAnalysis() }
        .onChange(of: favoriteData) { _, _ in updateSmartRecipeAnalysis() }
        .onChange(of: smartRecipeFrameKey) { _, _ in smartRecipes.invalidateScene() }
        .onChange(of: viewModel.selectedRecipeID) { _, selected in
            smartRecipes.reconcileSelection(currentID: selected, availableIDs: Set(viewModel.recipes.map(\\.id)))
        }
        .sheet(isPresented: $isShowingSmartRecipes, onDismiss: { smartPresentation = nil }) {
            SmartRecipeSheet(
                store: smartRecipes, snapshot: smartPresentation,
                selectedID: viewModel.selectedRecipeID, canApply: canApplySmartRecipe,
                onApply: applySmartRecipe, onClose: { isShowingSmartRecipes = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: assistOptions, initial: true)''')
replace('            assists.stop()\n            camera.stop(after: CameraActivityPolicy.inactiveGracePeriod)',
        '            assists.stop()\n            smartRecipes.stop()\n            camera.stop(after: CameraActivityPolicy.inactiveGracePeriod)')
replace('''            HStack(spacing: 8) {
                activeCaptureIndicators

                CameraStatusPill(''', '''            HStack(spacing: 8) {
                SmartRecipeEntryPoint(
                    store: smartRecipes, selectedID: viewModel.selectedRecipeID,
                    canApply: canApplySmartRecipe, onOpen: openSmartRecipes,
                    onApply: applySmartRecipe, onUndo: undoSmartRecipe
                )
                Spacer(minLength: 0)
                activeCaptureIndicators

                if !isLive {
                    CameraStatusPill(''')
replace('''                .opacity(isLive ? 0 : 1)
                .accessibilityHidden(isLive)
''', '''                }
''')
replace('''            && !isShowingManualControls && !isShowingCaptureSetup
''', '''            && !isShowingManualControls && !isShowingCaptureSetup && !isShowingSmartRecipes
''')
replace('    // MARK: - Actions\n', '''    // MARK: - Smart recipe suggestions

    private var canApplySmartRecipe: Bool {
        scenePhase == .active && isCameraTabActive && camera.isRunning
            && camera.availability == .running && !isChromeDisabled && !isReviewing
            && viewModel.reviewImage == nil && !countdown.state.isActive && !camera.manualControls.isApplying
    }

    private var isSmartRecipeAnalysisActive: Bool {
        smartRecipes.isEnabled && canTriggerShutter && !isShowingLookDrawer
            && !isShowingLiveAdjustments && !isShowingTools
    }

    private var smartRecipeFrameKey: [String] {
        [camera.cameraPosition.rawValue, camera.selectedLensID ?? "", String(describing: camera.zoomFactor),
         String(describing: camera.previewViewportSize), String(describing: camera.previewRotationAngle),
         String(camera.previewMirrored)]
    }

    private func updateSmartRecipeAnalysis() {
        let favorites = (try? JSONDecoder().decode(Set<String>.self, from: favoriteData)) ?? []
        smartRecipes.configure(camera: camera, active: isSmartRecipeAnalysisActive,
                               recipes: viewModel.recipes, favoriteIDs: favorites)
    }

    private func openSmartRecipes() {
        guard !isChromeDisabled, !countdown.state.isActive else { return }
        smartPresentation = smartRecipes.snapshot
        closeControlDrawers()
        isShowingSmartRecipes = true
    }

    private func applySmartRecipe(_ id: String) {
        guard smartRecipes.isEnabled, canApplySmartRecipe,
              let recipe = viewModel.recipes.first(where: { $0.id == id }) else { return }
        smartRecipes.recordSelection(previousID: viewModel.selectedRecipeID, appliedID: recipe.id)
        viewModel.select(recipe: recipe)
        isShowingSmartRecipes = false
    }

    private func undoSmartRecipe() {
        guard canApplySmartRecipe,
              let id = smartRecipes.undo?.target(currentID: viewModel.selectedRecipeID,
                                                 availableIDs: Set(viewModel.recipes.map(\\.id))),
              let recipe = viewModel.recipes.first(where: { $0.id == id }) else { return }
        smartRecipes.clearUndo()
        viewModel.select(recipe: recipe)
    }

    // MARK: - Actions
''')
path.write_text(source)
manifest = [
    'FilmyCamera/Models/SmartRecipeEngine.swift',
    'FilmyCamera/Services/SmartRecipeStore.swift',
    'FilmyCamera/Views/SmartRecipeViews.swift',
    'FilmyCameraTests/SmartRecipeEngineTests.swift',
    'FilmyCameraTests/SmartRecipeIntegrationTests.swift',
    'FilmyCameraUITests/SmartRecipeUITests.swift',
    'docs/smart-recipes.md',
]
for relative in manifest:
    target = root / relative
    assert not target.exists(), f'Refusing to overwrite {relative}'
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(staged / relative, target)
suites_path = root / 'scripts/testing/suites.json'
suites = json.loads(suites_path.read_text())
suites['classes']['FilmyCameraTests/SmartRecipeEngineTests'] = 'unit'
suites['classes']['FilmyCameraTests/SmartRecipeIntegrationTests'] = 'integration'
suites['classes']['FilmyCameraUITests/SmartRecipeUITests'] = 'e2e'
for method in ['testSmartLooksIsDiscoverableAndUnavailableSceneHasNoApplyAction', 'testDisablingSuggestionsPersistsAcrossRelaunch']:
    suites['overrides']['FilmyCameraUITests/SmartRecipeUITests/' + method] = 'simulator-e2e'
suites_path.write_text(json.dumps(suites, indent=2) + '\n')
readme = root / 'README.md'
text = readme.read_text()
assert '## Smart looks' not in text
text += '''
## Smart looks

The Smart looks control above the viewfinder offers on-device, scene-aware recipe suggestions.
Tap **Apply** for the leading recommendation, or open it to compare three renders of the same
frame, choose Natural, Vivid, Cinema, or B&W, and apply a look with one tap. Undo restores the
previous look unless you have since chosen another manually. Suggestions never select a recipe
or save a photo automatically. Toggle analysis off in the Smart looks sheet.

The engine combines Apple Vision scene/face detection with light, contrast, and color measurements
and ranks the actual available recipes, including edited controls. It uses bounded, throttled
background work, pauses for capture and heat, and never uploads image data. These are aesthetic
starting points, not a guarantee of the best filter. See [the implementation and device-validation
notes](docs/smart-recipes.md).
'''
readme.write_text(text)
print('Integrated smart recipes with exact source anchors and registered test suites.')
