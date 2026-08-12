# Camera and film-look research

## Open-source implementation patterns reviewed

The initial architecture pass reviewed these public repositories:

- [GPUImage3](https://github.com/BradLarson/GPUImage3) — captures YUV camera buffers, converts them to Metal textures, and connects camera frames to a target/operation graph. BSD-licensed.
- [MetalPetal](https://github.com/MetalPetal/MetalPetal) — uses `CVPixelBuffer`/Metal texture bridging and render-graph style image processing. MIT-licensed.
- [FastttCamera](https://github.com/IFTTT/FastttCamera) — shows the older lookup-image pattern for camera filters and still-image capture. MIT-licensed.

The app does not copy source code from these projects and does not include them as dependencies. The shared design lessons are: keep capture and rendering on separate queues, use a pixel-buffer-to-GPU path for live preview, use a composable filter graph, and keep a still-image export path separate from the preview path.

## Recipe model

Fujifilm's public manuals and support material describe the controls as a combination of film simulation, highlight/shadow tone, grain, Color Chrome, Color Chrome FX Blue, white balance shift, and tone curve. Filmy Camera represents those controls as data in `FilmRecipe` and applies them as:

1. Exposure and tone controls.
2. Temperature/tint white-balance shift.
3. A generated 3D color cube for palette/cross-channel response.
4. Grain and vignette finishing stages.

This makes every look inspectable and adjustable instead of hiding it in an opaque filter name. The shipped recipe names are compatibility references only; the app is not affiliated with Fujifilm.
