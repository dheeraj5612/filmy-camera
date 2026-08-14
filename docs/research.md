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

### Reproducibility record — 2026-08-13

The comparison claims above are pinned to the following repository commits so a future review can distinguish a checked source snapshot from a moving default branch. The links are references only; no source is vendored into Filmy Camera.

- [GPUImage3 `84466fc3`](https://github.com/BradLarson/GPUImage3/tree/84466fc344e1220238c1c07e94e91207caaabe51) — [README](https://github.com/BradLarson/GPUImage3/blob/84466fc344e1220238c1c07e94e91207caaabe51/README.md); live camera-to-Metal operation graph. Its README marks still-photo processing as incomplete, so it is not treated as a still-export reference.
- [MetalPetal `f9b78897`](https://github.com/MetalPetal/MetalPetal/tree/f9b78897bd4214bb097f352a1bde0a4f4a1e2ddb) — [README](https://github.com/MetalPetal/MetalPetal/blob/f9b78897bd4214bb097f352a1bde0a4f4a1e2ddb/README.md); reusable GPU context, immutable image graph, and explicit color-space boundaries.
- [FastttCamera `1721da41`](https://github.com/IFTTT/FastttCamera/tree/1721da415ef47f5190aee12f1db756bc98ac802d) — [README](https://github.com/IFTTT/FastttCamera/blob/1721da415ef47f5190aee12f1db756bc98ac802d/README.md); capture lifecycle and still-filter separation.
- [NextLevel `2fa42500`](https://github.com/NextLevel/NextLevel/tree/2fa42500caf7edd7136d23b64d9ecb5684d93d07) — [README](https://github.com/NextLevel/NextLevel/blob/2fa42500caf7edd7136d23b64d9ecb5684d93d07/README.md); session state, interruptions, and media-output separation.

The source snapshots were checked on 2026-08-13. Repository licenses and current upstream state still require a fresh review before adopting any dependency or asset; this app continues to use system frameworks and original renderer code.

## Recipe model

Fujifilm's public manuals and support material describe the controls as a combination of film simulation, highlight/shadow tone, grain, Color Chrome, Color Chrome FX Blue, white balance, dynamic range, D Range Priority, monochromatic color, and tone curve. Filmy Camera represents those controls as data in `FilmRecipe` and applies them as:

1. Exposure and tone controls.
2. White-balance mode plus temperature/tint shift.
3. A generated 3D color cube for palette/cross-channel response.
4. Grain and vignette finishing stages.

This makes every look inspectable and adjustable instead of hiding it in an opaque filter name. The shipped recipe names are compatibility references only; the app is not affiliated with Fujifilm.

## Rendering contract

The preview, still, and export paths now share a canonical 32³ recipe transform. Quality remains an explicit API value for future scheduling/resolution work, but it no longer changes the color cube or the strength of grain/halation. Cube caching is keyed only by film base, palette, Color Chrome, and blue-response inputs, and cube generation happens outside the cache lock so slider changes do not block another frame.

The Core Image context declares sRGB as both working and output space for the current SDR/JPEG product contract. The renderer clamps at the final SDR boundary and does not claim HDR preservation. Synthetic rail thumbnails are generated from deterministic color blocks through the same renderer, which keeps the UI preview honest without bundling an unlicensed photograph.

The live viewfinder and still export share `CameraFrameLayout.aspectFillCrop`. Captured images are cropped to the same visible viewport before the recipe is rendered, and capture review is not presented if materialization fails. This makes composition parity testable even though physical-camera orientation, color profiles, and sensor calibration still require device QA.

The live camera output prefers bi-planar video-range YUV buffers when AVFoundation exposes them, with a BGRA fallback for older or simulator implementations. The camera session owns a random grain phase that is passed to both the preview and capture render, keeping grain placement aligned within a session while deterministic thumbnails and tests retain the canonical zero seed.

The [X-T5 image-quality menu](https://fujifilm-dsc.com/en-int/manual/x-t5/introduction/menu_list/) and [image-quality reference](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/) are the first-party vocabulary reference for the model. They document film simulation, grain effect roughness/size, Color Chrome, Color Chrome FX Blue, dynamic range, D Range Priority, white balance modes, monochromatic color axes, tone curve, color, sharpness, high-ISO noise reduction, and clarity. They do not provide a transferable iPhone LUT or sensor calibration. Therefore the renderer intentionally claims a transparent, original approximation of the public controls—not identical Fujifilm hardware output.

## Calibration and licensing boundary

The open-source look research also found reusable LUT/profile assets, but none are safe to ship in this commercial App Store target without an explicit license review:

- [abpy/FujifilmCameraProfiles](https://github.com/abpy/FujifilmCameraProfiles) publishes cube LUTs and camera profiles and states that they are CC BY-NC-SA 4.0. The repository is useful as a reference for LUT structure and color-management pitfalls, but its non-commercial terms exclude direct inclusion in this app.
- [plamf/fuji-x-weekly-simulation-profiles](https://github.com/plamf/fuji-x-weekly-simulation-profiles) publishes camera profile files under GPL-3.0. Those files are not vendored here, and the project notes that its values are only tested against a particular X-Trans generation.
- [JanLohse/spectral_film_lut](https://github.com/JanLohse/spectral_film_lut) demonstrates a datasheet-driven route to film-emulation LUTs. A future calibration pass should use original measurements or assets with commercial redistribution rights, then add reference images and device/sensor validation before changing the product's approximation disclaimer.

The current renderer therefore remains an original, inspectable Core Image/Metal model. It does not claim exact Fujifilm output, and the app does not ship firmware, proprietary profiles, or third-party LUT files.

## Bounded recipe fidelity and provenance pass — 2026-08-12

The recipe model now treats the public terminology boundary as an explicit
product contract. The first-party X-T5 manual uses the following control
groups: Film Simulation, Grain Effect (roughness and size), Color Chrome Effect,
Color Chrome FX Blue, White Balance, Dynamic Range, D Range Priority, Tone
Curve, Color, Sharpness, High ISO NR, and Clarity. It also documents
monochromatic warm/cool and green/magenta axes plus ACROS and monochrome
yellow, red, and green filter options. Filmy Camera uses those names as
interoperable vocabulary, while its numeric values remain app-defined
normalized parameters.

`FilmRecipe.Control` is the single semantic catalog for those numeric
parameters. Each entry states its unit, meaning, and app editor range. The
range is not presented as a Fujifilm hardware scale, and validation reports
out-of-range drafts without rewriting them. The renderer remains defensive and
clamps at its own output boundary.

`FilmRecipe` persistence is versioned. Current records use schema version 4
and serialize `Provenance` with the two first-party references above. The
record states `originalParametricApproximation` and
`notCalibratedToFujifilmHardware`; there is intentionally no exact-match,
hardware-calibrated, or proprietary-LUT state. Records from the old unversioned
shape remain decodable, but are labeled as legacy and fail the complete audit
until they are rewritten by the current model.

The product disclosure is therefore narrow and testable: the looks are
original approximations inspired by public controls, not pixel-identical
Fujifilm camera output; the app is not affiliated with or endorsed by
Fujifilm; and no proprietary LUT, firmware, or camera calibration data is
included. The current build uses original descriptive names in the user
interface; internal recipe identifiers retain the public control mapping for
continuity, but no exact-match claim is made.

First-party references:

- [FUJIFILM X-T5 Image Quality Setting](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/)
- [FUJIFILM Film Simulation overview](https://www.fujifilm-x.com/en-us/products/film-simulation/)
