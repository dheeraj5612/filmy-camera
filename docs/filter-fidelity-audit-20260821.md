# Filter fidelity audit — 2026-08-21

## Scope

This pass improves perceptual fidelity for the built-in Classic Chrome and
G7 X Compact looks, while retaining the app's explicit non-calibration
disclosures. Public documentation does not expose either vendor's complete
sensor-to-JPEG transform, so pixel-identical reproduction is not a supportable
claim without controlled paired captures from the target hardware.

## References consulted

- Fujifilm Classic Chrome overview:
  https://www.fujifilm-x.com/en-us/products/film-simulation/classic-chrome/
- Fujifilm X-T5 image-quality controls:
  https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/
- Fuji X Weekly Classic Chrome recipe archive:
  https://fujixweekly.com/tag/classic-chrome/
- Canon PowerShot G7 X Mark III:
  https://global.canon/en/c-museum/product/dcc884.html
- Canon Picture Style behavior:
  https://cam.start.canon/ky/C001/manual/html/UG-03_Shooting-1_0070.html
- Open-source neutral-profile plus 3D-LUT method:
  https://github.com/TingfengLuo/Camera-Profile-for-Fujifilm-Film-Simulation
- Open-source neutral preprocessing and Lab tone-curve method:
  https://github.com/t3mujinpack/t3mujinpack

## Method

The renderer keeps neutral input processing separate from the look transform,
then applies smooth hue-sector masks inside the existing deterministic 3D cube.
Classic Chrome now has directly tested magenta suppression and cool-shadow
separation. G7 X Compact now has directly tested warm portrait separation,
selective blue/foliage crispness, bounded neutral-gray cast, and zero
film-grain/halation finishing.

External LUT files were not copied into the app. Most available LUTs assume a
specific RAW camera profile, white balance, exposure, and input color space.
Applying one directly to an iPhone display-referred frame would make the result
less controlled and could create licensing ambiguity.

## Acceptance evidence

- Every built-in recipe remains finite and inside normalized RGB bounds.
- Classic Chrome suppresses magenta relative to Provia on the same swatch.
- Classic Chrome maintains greater cool-shadow blue/red separation.
- G7 X Compact increases blue and foliage chroma without materially tinting
  neutral gray.
- Preview, photo, and export remain pixel-identical for the two reference looks
  when the grain phase is fixed.
- A retained XCTest contact sheet renders every built-in look through the real
  renderer for manual inspection in CI artifacts.

## Path to tighter hardware matching

A future calibration pass should photograph a controlled ColorChecker,
skin-tone chart, gray ramp, foliage, and sky targets on the target Fuji and
Canon cameras under fixed illumination. The same scene should be captured on
the iPhone with exposure and white balance locked. A regularized 3D LUT can
then be fit in a documented neutral input space and validated on separate
holdout scenes. That is the defensible route toward substantially closer
hardware matching.
