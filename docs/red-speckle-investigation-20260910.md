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

Renderer v15 normalizes the skin-mask channel differences by luminance, applies protection after sharpness/clarity, and disables CINoiseReduction's internal sharpening. Its Signature constant was 50%, but the shared stage was later found to be disconnected (see below). These initial synthetic results did not establish a fix for the real capture.

The 512-pixel crease regression fails against the previous v14 renderer: the largest neighboring normalized warmth-residual jump is 0.5569 for Vivid Slide and 0.2598 for G7X, exceeding the 0.18 limit. The new renderer passes both recipes at preview, photo, and export quality. A separate 2048-pixel photo test checks local chroma continuity and finite output; the 512-pixel test additionally checks overall added warmth.

- Broad simulator validation: 196/196 passed in `build/g7x-build19-validation/Isolated-Renderer-Catalog-Metadata.xcresult`.
- Physical iPad GPU: the 512-pixel regression and seven metadata tests passed in `build/release-build19/ipad-tests/Skin-and-PhotoOutputEncoder-ipad-retry2.xcresult`.
- Physical iPad GPU: final 512- and 2048-pixel tests both passed in `build/release-build19/ipad-tests/NativeSize-and-FineSkin-ipad-retry2.xcresult`.

At that stage, the v15 candidate had not been tested on the reporting iPhone because it was locked.

## Real capture invalidates the synthetic acceptance result

The user reported continued artifacts and requested review of the latest Vivid Slide photograph. The original cached output was retrieved from the iPad at `build/photo-review-latest/ipad-vivid-slide-v15-latest.jpg`. Its embedded EXIF confirms app 1.0.0 build 19, renderer v15, Vivid Slide, capture time September 10 at 21:48:07 EDT, ISO 1000, 1/60 second, f/2.4, and flash off.

Visual inspection confirms conspicuous orange/red patches along the finger creases and palm, and an excessive overall orange cast. Therefore v15 does **not** resolve the reported defect, and the passing synthetic tests are insufficient acceptance evidence. The problem is now reproduced in a current iPad saved image as well. Build 19 had already uploaded before this confirmation; no external beta review was submitted for it.

The unfiltered capture is not retained by the normal save path. Next diagnostic: an explicitly enabled debug-only capture of the unfiltered source plus final output and render parameters, followed by stage-by-stage comparisons on that exact input. Do not infer the cause solely from the already-filtered JPEG or loosen test thresholds to match it.

Code review also found that `applyRecipeCharacter` is currently uncalled: its 50% strength constant does not affect non-G7X rendering. Restoring the requested shared 50% Signature stage and proving it affects rendered output remains required for the final fix. The diagnostic build preserves the current renderer so the stage comparison starts from the observed failure.

## Paired-source reproduction and isolated cause

Build 20 captured a paired original/result at September 10, 22:09:08 EDT. The original is a Display P3 JPEG at ISO 800 with flash off. Its crease detail does not contain the conspicuous red bands visible in the filtered result. The pair remains local under `build/skin-diagnostic-pair/latest/`.

Re-rendering that exact original through the normal v15 pipeline reproduces the red bands. Exporting intermediate stages shows that the color transform adds warmth broadly, while the skin correction suppresses it unevenly. Its upper saturation exclusion fades protection between saturation 0.68 and 0.90 and removes protection above 0.90. Legitimate warm skin in this capture crosses that range, especially along darker creases. The prior synthetic fixture stayed below the boundary and could not detect this failure.

Removing **only** that upper saturation exclusion removes the conspicuous red bands in the paired-source Vivid Slide and G7X renders while retaining crease texture. In a fixed sampled hand region, the 95th percentile of added normalized red warmth falls from 0.8897 to 0.1524 for Vivid Slide and from 0.5100 to 0.0870 for G7X. These are diagnostic measurements, not universal image-quality thresholds. The stage-export run passed in `build/skin-diagnostic-pair/StageExport-v15.xcresult`; images and measurements are in `build/skin-diagnostic-pair/stages-v15/`.

This experiment establishes an app-specific cause for the reproduced defect. The internet reports helped choose experiments; they do not establish an Apple GPU defect. Final acceptance still requires the permanent change, the restored 50% Signature stage, expanded saturated-skin regression coverage, and physical-device verification.


## Remaining failures with restored Signature and wide-gamut input

The first v16 candidate removed the upper saturation exclusion and restored the actual shared Signature stage at 50%. The real capture no longer had the red bands on either simulator or physical iPhone GPU. However, two expanded synthetic tests still failed on both: the fine-skin fixture retained excessive orange in a deep shadow, and the Display P3 fixture showed abrupt chroma changes. This candidate was not accepted for upload.

Worst-pixel diagnostics isolate two additional mechanisms. A fully selected skin pixel retained 0.4287 added normalized warmth because a fixed 85% correction leaves 15% of an arbitrarily strong grade. In the saturated fixture, Display P3 source colors transformed into extended sRGB with negative blue values (for example `[0.9772, 0.2748, -0.1628]`). The old correction compared warmth against that out-of-gamut reference before fitting only its upper channel limit. Subsequent clipping of the negative blue value produced a large visible change near the correction threshold. The mask itself was fully selected at these pixels; this was a gamut/comparison-order failure, not another saturation exclusion.

The revised v16 candidate fits reference chroma to **both** ends of the destination gamut before measuring warmth. A smooth bounded residual replaces fixed-percentage correction: for a fully selected pixel outside highlight fade, residual warmth approaches 0.12 as the incoming excess increases. It keeps rendered luminance and uses no spatial blur. Signature remains 50%. Final simulator validation and physical-device availability are recorded below.


The revised kernel passed 55 of 56 renderer/Signature/real-source checks. Inspection of the remaining test's exact pixels revealed a measurement error: source normalized red contrast was 0.2353, while rendered contrast was 0.0256. Taking the absolute *change in residual* incorrectly classified that reduction as a 0.2097 discontinuity. The Display P3 test now measures amplification of neighboring hue contrast. Its 0.20 threshold is unchanged; added warmth and raw chroma-step limits are unchanged. A counterfactual render with the legacy saturation cutoff must exceed that same threshold, ensuring the corrected metric still detects the original failure. Existing 512- and 2048-pixel tests remain unchanged.


## Final v16 validation

- The final kernel passed the other 55 renderer, Signature, and real-source checks in `build/skin-diagnostic-pair/FinalRenderer-v16-rerun.xcresult`. That run's one failing test was the Display P3 measurement subsequently corrected above; production code did not change afterward.
- The corrected saturated-skin regression, its legacy-cutoff counterfactual, catalog acceptance, EXIF encoder, color-space boundaries, flash availability, and recipe invariants passed **219/219** with no skips in `build/release-build21/validation/Final-Catalog-Metadata-Saturated.xcresult`. Together these runs cover 274 distinct passing checks on the final code/test behavior.
- The exact paired original was rendered through the final kernel for both Vivid Slide and G7X. Visual inspection confirms the conspicuous red bands are absent and crease texture remains. Local images: `build/skin-diagnostic-pair/stages-v16-final/`.
- Physical iPhone testing of the intermediate upper-gate-only fix reproduced the earlier synthetic failures and rendered the same real-source improvement. It is not validation of the final gamut/bounded-warmth revision. Both devices became locked before that final revision could be tested or installed. Lock/preparation evidence is under `build/release-build21/final-verification/`. Device verification remains pending unlock; no hardware-GPU claim is made for the final revision.

The final release candidate is app 1.0.0 build 21, renderer `core-image-parametric-v16`. It includes the shared 50% Signature stage, the skin-color fixes, the earlier flash-off correction, and populated capture EXIF/app provenance. Personal diagnostic photographs remain ignored local artifacts, not test fixtures committed to the repository.


Release identity follow-up: the intermediate build 21/v16 had already been installed on the iPhone. Persistent recipe thumbnails are keyed by renderer version, so the final release is **build 22 / renderer v17** to invalidate those cached previews and distinguish it from the diagnostic candidate. The rendering kernel is identical to the final validated v16 revision above. Build 21's archive was preserved but was not uploaded.

Build 23 / renderer v18 (2026-09-11, source `e94737c`) layers the PR #96 halation-mask fix (clamped highlight mask instead of the `CIMaskToAlpha` path that could emit negative values) on top of the v17 skin-protection kernel; the version bump again invalidates cached recipe thumbnails. Archive validated with `scripts/release/validate-archive.sh` and uploaded to App Store Connect via the native Xcode account (`build/release-build23-final/release-evidence.json`). 238/238 focused simulator tests passed on the merged tree; the physical-device GPU pass and a fresh real-capture check are still open because both devices were locked.
