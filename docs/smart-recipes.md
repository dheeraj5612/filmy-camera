# Smart looks

## Using the feature

Frame the scene normally. The Smart looks pill in the camera's reserved status row shows a
recommended recipe once two observations agree. Tap **Apply** for that look, or tap its name
to compare three alternatives on the same frozen viewfinder frame. Natural, Vivid, Cinema,
and B&W let the photographer choose an aesthetic direction. The unfiltered toggle compares
all three against the same input. Selecting a suggestion uses the existing recipe-selection
and capture pipeline, including effective user edits. It never changes already saved photos.

Undo restores the previously selected recipe only while the suggested recipe is still selected.
A later manual selection invalidates undo. The sheet's switch persistently disables the worker.
Without a usable camera frame, the UI offers an explanation, not invented results.

## What is intelligent, and what is not

Apple Vision image classification and face rectangles supply scene evidence. No face identity,
demographic attribute, or emotion is inferred. Display-referred sRGB samples measure light,
5th/95th percentile contrast, saturation, warmth, and clipped highlights. Low-confidence labels
fall back to light/color guidance. Correlated labels are combined with max, not summed into
false confidence. Black, fully clipped, malformed, and transparent inputs are rejected.

The deterministic ranker combines scene affinity with actual recipe controls: film base,
contrast, saturation, highlight tone/protection, grain, exposure, temperature shift, and tint.
It favors gentler color for faces, restrained grain in dim frames, and gentler highlights in
contrasty frames. Favorites receive a small tie-break bonus; diversity discourages near-identical
families. Only IDs from the supplied effective catalog are eligible. The current app supplies
CameraViewModel.recipes; future pack/availability filtering should pass that filtered catalog
through the same argument rather than bypassing the ranker.

These are original aesthetic heuristics, not a trained personalized taste model or a calibrated
claim that a recipe is objectively correct. Highlight recommendations cannot recover source
clipping. Kelvin-only changes are not separately modeled in the ranker's normalized warmth
term; the actual recipe renderer still applies them to previews and capture.

## Capture, concurrency, and privacy

- A separate CameraService frame listener receives unfiltered, already oriented/mirrored frames.
  The renderer, capture controls, Photos permissions, and saved-image format are unchanged.
- One admitted frame at a time is copied to an owned RGBA image with a 384-pixel maximum edge,
  using the exact viewfinder aspect-fill crop. The camera-backed image is released before Vision.
- Core Image measurement and Vision run on a private utility queue. Minimum intervals are 1.5
  seconds normally, 3 seconds at fair thermal pressure, and 4 seconds in Low Power Mode.
  Serious/critical thermal state pauses analysis. There is no unbounded frame backlog.
- Generation tokens reject stale results after lens, zoom, crop, orientation, background, catalog,
  or intent changes. Invalidating does not release an in-flight lease until its worker finishes.
- Two agreeing samples and a 3.5-second minimum display dwell reduce flicker. Opening the chooser
  freezes its source, results, and tap targets; thumbnails render serially with cancellation checks.
- Admission of new analysis pauses during capture, saving, import/review, countdown, inactive camera
  states, and camera control sheets/drawers. The hardware shutter cannot capture through the Smart looks sheet.
- Image data and ephemeral scene evidence are not uploaded, logged, or persisted. Only the enabled
  preference and aesthetic intent persist. Small image copies are cleared when analysis stops;
  the frozen chooser image lasts only until the chooser closes. An in-progress worker may finish
  after disabling, but its result cannot publish.

## Validation

SmartRecipeEngineTests covers scene/intent ranking, edits, diversity, weak/invalid evidence,
pixel statistics, backpressure, throttling, stale callbacks, stabilization, and conditional undo.
SmartRecipeIntegrationTests covers the actual recipe catalog, native Core Image/Vision handoff,
crop bounds, preference isolation/persistence, and unchanged manual selection.
SmartRecipeUITests covers discoverability, honest no-camera behavior, and the persistent off switch
on the simulator. All classes are registered in scripts/testing/suites.json.

The checked-in Xcode project includes the three application files and all three test classes.
When adding or moving files, regenerate with the repository's pinned XcodeGen 2.45.4 and commit
the generated project rather than editing project identifiers by hand. A second generation must
leave the project unchanged. Portable policy tests and project generation are useful checks, but
neither substitutes for compiling the application against the iOS SDK and running native tests.

Targeted native command after `xcodegen generate --spec project.yml`:

```sh
xcodebuild -project FilmyCamera.xcodeproj -scheme FilmyCamera \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:FilmyCameraTests/SmartRecipeEngineTests \
  -only-testing:FilmyCameraTests/SmartRecipeIntegrationTests \
  -only-testing:FilmyCameraUITests/SmartRecipeUITests test
```

Device acceptance remains important: frame people against colorful backgrounds, food, foliage,
bright windows, neon, and low-light scenes; move/zoom/switch cameras quickly; compare front-camera
mirroring and crop; exercise countdown, shutter, manual changes, and undo; cover/uncover the lens;
background/foreground; test VoiceOver and large text on compact iPhone and iPad; use Instruments
for sustained preview frame pacing, camera-buffer pressure, energy, and thermal behavior.
No frame-rate, battery-life, scene-accuracy percentage, or pixel-identical camera claim is implied
by policy tests or a simulator build.

Primary implementation references:

- https://developer.apple.com/documentation/vision/vnclassifyimagerequest
- https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest
- https://developer.apple.com/library/archive/technotes/tn2445/_index.html
