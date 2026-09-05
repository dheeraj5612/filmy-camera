# Filmy Camera

Filmy Camera is a native iPhone and iPad camera built around the feeling of choosing a film recipe before you shoot. It combines a low-friction SwiftUI camera UI with a Core Image/Metal-ready rendering pipeline for live preview and full-resolution exports.

## Current product slice

- Live camera session through `AVCaptureVideoDataOutput` and `AVCapturePhotoOutput`.
- GPU-backed Core Image processing with a generated 3D color cube, dynamic range, tone curve, temperature/tint, Color Chrome, FX Blue, detail, grain, halation, and vignette stages.
- Native bi-planar YUV preview buffers when available, with a BGRA fallback, and a session-scoped grain phase shared by preview and capture for a more faithful WYSIWYG frame.
- A dedicated G7 X Compact profile and curated editable film recipes based on public Fujifilm-style controls: film base, tone curve, color, white-balance shift, dynamic range, Color Chrome, FX Blue, sharpness, noise reduction, clarity, grain, grain size, halation, and vignette.
- Full-resolution capture review with retake or explicit Save to Photos, so a frame is never committed silently.
- Try another look on the same capture or import and compare with Original before saving. Review previews are bounded to 1800 pixels, and changed looks export at full resolution on Save without changing the next shot's recipe.
- System photo picker import that preserves the original framing and applies the selected recipe at full resolution up to the 40 MP processing budget; larger images are resized and labeled in review.
- First-run recipe-first onboarding with a direct handoff into the camera.
- Recipe swatches render the live viewfinder scene through each recipe (a synthetic color scene stands in when no camera is running), so choosing a look means seeing this scene in that look.
- Camera-first SwiftUI UI in the shape of an iPhone camera: a letterboxed 4:3 viewfinder on a black body, flash and camera switch in the top bar, Apple-style zoom presets over the frame, a film-strip recipe rail with renderer-backed swatches, a Roll thumbnail and Tune beside the shutter, Liquid Glass chrome on iOS 26 (material fallback earlier), persistent tuning, a recipe detail sheet, capture review, and a three-column contact-sheet Roll with zoom gestures.
- Optional semantic haptics for shutter, recipe and camera selections, focus, editor commits, discards, saves, and failures.
- Flash sits beside zoom in the on-screen controls and in Settings, and the last explicit choice is remembered; the G7 X profile renders flash frames with subject/ambient separation.
- Failed starts and runtime errors reconnect with backoff, and interruptions explain the cause (background, another app, multitasking, heat). The session supports iPad Split View and stays warm during review and quick tab switches to reduce restart work when returning to the viewfinder.
- The film pipeline compiles off the main thread while the session configures, and photo cache maintenance runs after the first frame.
- iPhone and iPad hardware controls for front/back switching and available-lens selection, with simulator-safe preview behavior.
- The live preview renders into a bounded drawable (about 1.3 MP) with a 30 fps target while stills and exports retain their full processing resolution. Sustained frame pacing and thermals require separate device measurement; isolated renderer timing does not establish camera frame rate.
- sRGB output normalization plus embedded recipe provenance metadata on saved JPEGs.
- Simulator-safe empty state: the full interface runs without camera hardware and clearly asks for a physical iPhone or iPad for capture.
- iPad support: readable-width pages, an adaptive Roll contact sheet, and the same viewfinder chrome verified on an iPad Pro and on iPhone-size layouts.

## Build

```sh
xcodegen generate
xcodebuild -project FilmyCamera.xcodeproj \
  -scheme FilmyCamera \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

If that simulator is not installed, replace the destination with any available iPhone ID from `xcrun simctl list devices available`.

For deterministic simulator tests on CI or a busy development machine, add `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1` to the test invocation.

Run the complete test suite with `python3 scripts/testing/run.py ci --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID'`. See [the testing guide](docs/testing.md) for unit, integration, Photos E2E, hardware, performance, coverage, and CI commands.

The app requires iOS 17 or later. Camera and Photos permissions are requested only when the relevant feature is used.

## Rendering note

The recipe controls intentionally model the public vocabulary used by Fujifilm cameras, but this app is not affiliated with Fujifilm and does not ship Fujifilm firmware, LUTs, or proprietary calibration data. Exact camera output varies by sensor generation, exposure, white balance, and lighting; the bundled recipes are transparent, adjustable interpretations rather than claims of identical hardware output.

## Research

See [docs/research.md](docs/research.md) for the open-source architecture review and the rendering decisions used here.
