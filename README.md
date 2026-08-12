# Filmy Camera

Filmy Camera is a native iPhone camera built around the feeling of choosing a film recipe before you shoot. It combines a low-friction SwiftUI camera UI with a Core Image/Metal-ready rendering pipeline for live preview and full-resolution exports.

## Current product slice

- Live camera session through `AVCaptureVideoDataOutput` and `AVCapturePhotoOutput`.
- GPU-backed Core Image processing with a generated 3D color cube, tone curve, temperature/tint, grain, and vignette stages.
- Eleven recipe starting points based on public Fujifilm-style controls: film base, tone curve, color, white-balance shift, Color Chrome-style compression, blue response, grain, clarity, and vignette.
- Capture to Photos with the selected look baked into the saved image.
- Dark, camera-first SwiftUI UI with recipe rail, recipe detail sheet, capture feedback, and a recent grid.
- Simulator-safe empty state: the full interface runs without camera hardware and clearly asks for a physical iPhone for capture.

## Build

```sh
xcodegen generate
xcodebuild -project FilmyCamera.xcodeproj \
  -scheme FilmyCamera \
  -destination 'platform=iOS Simulator,name=FilmyCamera iPhone' \
  build
```

For deterministic simulator tests on CI or a busy development machine, add `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1` to the test invocation.

The app requires iOS 17 or later. Camera and Photos permissions are requested only when the relevant feature is used.

## Rendering note

The recipe controls intentionally model the public vocabulary used by Fujifilm cameras, but this app is not affiliated with Fujifilm and does not ship Fujifilm firmware, LUTs, or proprietary calibration data. Exact camera output varies by sensor generation, exposure, white balance, and lighting; the bundled recipes are transparent, adjustable interpretations rather than claims of identical hardware output.

## Research

See [docs/research.md](docs/research.md) for the open-source architecture review and the rendering decisions used here.
