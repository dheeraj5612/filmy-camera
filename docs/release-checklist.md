# Filmy Camera release checklist

Current candidate: version 1.0.0, build 8, with the [camera UX redesign](design-pass-20260904.md) and [reversible photo review](review-editing-20260904.md). The signed development app is installed on the test iPad. Build 5 remains the last verified Apple upload; App Store Connect requires renewed sign-in for a current readback. Builds 6 and 7 are preserved historical candidates. Historical release notes are in [release-history.md](release-history.md).

## Build 8 release gates

- [x] Implement review look switching and Original comparison with bounded previews, deferred full export, exact retry, and independent shooting selection.
- [x] Pass local 180 unit/integration tests and three normal Photos E2E flows on iPadOS 26.5 and iOS 18.5. The test runner has 20 portable checks and selects 201 app tests for routine CI.
- [x] Install the signed 1.0.0 (8) app and pass all 23 applicable iPad tests. The strengthened physical capture/compare/look-switch/landscape/save case also passed separately.
- [ ] Pass required CI on the final commit, archive the clean source, and validate signed archive/IPA parity.
- [x] Refresh and inspect five iPhone and five iPad store screenshots from isolated public-fixture runs, showing current review controls and matching saved treatments.
- [ ] Upload build 8 and the refreshed media, verify processing, select the matching build/media, and validate the review draft.
- [ ] Complete the iPhone-specific, controlled image-quality, and submission gates below.

## Preserved build 7 release gates

- [x] Implement a camera-first layout, on-demand grouped looks, full-screen review/detail, and pinned return navigation.
- [x] Validate simulator camera portrait/landscape, large text, editor, navigation, and renderer behavior. See [design validation](design-pass-20260904.md#validation) for the full-run and focused rerun evidence.
- [x] Build for physical iOS and install version 1.0.0 (7) on the connected iPad.
- [x] Finish refreshed public-photo screenshot packs on iPhone and iPad simulators; all three normal import/save flows and safe-area/interaction checks passed. Matching Apple uploads remain pending.
- [ ] Complete the redesigned capture/review/save/Retake hardware pass after unlocking the Mac and iPad.
- [ ] Pass required CI, archive the clean final source, and validate signed archive/IPA parity.
- [ ] Upload build 7, verify processing, select it with matching screenshots, and validate the review draft. Prior build 5 draft validation does not validate build 7.

## Preserved build 6 baseline

- [x] Make save success await the off-main atomic local JPEG write and Roll index update. Photos write failures retain their existing recovery; a local cache failure after Photos success must not encourage duplicate saving.
- [x] Validate the new callback-ordering regression and physical add-only save/relaunch flow. The focused simulator suite passed 19 tests with one physical-only skip; all three focused iPad save/callback/flash checks passed without skips or failures.
- [x] Archive and export build 6 from clean source `e2837c603e96aa73b00bb7e24b4c394573dbd43b`; validate executable/dSYM/IPA parity. Artifact paths and SHA-256 are in the [validation record](mvp-validation-20260904.md#post-review-save-fix-and-latest-release-state).
- [x] Restore the iPad's original Photos Full Access permission after the add-only tests and verify installed version 1.0.0 (6).
- [x] Merge the validated source through [PR 80](https://github.com/dheeraj5612/filmy-camera/pull/80). Main commit `b30a4ca85b1ea742ee420713440c365b7c684d8d` has the same tree as archive source `e2837c6`.
- [x] Required CI passed on exact application source `e2837c6` in [run 33924488772](https://github.com/dheeraj5612/filmy-camera/actions/runs/33924488772), including release validation and full unit/UI suites.
Build 6 upload attempts stopped before transfer with `Failed to Use Accounts`. They are preserved as release evidence; build 7 is now the upload target.

## Verified build 5 baseline

- [x] Build 5 was archived and uploaded from source `d9ef13836fdacea4929dd60cddb32b8eb0afd785`.
- [x] `build/FilmyCamera-d9ef138-signed.xcarchive` passed distribution signing, source provenance, privacy-manifest, and executable/dSYM architecture UUID validation.
- [x] `build/export-d9ef138/FilmyCamera.ipa` passed independent archive parity validation; its recorded SHA-256 is in the [validation record](mvp-validation-20260904.md).
- [x] App Store Connect finished processing build 5. A fresh readback showed build 5 selected and version 1.0 in **Prepare for Submission**.
- [x] The final simulator, physical iPad, full recipe capture-sheet, Roll/share, and performance results are recorded in the [validation record](mvp-validation-20260904.md).
- [x] The production and release-tool audit is recorded in the [MVP audit](mvp-audit-20260904.md).
- [x] Required CI passed on archived source `d9ef138` in [GitHub Actions run 33914142237](https://github.com/dheeraj5612/filmy-camera/actions/runs/33914142237).

## Preserved build 5 media and earlier CI

- [x] Required CI passed on `e4b63da` in [run 33919773477](https://github.com/dheeraj5612/filmy-camera/actions/runs/33919773477), including the current media and screenshot-test isolation fix. Later test changes need their own PR checks; do not attribute an older run to a newer commit.
- [x] Finish and inspect the five-image current-app packs for the iPhone 6.5-inch and iPad 13-inch slots.
- [x] Upload both final packs to App Store Connect, reload, and verify all five names in numeric order in each device slot.
- [x] Set the connected iPad Auto-Lock to 15 minutes and verify on the device with a temporary Settings runner.

A physical-camera hero can supplement these screenshots after iPhone acceptance. Simulator import/review/Roll images represent those actual app flows; a simulator camera-unavailable screen is not launch media.

The media workflow uses one public-safe generated original in a fresh simulator. The normal app imports that same original through G7 X Compact, Muted Color, and Fine Monochrome; saves the production outputs; then shows the populated Roll and photo detail. Each device pack contains exactly:

1. `01-g7x-import`
2. `02-film-import`
3. `03-monochrome-import`
4. `04-roll`
5. `05-photo-detail`

## Remaining acceptance and submission

- [ ] Complete iPhone hardware acceptance for lens switching, flash, capture/import parity, save, interruption recovery, and sustained thermal behavior. The completed iPad pass cannot prove iPhone 5× telephoto switching.
- [ ] Complete a controlled portrait and color comparison before making comparative image-quality claims.
- [x] Verify the saved App Review contact phone and email through the visible native browser form after reload. The text snapshot omits these values and is not evidence that they are blank.
- [x] Run Add for Review validation for the build 5 baseline. The draft was subsequently removed for replacement; its prior successful validation does not submit or validate build 6.
- [x] Confirm saved review notes, age rating, export compliance, free pricing, availability, privacy and public support/privacy URLs; paid-app, banking, tax and Digital Services Act statuses read Active.
- [x] The updated Free Apps agreement is Active, effective September 4, 2026, with no pending-agreement banner on the subsequent Business-page readback.
- [x] Select **Manually release this version**, save, and verify after reload. Apple approval must not automatically publish before the remaining iPhone acceptance.
- [ ] Submit version 1.0 for App Review and read back the resulting status. Build selection is not submission or public release.

Do not describe the rendering as camera-exact or claim G7 X superiority without controlled same-scene references. Keep the existing original-renderer, non-affiliation, and no-proprietary-data disclosures in the listing.

## Repeatable release workflow

Run from a clean checkout of the source being archived. Use the recorded source revision when validating an existing archive; do not restamp build 5 or build 6 from a later documentation or test commit.

```sh
scripts/release/archive-device.sh
scripts/release/validate-archive.sh build/FilmyCamera-<source-sha>-signed.xcarchive
scripts/release/prepare-upload.sh --check
scripts/release/prepare-upload.sh --export
scripts/release/validate-ipa.sh \
  --ipa build/export-<source-sha>/FilmyCamera.ipa \
  --archive build/FilmyCamera-<source-sha>-signed.xcarchive
scripts/release/prepare-upload.sh --upload
```

The check mode is read-only. Export and upload require explicit modes plus valid external signing/App Store credentials. Never commit certificates, profiles, API keys, or upload credentials.
