# Filter fidelity audit — 2026-08-21

## Scope

This pass improves perceptual fidelity for the built-in Classic Chrome and
G7 X Compact looks, while retaining the app's explicit non-calibration
disclosures. Public documentation does not expose either vendor's complete
sensor-to-JPEG transform, so pixel-identical reproduction is not a supportable
claim without controlled paired captures from the target hardware.

## References consulted

### Official characteristics

- Fujifilm Classic Chrome overview:
  https://www.fujifilm-x.com/en-us/products/film-simulation/classic-chrome/
- Fujifilm X-T5 image-quality controls:
  https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/
- Canon PowerShot G7 X Mark III product history:
  https://global.canon/en/c-museum/product/dcc884.html
- Canon Picture Style behavior:
  https://cam.start.canon/ky/C001/manual/html/UG-03_Shooting-1_0070.html

The official descriptions provide the acceptance direction used here. Classic
Chrome is subdued, suppresses magenta, and keeps cool shadows. Canon Standard
Picture Style is vivid, sharp, and crisp, while Portrait is smoother and less
sharp. Those descriptions are treated as relative behavior, not proprietary
numeric targets.

### Community look references

- Fuji X Weekly Classic Chrome recipe archive:
  https://fujixweekly.com/tag/classic-chrome/
- Lou & Marks G7 X editing notes:
  https://loumarkspresets.com/blogs/lightroom/canon-g7x-lightroom-edit
- CompareMag G7 X capture notes:
  https://www.comparemag.com/blog/how-to-get-the-glowy-look-on-canon-g7x

Community references are used only to define the social-media "G7 X look"
target: direct-flash subject separation, slightly brighter exposure, warm but
clean skin, controlled highlights, darker backgrounds, crisp color, and no
added film grain. They are not treated as Canon calibration data.

### Open-source processing methods reviewed

- Neutral-profile plus 3D-LUT method:
  https://github.com/TingfengLuo/Camera-Profile-for-Fujifilm-Film-Simulation
- Neutral preprocessing and Lab tone-curve method:
  https://github.com/t3mujinpack/t3mujinpack
- RawTherapee-inspired Fuji presets using tone, HSV, sharpening, and chroma
  noise-reduction controls:
  https://github.com/GLTR87/RawTherapee-presets-Fuji-inspired
- Open film pipeline separating tone, LUT interpolation, halation, and grain:
  https://github.com/thedevmark/film-lab

External LUT files were not copied into the app. Available LUTs commonly assume
a specific RAW camera profile, white balance, exposure, tone curve, and input
color space. Applying one directly to an iPhone display-referred frame would be
less controlled and could introduce licensing ambiguity.

## Method

The renderer keeps neutral input processing separate from the look transform,
then applies smooth hue-sector masks inside the existing deterministic 3D cube.
Classic Chrome now has directly tested magenta suppression and cool-shadow
separation. G7 X Compact now has directly tested warm portrait separation,
selective blue/foliage crispness, bounded neutral-gray cast, and zero
film-grain/halation finishing.

The G7 X target is explicitly split into two layers:

1. **Capture-domain behavior:** direct flash, exposure, lens rendering, subject
   distance, background falloff, and sensor noise. A post-process filter cannot
   recreate these effects exactly after capture.
2. **Rendering behavior:** highlight rolloff, skin hue, saturation, white
   balance, local detail, sharpening, and neutral-gray preservation. These are
   the properties controlled by the current recipe and renderer.

## Acceptance evidence

- Every built-in recipe remains finite and inside normalized RGB bounds.
- Classic Chrome suppresses magenta relative to Provia on the same swatch.
- Classic Chrome maintains greater cool-shadow blue/red separation.
- G7 X Compact increases blue and foliage chroma without materially tinting
  neutral gray.
- G7 X Compact keeps grain and halation disabled by contract.
- Preview, photo, and export remain pixel-identical for the two reference looks
  when the grain phase is fixed.
- A retained XCTest contact sheet renders every built-in look through the real
  renderer for manual inspection in CI artifacts.

## Path to tighter hardware matching

A future calibration pass should photograph a controlled ColorChecker,
skin-tone chart, gray ramp, foliage, blue-sky target, specular highlights, and
night direct-flash portrait on the target Fuji and Canon cameras under fixed
illumination. The same scenes should be captured on the iPhone with exposure,
white balance, focus, flash state, and framing locked. A regularized 3D LUT can
then be fit in a documented neutral input space and validated on separate
holdout scenes.

For the G7 X social-media look, the paired set must include both ambient and
direct-flash captures. Otherwise a fitted color transform will incorrectly try
to encode lighting geometry and flash falloff into color alone. Controlled
paired captures are the defensible route toward substantially closer hardware
matching.
