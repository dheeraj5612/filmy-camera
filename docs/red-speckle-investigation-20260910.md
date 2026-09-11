# Red speckle investigation — September 10, 2026

The saved iPhone JPEG contains bright red contours and speckles around finger creases and nail edges. The user reports the same artifact in preview and saved photos, strongest in Vivid Slide and milder in G7X. This makes an export-only compression or display-only explanation insufficient. The exact cause remains under investigation; the reports below provide diagnostic leads, not proof of an Apple defect.

## Findings from primary sources and firsthand reports

- **Noise reduction can also sharpen.** Apple's [CINoiseReduction reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html#//apple_ref/doc/filter/ci/CINoiseReduction) says luminance differences below its threshold are blurred, while larger differences are sharpened. Its documented default sharpness is 0.40. Our previous mapping set Vivid Slide to 0.9935 and G7X to 0.974, followed by separate sharpness and clarity stages. Disabling the hidden sharpening is a concrete isolation test.
- **Color masks can produce speckled selections.** Blackmagic's [Resolve 17 guide](https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_17_New_Features_Guide.pdf) describes cleaning noise and holes in a matte. It also warns that excessive matte blur can create a halo. A [firsthand Reddit report](https://www.reddit.com/r/davinciresolve/comments/1gd2icw/) describes sharpening breaking a qualifier selection; another [qualifier report](https://www.reddit.com/r/davinciresolve/comments/162ynhx/) reports improvement after smoothing the selection. These involve Resolve, so they support testing the mechanism rather than establishing our cause.
- **GPU failures exist, but the closest reproducible report differs.** This [GitHub reproduction](https://github.com/alexfoxy/ci-metal-shader-bug) reports a sampler-kernel NaN failure on iOS 27 beta, with a passing iOS 26.5 control and a working CIColorKernel. Our observed iPhone runs 26.6.2 and uses CIColorKernel. A separate [iOS 26 firsthand report](https://www.reddit.com/r/iOSProgramming/comments/1l80nky/) concerns precompiled Metal library compatibility and reports success after recompilation with Xcode 26. Neither is an exact match.
- **Color-space and gamut errors remain alternatives.** [MetalPetal's source documentation](https://github.com/MetalPetal/MetalPetal#color-spaces) explains explicit color-space and alpha handling. [ACES documentation](https://docs.acescentral.com/rgc/guides/rgc-implementation/) describes artifacts from out-of-gamut values. Verify finite values, matching color spaces, and clipping before introducing another color correction.

## Application-specific hypothesis and verification

Our skin mask used absolute red–green and green–blue differences. Identical skin hue can cross these thresholds as a crease darkens, reducing protection locally. Sharpening can then exaggerate the color difference. Test brightness-normalized mask terms, protection after detail processing, and zero internal sharpening in CINoiseReduction independently.

Keep Signature at 50%. Preserve luminance texture; avoid a face blur. Cover G7X and Vivid Slide, dark and light skin ramps with creases and fine texture, preview/still/export, finite output and local color continuity. Compare the same input through CPU and actual iPhone GPU rendering. A synthetic passing test does not establish that the user's real scene is fixed; verify a fresh device capture as well.

## Implemented fix and measured results

Renderer v15 normalizes the skin-mask channel differences by luminance, applies protection after sharpness/clarity, and disables CINoiseReduction's internal sharpening. Signature is 50%. The evidence supports this combined fix; it does not isolate one stage as the sole cause.

The 512-pixel crease regression fails against the previous v14 renderer: the largest neighboring normalized warmth-residual jump is 0.5569 for Vivid Slide and 0.2598 for G7X, exceeding the 0.18 limit. The new renderer passes both recipes at preview, photo, and export quality. A separate 2048-pixel photo test checks local chroma continuity and finite output; the 512-pixel test additionally checks overall added warmth.

- Broad simulator validation: 196/196 passed in `build/g7x-build19-validation/Isolated-Renderer-Catalog-Metadata.xcresult`.
- Physical iPad GPU: the 512-pixel regression and seven metadata tests passed in `build/release-build19/ipad-tests/Skin-and-PhotoOutputEncoder-ipad-retry2.xcresult`.
- Physical iPad GPU: final 512- and 2048-pixel tests both passed in `build/release-build19/ipad-tests/NativeSize-and-FineSkin-ipad-retry2.xcresult`.

The final candidate has not yet been tested on the reporting iPhone because it is locked.

## Real capture invalidates the synthetic acceptance result

The user reported continued artifacts and requested review of the latest Vivid Slide photograph. The original cached output was retrieved from the iPad at `build/photo-review-latest/ipad-vivid-slide-v15-latest.jpg`. Its embedded EXIF confirms app 1.0.0 build 19, renderer v15, Vivid Slide, capture time September 10 at 21:48:07 EDT, ISO 1000, 1/60 second, f/2.4, and flash off.

Visual inspection confirms conspicuous orange/red patches along the finger creases and palm, and an excessive overall orange cast. Therefore v15 does **not** resolve the reported defect, and the passing synthetic tests are insufficient acceptance evidence. The problem is now reproduced in a current iPad saved image as well. Build 19 had already uploaded before this confirmation; no external beta review was submitted for it.

The unfiltered capture is not retained by the normal save path. Next diagnostic: an explicitly enabled debug-only capture of the unfiltered source plus final output and render parameters, followed by stage-by-stage comparisons on that exact input. Do not infer the cause solely from the already-filtered JPEG or loosen test thresholds to match it.

Code review also found that `applyRecipeCharacter` is currently uncalled: its 50% strength constant does not affect non-G7X rendering. Restoring the requested shared 50% Signature stage and proving it affects rendered output remains required for the final fix. The diagnostic build preserves the current renderer so the stage comparison starts from the observed failure.
