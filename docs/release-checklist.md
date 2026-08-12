# Filmy Camera release checklist

## Current workspace gate

- [x] Verify the production Swift app target is present under `FilmyCamera/`.
- [x] Exercise the production `FilmRecipe.builtIns` and `FilmRenderer.render` APIs from XCTest.
- [x] Confirm the generated Xcode project exposes the `FilmyCamera` scheme, unit tests, and UI tests.
- [x] Verify the simulator camera shell, editable recipe controls, accessibility labels, and empty-state recovery surface.

## Product and device QA

- [ ] Test camera permission denial, recovery, and first-run messaging on a physical iPhone.
- [ ] Test photo-library permission denial, limited access, save, and recent-photo behavior.
- [ ] Verify preview and saved output use the same selected recipe, including the capture-review handoff (the shared aspect-fill crop and fail-closed render path are covered in simulator tests; physical-device verification remains open).
- [ ] Verify output bounds, orientation, image dimensions, metadata, and memory use with representative photos.
- [ ] Test every bundled recipe in bright daylight, low light, skin tones, sky, and mixed lighting.
- [ ] Test interruption/resume for phone calls, backgrounding, camera unavailable, and low storage.
- [ ] Verify VoiceOver labels, Dynamic Type, contrast, hit targets, and Reduce Motion behavior.
- [ ] Confirm the app never claims affiliation with or ships proprietary Fujifilm data.

## Build and release artifacts

- [x] Run `xcodegen generate` from a clean checkout.
- [x] Run the credential-free release project preflight (`scripts/release/validate-project.sh`).
- [x] Run the iPhone Simulator build and XCTest workflow locally (39 unit/renderer tests plus 2 UI tests, 41 total, on iOS 18.5 and iOS 26.5 runtimes).
- [x] Re-run the hosted Xcode 16.4 workflow for this production-hardening pass and verify the exact merged SHA.
- [x] Keep release-script syntax, ShellCheck, and fail-closed upload-preparation checks in CI.
- [ ] Run a Release archive on a physical-device destination.
- [x] Validate `Info.plist`, launch behavior, app icon, version `1.0.0`, and build number `1`.
- [ ] Run App Store Connect upload validation and retain the archive plus dSYM/ symbol artifacts.
- [x] App Store metadata draft prepared; final App Store Connect pricing, availability, screenshots, legal copy, and support contact remain open.
- [ ] Produce required device screenshots and an optional preview video.
- [x] Confirm the privacy policy, GitHub support URL, and marketing URL are live.

## App Store Connect and Apple requirements

- [ ] Enroll in the Apple Developer Program and accept current agreements.
- [ ] Create the App Store Connect app record with bundle ID `com.dheeraj.filmycamera`.
- [ ] Register/verify the bundle identifier in the Apple Developer portal.
- [ ] Configure signing certificates, provisioning profiles, and the CI keychain strategy for device archives.
- [ ] Create an App Store Connect API key or use an authenticated Xcode/Transporter account for upload.
- [ ] Complete App Privacy answers, age rating, export-compliance answers, pricing, availability, and tax/banking setup.
- [ ] Supply a valid privacy policy URL, support URL, and support contact.
- [ ] Submit TestFlight build for review, test with external testers, and resolve review feedback.
- [ ] Submit the production version and confirm release timing.

## Credential boundary

The simulator build/test workflow intentionally uses no Apple Developer credentials and should run with signing disabled. The following still require the account owner or an authorized release operator:

- Apple Developer Program/App Store Connect access
- Team ID, bundle-ID registration, signing certificate, and provisioning profile
- App Store Connect API key or authenticated upload session
- Live privacy/support/marketing URLs and support email

Do not commit certificates, provisioning profiles, API keys, or App Store Connect credentials to this repository or GitHub Actions logs.

## Release automation

After the physical device and Apple Distribution signing are available:

```sh
scripts/release/archive-device.sh
scripts/release/validate-archive.sh build/FilmyCamera.xcarchive
scripts/release/prepare-upload.sh --check
scripts/release/prepare-upload.sh --export
scripts/release/prepare-upload.sh --upload
```

The archive wrapper generates the project and creates a Release archive for a generic iOS device. The upload-preparation wrapper is read-only by default, validates the archive and local signing material before export, requires explicit `--export` or `--upload` modes, and keeps App Store Connect keys outside the repository. It fails closed unless the archive and exported IPA have the expected bundle/version, distribution signature, provisioning profile, dSYM, and privacy manifest. It never stores credentials in the repository or CI logs.

## Verified evidence

- Last verified app-code mainline: `1268341282b0dbcf49e9d0ca93b12b17f3d53192`
- Production-hardening PR: [PR #31](https://github.com/dheeraj5612/filmy-camera/pull/31) — merged after green hosted checks on the pushed branch SHA.
- Mainline GitHub Actions run: [31650506505](https://github.com/dheeraj5612/filmy-camera/actions/runs/31650506505) — green Xcode 16.4 simulator build; the 39 unit/renderer tests and 2 UI tests passed, with generated-project reproducibility, release preflight, artifact/log retention, ShellCheck, metadata validation, and the fail-closed upload-preparation lane.
- Previous mainline baseline: [31647529461](https://github.com/dheeraj5612/filmy-camera/actions/runs/31647529461) — green Xcode 16.4 simulator build before this production-hardening pass.
- Current local simulator verification: 39 unit/renderer tests plus 2 UI tests passed on iOS 18.5 and iOS 26.5; the gallery/settings UI flow, renderer-backed recipe thumbnails, Tune flow, capture-review handoff, typed camera availability states, flash availability contract, Photos authorization policy, VoiceOver focus action, privacy/support links, and accessibility tree were verified.
- Local release project preflight: `scripts/release/validate-project.sh` passed for bundle `com.dheeraj.filmycamera`, version `1.0.0 (1)`, the privacy manifest, the 1024×1024 icon, and all expected schemes/tests.
- Current local simulator: iPhone 16 Pro, iOS 18.5 — camera shell, recipe editor, Gallery/Settings navigation, accessibility tree, screenshots, and simulator capture fallback verified.
- Historical unsigned archive: `/tmp/filmycamera-rc-20260812-ui-deterministic.xcarchive` — contains dSYM and `PrivacyInfo.xcprivacy`, but predates current main; rebuild and pin a current archive before release use.
- Current product evidence covers Provia Standard, typed camera-session recovery, deterministic UI-test mode, saved recipe/date provenance, share/delete actions in Gallery, in-app privacy/support links, VoiceOver center focus/exposure, and release-script fail-closed behavior. The archive validator now fails closed on a missing profile, mismatched team/bundle/version/build, expired profile, enabled `get-task-allow`, missing dSYM/privacy manifest, or non-distribution signature. Signing is only declared in project settings for team `AQW5C8DEEG`; CI remains simulator-only and unsigned, with no signed device archive or App Store submission proven.
- Mainline evidence now includes a renderer-backed synthetic recipe rail, canonical look parity across quality tiers, typed monochrome channel response, hue-aware Color Chrome/FX Blue behavior, deterministic grain, explicit photo dimensions, capture provenance, filtered JPEG metadata, shared preview/still aspect-fill framing, and a fail-closed render path. The exact merged mainline SHA and hosted run above are green; signed-device and App Store evidence remain open.
- Signing follow-up: [PR #4](https://github.com/dheeraj5612/filmy-camera/pull/4) and [PR #5](https://github.com/dheeraj5612/filmy-camera/pull/5) merged with green simulator/XCTest checks.
- Physical QA and App Store Connect submission remain open until device and Apple account access are available.
