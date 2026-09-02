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
2. White-balance mode plus persisted Kelvin color temperature and temperature/tint fine-tuning.
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
interoperable vocabulary, while its normalized fine-tuning values remain
app-defined parameters. The explicit Color Temperature mode also persists
the documented 2500–10000 K range; this records camera intent but does not add
proprietary calibration.

`FilmRecipe.Control` is the single semantic catalog for those numeric
parameters. Each entry states its unit, meaning, and app editor range. The
range is not presented as a Fujifilm hardware scale, and validation reports
out-of-range drafts without rewriting them. The renderer remains defensive and
clamps at its own output boundary.

`FilmRecipe` persistence is versioned. Current records use schema version 5
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

## Live open-source review — 2026-08-14

The implementation review was refreshed against current upstream repositories
and Apple's filtered-camera sample. The result reinforces the existing choice
to keep the app dependency-free:

- [IFTTT/FastttCamera](https://github.com/IFTTT/FastttCamera) (MIT) remains a
  useful reference for capture lifecycle, orientation, crop, focus/exposure,
  and lookup-filter separation, but its Objective-C/CocoaPods foundation is
  not a good new dependency.
- [BradLarson/GPUImage3](https://github.com/BradLarson/GPUImage3) (BSD-3-Clause)
  demonstrates a composable Swift/Metal source → operation → consumer graph;
  its README still calls out incomplete still-photo processing, so it is a
  reference rather than the still-export foundation.
- [MetalPetal/MetalPetal](https://github.com/MetalPetal/MetalPetal) (MIT) is
  the strongest reusable render-graph alternative: immutable image promises,
  reusable context, custom kernels, color lookup, caching, and explicit color
  boundaries. Its examples and documentation have separate licensing notes.
- [NextLevel/NextLevel](https://github.com/NextLevel/NextLevel) (MIT) is a
  useful capture-state reference for interruptions, depth, RAW, and output
  callbacks, but its broad dependency surface is unnecessary for the current
  app's AVFoundation service.
- [yangKJ/Harbeth](https://github.com/yangKJ/Harbeth) (MIT) is a benchmark
  candidate for Metal/CUBE/LUT plumbing, not an adopted dependency until API
  stability, performance, and every transitive asset are reviewed.

Apple's [AVCamFilter sample](https://developer.apple.com/documentation/avfoundation/avcamfilter-applying-filters-to-a-capture-stream)
continues to support the chosen architecture: keep camera session work off the
main thread, process pixel buffers through a reusable Core Image/Metal context,
and use the same deterministic recipe graph for preview and still output.
The public Fujifilm material still defines the user-facing recipe controls, not
the sensor/ISP transfer functions or a general-purpose LUT. Model-specific
downloadable LUTs and community profiles therefore remain excluded from the
commercial bundle without explicit redistribution rights and calibration data.

## Film-response and camera-pipeline audit — 2026-08-19

This pass rechecked the current app against source snapshots rather than only
repository descriptions:

- [GPUImage3 `84466fc3`](https://github.com/BradLarson/GPUImage3/tree/84466fc344e1220238c1c07e94e91207caaabe51)
  (BSD-3-Clause) bounds in-flight camera-frame work and bridges native YUV
  buffers into its reusable Metal pipeline.
- [MetalPetal `f9b78897`](https://github.com/MetalPetal/MetalPetal/tree/f9b78897bd4214bb097f352a1bde0a4f4a1e2ddb)
  (MIT) treats input and output color spaces as explicit boundaries, reuses a
  heavyweight render context, and keeps intermediate image graphs immutable.
- [NextLevel `2fa42500`](https://github.com/NextLevel/NextLevel/tree/2fa42500caf7edd7136d23b64d9ecb5684d93d07)
  (MIT) isolates capture-session interruption/runtime-error handling from the
  view layer.
- [dazz-retro-camera `c8a7f269`](https://github.com/ganjmeng/dazz-retro-camera/tree/c8a7f269900cacfb9388d0beb3998036af1f5104)
  (MIT) is a similar app-idea reference whose documented finishing pipeline
  derives bloom/halation before adding grain and vignette.
- [Filmulator `57fbaec5`](https://github.com/CarVac/filmulator-gui/tree/57fbaec57555432d86d3aa632990cd8fa09114ad)
  (GPL-3.0-or-later) models spatial development effects and highlight
  compression. It is research-only here: no source or algorithm was copied.
- [SilverGrain `0db9850c`](https://github.com/kjerk/silvergrain/tree/0db9850cd93b07bea2f833b869e4ed8b1594bd3d)
  (AGPL-3.0) demonstrates deterministic, resolution-aware, luminance-preserving
  grain. It is also research-only; its implementation was not incorporated.

The resulting code changes remain original and dependency-free. AVFoundation
color attachments are now preserved when a preview `CIImage` is created, then
converted only at FilmRenderer's explicit sRGB materialization boundary.
Halation is derived before grain so the synthetic texture cannot contaminate
the highlight mask. Session interruptions and runtime errors now terminate any
pending photo request before recovery, preventing a permanently busy shutter.

The audit intentionally did not port Filmulator or SilverGrain code because
doing so would add reciprocal-license obligations to this App Store target. It
also did not adopt third-party LUTs or stock calibration data.

## G7 X-inspired compact look — 2026-08-19

The `g7x-compact` recipe is an original approximation based only on Canon's
public [PowerShot G7 X Mark III specifications](https://www.usa.canon.com/support/p/powershot-g7-x-mark-iii)
and [Camera Museum overview](https://global.canon/en/c-museum/product/dcc884.html).
Those sources establish the relevant product envelope: a 20.1-megapixel
one-inch stacked CMOS sensor, DIGIC 8 processing, a 24–100 mm-equivalent
f/1.8–2.8 zoom, Auto ambience/white-priority balance, and a Standard Picture
Style option. They do not publish a transferable tone curve, color matrix, or
Picture Style payload.

The implementation therefore targets the observable intent rather than an
exact match: clean compact-camera color, slightly warm portrait midtones,
selective red/blue presence, smooth highlight protection, restrained detail,
and no synthetic film grain, halation, or blanket contrast. Its
dedicated parametric film base and editable recipe controls run through the
same deterministic preview/photo/export pipeline as every other look.

The app records Canon-specific public references and a not-calibrated-to-Canon
status in saved-photo provenance. It makes no claim to reproduce the physical
camera's sensor, 24–100 mm lens, DIGIC processing, optical depth of field, or
pixel-identical JPEG output; no Canon LUT, Picture Style file, firmware,
sample-image pixels, code, or calibration data is included.

## G7 X compact-profile fidelity pass — 2026-08-27

The mode was re-audited against Canon's current public support specifications
and the official PowerShot G7 X Mark III Advanced User Guide. Canon documents
the one-inch 20.1 MP sensor and 24–100 mm-equivalent f/1.8–2.8 lens, Auto
Lighting Optimizer, ambience- and white-priority auto white balance, and the
Standard Picture Style as vivid, sharp, crisp, and suitable for most scenes.
The guide also distinguishes Portrait's smoother skin rendering from Standard;
Filmy Camera continues to target the general Standard-style compact JPEG rather
than silently combining multiple Canon modes.

### Real-image reference batch

The second pass used Photography Blog's 31 downloadable, unmodified 20 MP
SuperFine JPEG samples. EXIF verification identified every file as a Canon
PowerShot G7 X Mark III, 5472 x 3648, sRGB image. Nine matching CR3 files first
established the method; the final batch expanded to all 31 matching CR3 files
and independently developed them through Apple's RAW pipeline. This
made same-scene comparisons possible without storing or shipping any third-
party image, embedded profile, or derived LUT in the app.

Across the initial nine pairs, the camera JPEG opened dark tones and midtones while
retaining a shoulder near white. Relative median saturation changes varied by
source hue: approximately +11% red, +15% orange/warm subjects, +12% yellow,
-5% green, +13% cyan/blue, and +4% magenta. Low-chroma neutral areas showed an
equal-channel lift rather than a stable warm or green cast. Mid-frequency edge
contrast was about 1.18x the independent development, but this combines Canon
sharpening with differences in the RAW developer and must not be treated as a
transferable camera kernel.

These measurements are directional, not calibration data: the scenes are not
a controlled color chart, Apple's RAW development is only a comparison
baseline, and exposure/WB choices vary between photographs. They are useful
for rejecting the earlier blanket warmth and saturation, not for claiming a
pixel-identical match.

The implementation now includes a dedicated compact-digital tone stage in
addition to the inspectable recipe controls. Its original curve keeps a clean
black point, opens shadow and midtone detail, and rolls into a softer highlight
shoulder. The compact color transform treats luminance and hue separately: it
keeps neutrals clean, warms only moderate-chroma portrait midtones, adds
selective red and blue presence, restrains foliage, and reduces chroma in deep
shadows and near-white highlights. The final built-in deliberately removes
blanket contrast, noise reduction, vignette, palette bias, and extra blue
response. It retains only fine sharpening and very low clarity, avoiding a
second heavy local-contrast pass on already-processed iPhone/HEIC input.

An instrumented, non-shipping calibration harness rendered all 31 independent
RAW developments through candidate stage combinations and compared them with
their same-scene Canon JPEGs. The earlier full-strength recipe increased mean
absolute RGB error from 0.04209 to 0.06712 and improved only 2 of 31 pairs. The
restrained dedicated compact transform plus the small tone, dynamic-range,
sharpness, and clarity settings reduced it to 0.03391 and improved 22 of 31
pairs: a 19.4% average reduction from the independent-development baseline.
The external files and temporary harness are not included in the app or its
test bundle.

The camera UI labels the selection as a camera profile instead of film stock,
and recipe details expose the processing intent, official Canon references,
and the hardware/calibration boundary. Renderer provenance advances to
`core-image-parametric-v5`; persisted user edits migrate onto the current
built-in parent while retaining their editable values.

The new regression fixtures verify a monotonic compact tone response, opened
shadow/midtone luminance, a retained highlight shoulder, warm skin and red
separation, restrained foliage, blue-sky separation, and tightly bounded
neutral color. These tests are
behavioral guardrails for the original approximation, not evidence of a
pixel-identical G7 X match. Physical side-by-side calibration remains open.

## Compact-camera interaction reference — 2026-08-27

The public App Store listing and screenshots for
[flag7x](https://apps.apple.com/us/app/flag7x-g7x-style-camera/id6747452095)
were reviewed as an interaction reference, not as a source for code, assets,
branding, or color transforms. Its strongest product principle is immediacy:
the photograph dominates the screen while zoom, exposure, flash, composition,
camera switching, and the shutter remain in the capture path.

Filmy Camera adapts that principle to its own darkroom visual system. When the
G7 X Compact profile is active, the viewfinder-first layout now exposes a
bounded quick-control dock for zoom, EV, grid, and—when the active hardware
supports them—flash, camera position, and lens selection. The dock keeps the
selected camera profile beside the shutter, retains 44-point touch targets and
VoiceOver state, and continues to scale across iPhone and iPad. Film recipes,
photo import, provenance, and the existing detailed controls remain distinct
Filmy Camera workflows.

## flag7x visual-reference pass — 2026-08-30

The installed `flag7x` 3.3.1 app was launched on a connected iPad and captured
through Xcode's device screenshot path. Its current public product page and
[G7X-inspired guide](https://www.flag7xapp.com/guides/canon-g7x-look-iphone)
were reviewed alongside the live UI. The public target is a polished compact-
camera default with warm natural color, saturated but controlled subjects,
friendly contrast, and an optional portrait-smoothing setting. Flash is a
capture choice that creates bright-subject/dark-background separation; it is
not treated as a color-filter curve.

Filmy Camera keeps its existing same-scene Canon JPEG/RAW-derived compact core
but now uses the stronger social-camera treatment as its initial default:
brighter warm portrait midtones, peach/pink skin, richer ambient shadows,
controlled saturation, and gentle skin-selective smoothing. Synthetic grain,
vignette, and halation remain off. No flag7x code, assets, LUTs, private app data, or sample pixels
are copied or shipped, and the result remains an independently implemented
approximation rather than a pixel-identical claim.

The global warmth initially reduced saturated-red separation by moving those
pixels near the existing hue-sector boundary. A regression fixture caught it;
the final renderer makes only a small red/orange-local correction and advances
saved-photo provenance to `core-image-parametric-v6`.

## G7 X social-portrait reference pass — 2026-08-30

Public G7 X Mark II/III night-out portraits, group photos, selfies, and direct-
flash examples were reviewed to identify the outcome people seek rather than
to reproduce an individual image. Across the references, the recurring visual
language was a bright, clean subject against a darker ambient background;
peach/pink warmth in skin; crisp red and gold accents; controlled highlights;
and slightly softened microcontrast instead of aggressive phone-style HDR.

The G7 X Compact default now intentionally exaggerates that feel. It is also
the initially selected recipe on a new install. A one-time face-detection pass
on captured stills supplies softly feathered subject regions; when AVFoundation
confirms that flash actually fired, the renderer brightens and protects those
subjects while darkening ambient background. The same default adds a firmer
social-photo curve, stronger bounded color, warmer ambience-priority balance,
peach/pink-local portrait color, and gentle skin-selective smoothing. Flash
remains a real capture control; a non-flash image never receives the stronger
direct-flash separation.
No reference pixels, LUTs, private app data, or images are included. Saved-photo
provenance advances to `core-image-parametric-v8`.

## iPad hardware verification and renderer corrections — 2026-09-01

The branch was rebased onto the merged viewfinder redesign (#77) and the
whole test suite was run on a paired iPad Pro 11-inch (2nd generation) on
iOS 26.6.1, plus the iPad Pro and iPhone 17 Pro simulators. Two classes of
crash logs found on the device pointed at the same defect: in Swift 6
language mode, closure literals passed to PhotoKit change blocks and
completion handlers from the `@MainActor` photo-library service inherit
main-actor isolation, and PhotoKit invokes them on its own serial queue, so
the runtime isolation check trapped while saving to the app album, deleting,
or requesting authorization. Every PhotoKit callback is now an explicitly
`@Sendable` closure that captures only identifiers and re-fetches inside the
change block.

Rendering real fixture photographs through the pipeline on the device exposed
two renderer-wide issues:

- Contrast was applied by `CIColorControls` in Core Image's linear working
  space, whose pivot (0.5 linear, roughly 0.73 sRGB) drives every dark tone
  toward black even at modest settings; recipes at 1.18 clipped everything
  below about 0.3 sRGB. Contrast now runs in gamma-encoded space around
  perceptual middle gray, which is how a camera's contrast control behaves.
- The Color Temperature control used Core Image's target-neutral direction,
  where a lower Kelvin renders warmer. Cameras and RAW editors use the
  opposite convention: the value is the illuminant being neutralized, so a
  higher setting renders warmer. Phone frames arrive already balanced for the
  scene, so 5600 K is now the as-shot reference (`FilmRecipe.asShotKelvin`)
  and public creator recipes with Kelvin values render in their intended
  direction. Nostalgic Summer's exposure was also eased from +0.67 to +0.45.

The G7 X Compact default was re-tuned against the same fixtures. Near-neutral
warm grays were being treated as skin and drifted brown, so the skin and red
hue sectors now require real chroma before they receive color; skin moves
toward peach/pink (red up, green held, a little blue back) instead of tan;
the global white-balance shift is reduced so walls and fabric stay neutral;
and the face-driven subject lift is gated by luminance so a bright wall behind
a head never becomes a halo. Exposure, tone, saturation, contrast, and
skin smoothing were raised for a clearly compact-camera result that remains
bounded. Saved-photo provenance advances to `core-image-parametric-v9`.

A local-only render gallery test (`RecipeRenderGalleryTests`) attaches
labelled before/after composites for any `FilmyCameraTests/Fixtures/fixture-*.jpg`
photographs present at build time; the fixtures are intentionally not
committed and the test skips without them.
