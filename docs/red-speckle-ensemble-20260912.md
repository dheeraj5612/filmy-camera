# Red speckles: expanded research and open-model review

## Scope and evidence

Read-only investigation; no renderer changes. The connected iPhone has build 23,
renderer v18. Build 24 changes selfie mirroring. The available camera sample is
from build 20/v15, not a fresh reproduction of the user's remaining report.
Current stage exports identify renderer v18/build 24 and reuse that old source.
The preceding run passed 14 selected tests, including the diagnostic exporter
and HalationArtifactRegressionTests; no additional tests were run for this review.

Local samples, relative to repository root (personal images remain untracked):

- `build/skin-diagnostic-pair/latest/source.jpg`: original source.
- `build/skin-diagnostic-pair/latest/final.jpg`: old affected saved output.
- `build/skin-diagnostic-pair/stages-current/velvia-vivid/final.png`: current rerender.
- `build/skin-diagnostic-pair/stages-current/{velvia-vivid,g7x-compact}/`: source,
  postDetail, postSkin, postHalation, bypass, legacy and final comparisons.
- `build/skin-diagnostic-pair/stages-current/render-info.json`: provenance.

## Expanded ensemble

Five additional OpenCode runs were dispatched with the full local context handoff,
code access, explicit sample ages, competing hypotheses and a no-edit constraint:

| Model | Assigned scope | Evidence and limitations |
| --- | --- | --- |
| DeepSeek R1-0528 | Independent mechanism analysis | Speculative halation ranking without causal evidence. Rejected its invented test command and unverified filter API; no web fetches were visible despite its claim of checking documentation. |
| Qwen3 Coder | LUT, gamut, numerical stability | Read code/history but returned largely speculative halation claims; no useful new causal evidence. |
| GLM-4.7 | Capture, GPU, color management, JPEG | Suggested precision/gamut experiments; several proposed controls were invalid and are corrected below. |
| Kimi K2 Thinking | Noise research and experimental design | Consulted OpenCV/Apple references; useful stage-isolation approach, but overstated exclusions and platform limitations. |
| Qwen3-VL-235B Thinking | Visual comparison | Received all three images above; explicitly reported seeing attachments. It judged the old red speckles absent in the current rerender, not proof about a fresh capture. |

Earlier reviews used Qwen3-VL Instruct, DeepSeek V3.2 and Claude Code. Claude's
image reads were blocked by its local hooks. More model votes are not stronger
experimental evidence. Raw expanded-review logs are `/tmp/filmy-ensemble-*.log`.

## Primary research, checked independently

1. [Apple CIContext](https://developer.apple.com/documentation/coreimage/cicontext):
   inputs are converted from their declared spaces into the working space, then
   outputs into the destination space. Relabeling P3 samples as sRGB is not a
   valid conversion or corrective test. Preserve and inspect source metadata.
2. [Apple workingFormat](https://developer.apple.com/documentation/coreimage/cicontextoption/workingformat):
   modern SDK default intermediates are RGBAh. RGBAf context intermediates are
   macOS-only. The renderer does not override this option; merely specifying
   RGBAh is not an increase in intermediate precision. Output RGBA8 and kernel
   arithmetic precision are separate questions.
3. [Apple filter reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/):
   CINoiseReduction is luminance-threshold-based, with a separate sharpness
   control. This renderer already sets that control to zero. Do not claim that
   sharpening is unavoidable or blindly add another RGB blur.
4. [He, Sun and Tang, Guided Image Filtering](https://people.csail.mit.edu/kaiming/publications/eccv10guidedfilter.pdf):
   guidance-aware smoothing can preserve edges. Applying it to a correction
   mask, while retaining image luminance/detail, is a conditional experiment,
   not a demonstrated fix for this capture pipeline.
5. [Apple MPSImageGuidedFilter](https://developer.apple.com/documentation/metalperformanceshaders/mpsimageguidedfilter)
   provides edge-aware filtering on Metal textures. [CIImage texture input](https://developer.apple.com/documentation/coreimage/ciimage/init(mtltexture:options:))
   supports GPU interoperability. CPU round-trips are not inherently required;
   synchronization, color interpretation and performance still need validation.
6. [Apple CIEdgePreserveUpsample](https://developer.apple.com/documentation/coreimage/ciedgepreserveupsample)
   exposes luma-guided upsampling. This is not a drop-in chroma denoiser, but
   contradicts a blanket claim that Core Image has no edge-aware building blocks.
7. [OpenCV colored NLM](https://docs.opencv.org/4.8.0/d1/d79/group__photo__denoise.html)
   separates luminance and chromatic denoising strength in Lab. Use as an offline
   reference experiment before considering any runtime dependency.
8. [Buades, Coll and Morel, Non-Local Means](https://www.ipol.im/pub/art/2011/bcm_nlm/)
   supplies a reproducible research implementation. Its Gaussian-noise model
   does not establish that processed camera noise fits this model.

## Adjudication

- Halation cannot explain a zero-halation G7X render by itself. Vivid's built-in
  amount is small, and its highlight mask is already clamped before blur.
  The existence of a red screen blend alone is not evidence of a remaining bug.
- Spatial skin-mask variability and upstream detail amplification remain
  plausible, unproven mechanisms. Smooth per-pixel gates can still respond to
  noisy neighboring colors. Broad warmth is distinct from isolated chroma spikes.
- Equal RGB grain deltas preserve channel differences before clipping, but later
  clipping can change chroma. Thus grain is not universally exonerated; grain=0
  does exclude it for the available capture's settings.
- The diagnostic exporter uses `outputCGImage` and the shared context, which
  selects Metal when available. It is incorrect to assume all simulator exports
  use software merely because other tests use `testContextOptions`.
- A stage appearing for the first time after skin protection implicates that
  stage or its inputs, not automatically the preceding sharpening stage.
- GPU/device comparisons need measured tolerances, not mandatory bit equality.
  JPEG background-color settings do not control chroma subsampling. Compare
  lossless pixels before encoding with decoded JPEG pixels instead.

## Smallest discriminating experiment

1. Obtain one fresh affected source/final pair plus recipe, build, renderer,
   exposure/ISO where available, input color metadata, and whether preview is
   affected. Keep source bytes identical for all comparisons.
2. Select a visibly affected skin ROI and a clean control ROI. Export source,
   postColorCube, postDetail, postSkin, postHalation and pre-encoding final.
   Measure neighboring opponent-chroma differences at matched luminance, edge
   magnitude and clipped-pixel counts; inspect matching crops, not resized views.
3. Run one-variable ablations: detail/clarity off; skin protection bypassed;
   halation off; grain off. The earliest new artifact and its disappearing
   ablation determine which stage to investigate. Inspect the raw correction
   mask only if skin protection is implicated.
4. Render identical bytes on physical iPhone GPU and host/simulator, recording
   actual context configuration. Compare tolerance-bounded error maps. Separately
   compare pre-encoding pixels with decoded saved output to isolate encoding.
5. Only if mask instability is demonstrated, compare smoothing the mask with a
   luma-guided mask against baseline. Only if source chroma noise is implicated,
   compare chroma-only denoise before detail against baseline. Retain skin
   texture, colored fine detail and preview/export parity; measure device cost.

No new fix or release is justified by the ensemble alone. The unresolved
requirement is a current affected capture, not additional consensus.
