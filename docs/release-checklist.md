# Filmy Camera release checklist

Current candidate: version 1.0.0, build 5. Historical release notes and older “current” statements are preserved in [release-history.md](release-history.md).

## Verified candidate state

- [x] Build 5 was archived and uploaded from source `d9ef13836fdacea4929dd60cddb32b8eb0afd785`.
- [x] `build/FilmyCamera-d9ef138-signed.xcarchive` passed distribution signing, source provenance, privacy-manifest, and executable/dSYM architecture UUID validation.
- [x] `build/export-d9ef138/FilmyCamera.ipa` passed independent archive parity validation; its recorded SHA-256 is in the [validation record](mvp-validation-20260904.md).
- [x] App Store Connect finished processing build 5. A fresh readback showed build 5 selected and version 1.0 in **Prepare for Submission**.
- [x] The final simulator, physical iPad, full recipe capture-sheet, Roll/share, and performance results are recorded in the [validation record](mvp-validation-20260904.md).
- [x] The production and release-tool audit is recorded in the [MVP audit](mvp-audit-20260904.md).
- [x] Required CI passed on archived source `d9ef138` in [GitHub Actions run 33914142237](https://github.com/dheeraj5612/filmy-camera/actions/runs/33914142237).

## Current head and media

- [x] Required CI passed on `eb5f2a5` in [run 33915751007](https://github.com/dheeraj5612/filmy-camera/actions/runs/33915751007). Later media/test changes need their own PR checks; do not attribute an older run to a newer commit.
- [x] Finish and inspect the five-image current-app packs for the iPhone 6.5-inch and iPad 13-inch slots.
- [x] Upload both final packs to App Store Connect, reload, and verify all five names in numeric order in each device slot.
- [x] Set the connected iPad Auto-Lock to 15 minutes and verify on the device with a temporary Settings runner.

A physical-camera hero can supplement these screenshots after iPhone acceptance. Simulator import/review/Roll images represent those actual app flows; a simulator camera-unavailable screen is not launch media.

The current media workflow uses one public-safe generated original in a fresh simulator. The normal app imports that same original through G7 X Compact, Muted Color, and Fine Monochrome; saves the production outputs; then shows the populated Roll and photo detail. Each device pack contains exactly:

1. `01-g7x-import`
2. `02-film-import`
3. `03-monochrome-import`
4. `04-roll`
5. `05-photo-detail`

## Remaining acceptance and submission

- [ ] Complete iPhone hardware acceptance for lens switching, flash, capture/import parity, save, interruption recovery, and sustained thermal behavior. The completed iPad pass cannot prove iPhone 5× telephoto switching.
- [ ] Complete a controlled portrait and color comparison before making comparative image-quality claims.
- [x] Verify the saved App Review contact phone and email through the visible native browser form after reload. The text snapshot omits these values and is not evidence that they are blank.
- [x] Run Add for Review validation and verify the draft lists iOS App 1.0 / binary 1.0.0 (5) as Item Ready to Submit.
- [x] Confirm saved review notes, age rating, export compliance, free pricing, availability, privacy and public support/privacy URLs; paid-app, banking, tax and Digital Services Act statuses read Active.
- [ ] Account Holder must review and accept the updated Developer Program License Agreement. The Business page reports Active (New Agreement Available) for Free Apps and says acceptance is required before app submission.
- [ ] Submit version 1.0 for App Review and read back the resulting status. Build selection is not submission or public release.

Do not describe the rendering as camera-exact or claim G7 X superiority without controlled same-scene references. Keep the existing original-renderer, non-affiliation, and no-proprietary-data disclosures in the listing.

## Repeatable release workflow

Run from a clean checkout of the source being archived. Do not restamp the existing build 5 archive from a later documentation or test commit.

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
