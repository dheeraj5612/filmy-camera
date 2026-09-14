# Local capture replay — 2026-09-13

## Request and evidence

User requests persistent local testing until the latest Vivid Slide sample no longer has red speckling; maintain investigation notes. Use the production pipeline, not an approximate Python renderer. Personal photographs remain outside tracked files.

Fresh paired iPad capture: `/tmp/filmy-latest-ipad-crease-20260913` (source.capture, final.jpg, metadata.json), captured 18:40:21Z, app 1.0.0 (25), renderer v18. Source SHA256 `b8d8157ac90783f7b82d697fc5b3f8396f7a1d8f665f0a50cc8c9350fb3c8005`. Recipe Vivid Slide, instantPrint, grain 0, flash false.

## Initial diagnosis

- Exact source/recipe/crop/grain-phase replay through FilmRenderer on the Mac iOS 26.5 simulator reproduces scattered red crease pixels. Thus the defect is not exclusive to the iPad GPU.
- Baseline stage exports: `/tmp/filmy-mac-stages-v18/velvia-vivid`; native 400px crop at image coordinates x500,y740 makes it visible. Color cube strongly increases warmth; postSkin suppresses most warmth but leaves scattered red pixels.
- In that crop, 876 pixels have >0.5 added normalized red warmth. Representative problematic source pixels have huePosition around 0.145, inside the skin mask's lower hue feather (0.08–0.18), with source luma ~0.20–0.26. The dark-luma cutoff alone does not explain those pixels. Partial skin protection at the red hue boundary amplifies source chroma noise; the final correction below verifies this diagnosis.
- Earlier synthetic tests passed on iPad (16/16); they did not cover this fresh real-source failure. Do not use passing synthetic tests as proof the sample is clean.

## Replay workflow

`scripts/testing/render-capture.py` builds and executes the opt-in RendererSkinCaptureDiagnosticsTests on a Mac simulator. Swift replay calls production CameraViewModel.render, including framing, finish compositor, and JPEG encoder, and additionally exports FilmRenderer stages. Optional variants disable shadow tone, detail, or halation individually. Same code/input/settings does not imply bit-identical results across GPU/runtime/JPEG implementations; compare decoded pixels against the paired device final before asserting parity.

## Follow-up: mask correction

- Full production replay matches iPad dimensions (2496×3501). ICC-aware sRGB decoded comparison: mean absolute error 1.0385/255, p95 3/255, p99 5/255. Same production code, not bit-identical GPU/runtime/JPEG output.
- No-shadow, no-detail, and no-halation ablations all retain visible red speckles (870, 866, 882 high-excess pixels versus baseline 880). Shadow controls are not the cause in this sample.
- Changing the lower skin hue feather from 0.08–0.18 to 0.00–0.08 removes the obvious red crease speckles in the inspected native crop. High-excess pixels drop from 880 to 3; p99 added normalized red falls from 0.2953 to 0.1412. This threshold is a diagnostic, not a universal perceptual clean-image criterion. This initial candidate was rejected by broader red-object tests; see the final correction below.
- Preserved private evidence under ignored `build/red-speckle-local-20260913/{capture,baseline,hue-boundary-fix}` and `crease-comparison.png` (source / baseline / candidate).

## Pending

Build26 TestFlight archive/upload pending. Final v19/build26 verified installed on iPad. Phone installation remains blocked by its lock state; user asked to unlock.

## Regression verification

`RendererRedCreaseRegressionTests` uses a synthetic fixture derived from the observed lower-hue crease colors. Old mask fails the red contour assertion (0.35743 vs limit 0.29466); corrected mask passes while retaining chroma and luminance texture. Logs: `/tmp/filmy-crease-regression-{baseline,fix}.log`. Corrected full JPEG was visually reviewed; the former red contour is absent. Broader renderer checks are running for v19/build26.

## Command

```sh
python3 scripts/testing/render-capture.py \
  --input build/red-speckle-local-20260913/capture \
  --output build/red-speckle-local-20260913/replay-v19-refined \
  --variants --compare
```

`--compare` measures against the original paired device JPEG, so intentional renderer changes also contribute to differences. Use baseline v18 evidence to assess runtime parity. Omit `--skip-build` for trustworthy iteration after source edits.

## Broader validation follow-up

The initial 0.0–0.08 hue feather passed the actual-iPad targeted suite and the crease regression, but the 100-test simulator run found two existing G7X red-separation tests failing (10 assertions). It overprotects saturated red objects. Do not ship that candidate; refining the lower hue interval while preserving the real-capture improvement. Build26 initially installed on iPad is this intermediate candidate; reinstall after final validation. iPhone install failed because the device is locked; user asked to unlock. Portable suite passed 66 tests.


## Final correction and verification

- Final lower hue feather is **0.07–0.12**. It fully protects the observed crease hue (~0.145), while excluding the saturated red-object fixture (~0.0667). No shadow, detail, or halation feature was removed.
- Actual sample replay v19/build26 passed on both Mac simulator and physical iPad. Inspected full Mac output and native crease crops on both: former isolated red speckles are absent; source skin texture remains. Private comparison: `build/red-speckle-local-20260913/refined-comparison.png`.
- Broader simulator suite: **100 tests, zero failures**, `/tmp/filmy-v19-final-checks.log`. Physical iPad targeted suite: **18 tests, zero failures**, `/tmp/filmy-v19-ipad-refined-tests.log`. Actual-source iPad replay: **1 test passed**, `/tmp/filmy-v19-ipad-real-replay.log`. Portable tests: **66 passed**. The new crease test fails with the old mask and passes with the final mask.
- ICC-aware comparison of final v19 Mac versus final v19 iPad: matching 2496×3501 output, mean absolute RGB difference **1.0372/255**, p95 **3/255**, p99 **5/255**, max **26/255**. Same pipeline, not bitwise parity. Replay stage PNGs and final JPEG allow quick local iteration with hardware spot checks.
- Native iPad app readback confirms **1.0.0 (26)** after final refined build; `/tmp/filmy-v19-ipad-app-info.json`. iPad replay provenance matches v19/build26 and the exact source SHA256 above.
- Initial threshold diagnostics used post-skin crops. Final-stage native RGB diagnostic (`refined-crop-metrics.json`) counts added normalized-red >0.5 pixels at 987 baseline versus 49 refined, p99 0.2993 versus 0.1650. These are different stage measurements, not universal perceptual scores. Visual inspection determines acceptance for this sample; it does not prove every possible skin hue is artifact-free.

## Release handoff

- Final implementation committed as `3f34fc9`; release archive built from clean detached worktree `/tmp/filmy-release-build26`.
- Archive `/tmp/filmy-build26/FilmyCamera.xcarchive` passed distribution signing and release validation for 1.0.0 (26). App Store Connect upload succeeded at 2026-09-13 15:13 EDT; package is processing. TestFlight processing completion is not yet verified.
- Physical iPad has the final build26. iPhone installation is pending unlock; do not claim it updated until install succeeds and version is read back.

## User follow-up and regression guard

User reports “nice i think that fixed things” after build26. This supports the sample-level visual verification; it is not a guarantee for every capture.

Cause in plain language: naturally red skin-crease pixels fell near the edge of the skin-color correction mask. Neighboring pixels received different amounts of correction, so the film color transform amplified tiny color differences into red speckles. Adjusting the lower hue transition makes correction consistent across those crease colors. Shadow processing was ruled out by replay ablations and remains enabled.

Regression coverage is committed in `FilmyCameraTests/RendererRedCreaseRegressionTests.swift` and registered in the integration suite. It checks that neighboring crease hues do not develop an exaggerated red contour, while preserving source color and luminance texture. The old renderer fails this fixture; the shipped correction passes. Existing G7X red/sky separation coverage guards against overcorrecting red objects. The 100-test simulator and 18-test physical-iPad suites passed before release; no implementation changed in this follow-up, so those results remain applicable.
