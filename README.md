# Filmy Camera

Filmy Camera is a native iPhone and iPad camera built around the feeling of choosing a film recipe before you shoot. It combines a low-friction SwiftUI camera UI with a Core Image/Metal-ready rendering pipeline for live preview and full-resolution exports.

## Current product slice

- Live camera session through `AVCaptureVideoDataOutput` and `AVCapturePhotoOutput`.
- GPU-backed Core Image processing with a generated 3D color cube, dynamic range, tone curve, temperature/tint, Color Chrome, FX Blue, detail, grain, halation, and vignette stages.
- Native bi-planar YUV preview buffers when available, with a BGRA fallback, and a session-scoped grain phase shared by preview and capture for a more faithful WYSIWYG frame.
- Sixteen editable recipe starting points based on public Fujifilm-style controls: film base, tone curve, color, white-balance shift, dynamic range, Color Chrome, FX Blue, sharpness, noise reduction, clarity, grain, grain size, halation, and vignette.
- Full-resolution capture review with retake or explicit Save to Photos, so a frame is never committed silently.
- System photo picker import that applies the selected recipe at full resolution while preserving the original framing.
- First-run recipe-first onboarding with a direct handoff into the camera.
- Warm, camera-first SwiftUI UI: edge-anchored viewfinder chrome, a film-strip recipe rail with renderer-backed swatches, a last-frame Roll thumbnail beside the shutter, persistent tuning, a recipe detail sheet, capture review, and a three-column contact-sheet Roll with zoom gestures.
- Optional semantic haptics for shutter, recipe and camera selections, focus, editor commits, discards, saves, and failures.
- iPhone hardware controls for front/back switching and available-lens selection, with simulator-safe preview behavior.
- sRGB output normalization plus embedded recipe provenance metadata on saved JPEGs.
- Simulator-safe empty state: the full interface runs without camera hardware and clearly asks for a physical iPhone or iPad for capture.
- iPad support: readable-width pages, an adaptive Roll contact sheet, and the same viewfinder chrome verified on an iPad Pro and on iPhone-size layouts.
- Photo import from the system picker, rendered at full resolution with the current recipe and reviewed before saving.

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

The app requires iOS 17 or later. Camera and Photos permissions are requested only when the relevant feature is used.

## Rendering note

The recipe controls intentionally model the public vocabulary used by Fujifilm cameras, but this app is not affiliated with Fujifilm and does not ship Fujifilm firmware, LUTs, or proprietary calibration data. Exact camera output varies by sensor generation, exposure, white balance, and lighting; the bundled recipes are transparent, adjustable interpretations rather than claims of identical hardware output.

## Research

See [docs/research.md](docs/research.md) for the open-source architecture review and the rendering decisions used here.
