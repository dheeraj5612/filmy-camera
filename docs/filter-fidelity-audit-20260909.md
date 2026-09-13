# Filter fidelity audit — 2026-09-09

Three reversed controls and a G7 X color regression were corrected. The latest
simulator core run passed **411 tests**, including all 128 catalog cases and
27 numeric-control endpoint effects. An earlier physical run delivered 128
distinct photographs with renderer v10; complete v11 physical acceptance remains
pending. This audit does not certify a Fujifilm, Canon or film-stock match.

## Confirmed defects and fixes

| Control | Previous result | Corrected result | Primary evidence |
| --- | --- | --- | --- |
| Positive Highlights | Darkened highlights, using the same polarity as Shadows | Brightens highlights; negative values soften the shoulder | [Fujifilm: Creating Your Own Black & White Look](https://www.fujifilm-x.com/en-gb/learning-centre/creating-your-own-black-white-look/) and [Fujifilm image-quality FAQ](https://digitalcamera-support-en.fujifilm.com/digitalcameraengpcdetail?aid=000008353) |
| Incandescent white balance | Increased a warm cast | Cools the image to compensate tungsten warmth | [Fujifilm: Make Better Images Indoors](https://www.fujifilm-x.com/en-gb/learning-centre/make-better-images-indoors/) |
| Underwater white balance | Increased a blue cast | Adds warmth to reduce the blue cast | [Fujifilm X-T5 white balance reference](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/#white_balance) |

The polarity corrections initially used `core-image-parametric-v10`. The
compact highlight shoulder then exposed weaker saturated-red and sky separation
than the standard control after Highlights was corrected. Compact-only red/blue
hue gains now preserve that intended separation; skin, foliage, and neutral
assertions remain unchanged. A new test covers multiple highlight settings and
every quality tier without relaxing the original assertions.

The final renderer uses `core-image-parametric-v11`, invalidating thumbnails
generated during the v10 device run and recording the change in new JPEG
provenance. Existing recipe numbers and saved user controls remain intact.
These corrections intentionally change their previously reversed rendering.

## Coverage and runtime status

The latest [core summary](../build/exhaustive-qa-20260909/simulator-final2-core/filmycamera-core-summary.json)
records 411 passed / 0 failed / 0 skipped at build-input digest
`e07eb74fc36b33661129d8808279e4b4d911da06cf6ccf6cc761571d9317c3c5`.
Earlier v11 runs passed 405 cases at `caac243…` and 408 at `d3f2a5ab…`;
the additions cover Roll ownership/paging beyond former limits and safe sensor
white-balance gains during camera switching. These core results do not substitute
for the remaining physical camera and UI lanes.

| Scope | What was checked | Actual result |
| --- | --- | --- |
| All 128 catalog recipes | Separate chart, bundled daylight and low-light renders; dimensions, finite pixels, tonal range, monochrome behavior, JPEG metadata | Passed in v11 core; all 8 fixture contact sheets / 128 rows visually inspected |
| Preview/photo/export consistency | Identical pixels across quality paths for every built-in look | Passed in v11 core |
| All 27 numeric recipe controls | Each control's endpoints change actual pixels; Kelvin, monochrome and grain prerequisites enabled | Passed in v11 core; this does not establish every extreme combination is aesthetically good |
| Three corrected directions | Incandescent, Underwater, and positive/negative Highlights/Shadows at every quality tier | Passed in v11 core |
| G7 X selective color | Red and sky separation, with original skin/foliage/neutral assertions retained; multiple Highlights values and quality tiers | Failed before compact hue correction; passed with v11 |
| More than 100 physical photographs | One fresh sensor capture per recipe; unique original/output hashes and timestamps, encoded dimensions and provenance | **128 passed with v10**, all 128 original/output pairs hash-verified and visually reviewed at sheet scale; final v11 catalog is pending |
| Physical v11 output | Two Roll runs each saved three new photographs; two interrupted catalog attempts delivered 66 and 78 of 128 | Both Roll cases passed. Completed attachment sets passed integrity checks; both catalog cases failed. The 66-frame run had three obstructed/partly obstructed originals; the 78-frame run had one blurred/obscured and seven black originals |
| Physical v11 rendering timings | Preview render, full-resolution import, portrait detector sampling | 3 tests passed; short fixture measurements, not sustained camera/thermal certification |

The physical catalog [verification manifest](../build/exhaustive-qa-20260909/physical-catalog/review/verification.json)
records 128 requests and 128 delivered/encoded images in 207 seconds, zero
camera runtime errors, and 3024×4032 finished JPEGs. All 256 original/filtered
JPEGs and 128 per-shot JSON files were reconciled. The lane also contained a
separate UI case that failed to initialize; therefore the whole lane was not green.
The later v11 camera attempt entered background and delivered **zero** captures;
its manual/flash failures remain open, separately from three passing rendering
performance tests in the same result bundle. A subsequent attempt at `d3f2a5ab…`
delivered 66 new paired captures before request 67 failed on backgrounding.
Its [verification](../build/exhaustive-qa-20260909/device-final-hardware-review/review/verification.json)
marks full-catalog acceptance false and lists the missing 62 recipes. Lens/flash
cases failed; two manual cases skipped because their required opt-in flag was
missing from that command.

All 11 physical contact sheets were inspected. There were no gross broken
renders, monochrome leakage, orientation errors or border seams at that scale.
Pastel 400, Archive 64, Green 800 and Pacific Blues further clipped lamps/white
walls. Three original-resolution files were opened, but the tool displayed them
downsampled to 1368×1824; native-pixel quality for every image is unverified.
See [visual notes](../build/exhaustive-qa-20260909/visual-review-notes.json),
[physical review](../build/exhaustive-qa-20260909/physical-catalog/review/index.html)
and [v11 fixture review](../build/exhaustive-qa-20260909/simulator-v11-core/recipe-review/index.html).

The catalog lane keeps its images in local test attachments and does not add them
to Photos. It counts distinct camera files, not filtered versions of one source.
Six Roll acceptance photos across two passing runs were saved and retained separately. Simulator
fixtures, screenshots and the zero-capture v11 attempt do not increase the
physical photograph count. The three catalog manifests contain **272 distinct source hashes**,
output hashes and timestamps with no overlap; together with six Roll photos,
at least **278 physical photographs** are documented. All 24 physical contact
sheets were reviewed. The [66-frame visual review](../build/exhaustive-qa-20260909/device-final-hardware-review/review/visual-review.json)
flags obscured frames 1 and 63 and partly obscured/blurred frame 64. The
[78-frame visual review](../build/exhaustive-qa-20260909/device-final2-hardware-review/review/visual-review.json)
flags severe blur/obstruction at 71 and black originals at 72–78; those black
frames failed luminance/range checks. These eleven frames count as captures but
do not provide clean scene-quality comparisons. Readiness for frame 79 timed
out before the request; no final 128-recipe v11 physical pass is claimed.

## Accuracy boundaries and follow-ups

The implementation contains original parametric transforms. The
[Fujifilm film-simulation overview](https://www.fujifilm-x.com/en-us/products/film-simulation/)
supports the intended color/contrast families, grain states, monochrome filters,
and control vocabulary. It supplies no transferable calibration. Likewise,
[Canon's G7 X Mark III reference](https://global.canon/en/c-museum/product/dcc884.html)
does not establish equivalent iPhone optics or processing. Paired captures with
matched exposure, lighting, targets, and reference hardware are still required
for a calibrated fidelity claim. One bed scene cannot establish skin-tone,
landscape, mixed-light, or portrait-subject quality.

Two approximation limits are now explained beside the relevant editor controls:

- **Automatic dynamic-range choices:** DR Auto and D Range Priority Auto use
  fixed rendering strengths. They do not meter scene contrast or control sensor
  exposure. New help explicitly describes the preset strength and absence of
  scene metering. Scene-dependent automatic selection is not implemented.
- **White Priority and Custom 1–3:** these modes currently reuse the phone's
  existing balance and shared editable shifts. They do not independently measure
  or store custom reference whites. New help states that they start from captured
  white balance and that custom white measurement is unavailable.

Both distinctions follow from the
[X-T5 control descriptions](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/).
They are broader approximation limits, separate from the three directly
reversed controls. The help is implemented in source; the complete color-editor settings/reset
case passed in the corrected targeted simulator UI run, while physical controls
acceptance remains pending. The remaining hardware, settings and state-transition coverage
is tracked in the [feature QA report](exhaustive-qa-coverage-20260909.md).
