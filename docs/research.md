# Camera and film-look research

## Open-source implementation patterns reviewed

The initial architecture pass reviewed these public repositories:

- [GPUImage3](https://github.com/BradLarson/GPUImage3) — captures YUV camera buffers, converts them to Metal textures, and connects camera frames to a target/operation graph. BSD-licensed.
- [MetalPetal](https://github.com/MetalPetal/MetalPetal) — uses `CVPixelBuffer`/Metal texture bridging and render-graph style image processing. MIT-licensed.
- [FastttCamera](https://github.com/IFTTT/FastttCamera) — shows the older lookup-image pattern for camera filters and still-image capture. MIT-licensed.

The app does not copy source code from these projects and does not include them as dependencies. The shared design lessons are: keep capture and rendering on separate queues, use a pixel-buffer-to-GPU path for live preview, use a composable filter graph, and keep a still-image export path separate from the preview path.

## Verified comparison pass

The architecture comparison was expanded against the repositories below. The repository descriptions and licenses were checked from GitHub before the implementation decisions were recorded:

- [BradLarson/GPUImage3](https://github.com/BradLarson/GPUImage3) — BSD-3-Clause; a Swift/Metal graph for GPU-accelerated image and video processing. Relevant pattern: keep camera-buffer delivery and GPU operations composable.
- [MetalPetal/MetalPetal](https://github.com/MetalPetal/MetalPetal) — MIT; a Metal-backed image/video framework. Relevant pattern: bridge pixel buffers into a reusable render context and keep intermediate work on the GPU.
- [IFTTT/FastttCamera](https://github.com/IFTTT/FastttCamera) — MIT; an iOS camera framework with customizable filters. Relevant pattern: separate capture lifecycle from a still-image filter/export path.
- [NextLevel/NextLevel](https://github.com/NextLevel/NextLevel) — MIT; a media-capture framework for Swift. Relevant pattern: isolate session configuration, capture state, interruptions, and output callbacks from the view layer.

Filmy Camera uses those patterns as independent design input and does not vendor or copy their source. Its capture service owns AVFoundation queues, its preview uses an MTKView/Core Image render path, and its still export runs the same recipe model at a higher quality tier.

## Recipe model

Fujifilm's public manuals and support material describe the controls as a combination of film simulation, highlight/shadow tone, grain, Color Chrome, Color Chrome FX Blue, white balance shift, and tone curve. Filmy Camera represents those controls as data in `FilmRecipe` and applies them as:

1. Exposure and tone controls.
2. Temperature/tint white-balance shift.
3. A generated 3D color cube for palette/cross-channel response.
4. Grain and vignette finishing stages.

This makes every look inspectable and adjustable instead of hiding it in an opaque filter name. The shipped recipe names are compatibility references only; the app is not affiliated with Fujifilm.

The [X-T5 image-quality menu](https://fujifilm-dsc.com/en-int/manual/x-t5/introduction/menu_list/) and [image-quality reference](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/) are the first-party vocabulary reference for the model. They document film simulation, grain effect roughness/size, Color Chrome, Color Chrome FX Blue, dynamic range, white balance, tone curve, color, sharpness, high-ISO noise reduction, and clarity. They do not provide a transferable iPhone LUT or sensor calibration. Therefore the renderer intentionally claims a transparent, original approximation of the public controls—not identical Fujifilm hardware output.

## Calibration and licensing boundary

The open-source look research also found reusable LUT/profile assets, but none are safe to ship in this commercial App Store target without an explicit license review:

- [abpy/FujifilmCameraProfiles](https://github.com/abpy/FujifilmCameraProfiles) publishes cube LUTs and camera profiles and states that they are CC BY-NC-SA 4.0. The repository is useful as a reference for LUT structure and color-management pitfalls, but its non-commercial terms exclude direct inclusion in this app.
- [plamf/fuji-x-weekly-simulation-profiles](https://github.com/plamf/fuji-x-weekly-simulation-profiles) publishes camera profile files under GPL-3.0. Those files are not vendored here, and the project notes that its values are only tested against a particular X-Trans generation.
- [JanLohse/spectral_film_lut](https://github.com/JanLohse/spectral_film_lut) demonstrates a datasheet-driven route to film-emulation LUTs. A future calibration pass should use original measurements or assets with commercial redistribution rights, then add reference images and device/sensor validation before changing the product's approximation disclaimer.

The current renderer therefore remains an original, inspectable Core Image/Metal model. It does not claim exact Fujifilm output, and the app does not ship firmware, proprietary profiles, or third-party LUT files.
