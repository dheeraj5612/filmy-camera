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
- [x] Run the iPhone Simulator build and XCTest workflow locally; the current local evidence is 67 unit/renderer tests plus 3 UI tests (70 total) on both iOS 18.5 and iOS 26.5 simulator runtimes.
- [x] Re-run the hosted Xcode 16.4 workflow for this production-hardening pass and verify the exact merged SHA.
- [x] Keep release-script syntax, ShellCheck, and fail-closed upload-preparation checks in CI.
- [ ] Run a Release archive for a generic iOS device destination; verify the signed archive and app on a physical iPhone before upload.
- [x] Validate `Info.plist`, launch behavior, app icon, version `1.0.0`, and build number `1`.
- [ ] Run App Store Connect upload validation and retain the archive plus dSYM/ symbol artifacts.
- [x] App Store metadata draft prepared; final App Store Connect pricing, availability, screenshots, legal copy, and support contact remain open.
- [x] App Privacy answer matrix reviewed against the source tree in `docs/app-store/app-privacy.md`; entering the answers in App Store Connect remains an account-owner step.
- [ ] Produce required device screenshots and an optional preview video.
- [x] Confirm the privacy policy, public support URL, and marketing URL are live.

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

For headless provisioning, `archive-device.sh --allow-provisioning-updates` accepts the same `FILMY_ASC_KEY_ID`, `FILMY_ASC_ISSUER_ID`, and `FILMY_ASC_KEY_PATH` environment variables as the upload wrapper. Partial credentials and repository-local key paths are rejected before Xcode runs.

The hosted workflow keeps the release-script gate on metadata and checklist changes, while the simulator build lane runs only when binary-affecting files change. Unknown or manually dispatched scopes fail open so required validation is never silently skipped.

## Verified evidence

- Latest app-code mainline: `255008fd82e0a3d8d834e256638f827a19390904`
- Latest hardening commits: `fb51d6879a10146837ea3212ac698049eefed8fa` (headless release credential checks), `47c93dce619bcc031b89d2802fa91013c1c49c00` (CI workflow), `f6799ab9fbcb87b9b28c4d9569e4a13de27b7cfd` (Photos ownership/cache safety), and `1662f833f8909e1dd535a05075282ea230b1202b` (camera/review error states).
- Latest app-code evidence: [run 31720714081](https://github.com/dheeraj5612/filmy-camera/actions/runs/31720714081) — green on exact merged SHA `255008fd82e0a3d8d834e256638f827a19390904`; Xcode 16.4 generated-project reproducibility, 65 unit/renderer tests, 3 UI tests, release preflight, artifact retention, ShellCheck, metadata validation, and fail-closed upload-preparation checks passed.
- Previous full iOS evidence: [run 31671146304](https://github.com/dheeraj5612/filmy-camera/actions/runs/31671146304) — green on exact code SHA `3ae90dd64e37d31e9ee6c1d84d223eec2fc3070a`; Xcode 16.4 generated-project reproducibility, 61 unit/renderer tests, 2 UI tests, release preflight, artifact retention, ShellCheck, metadata validation, and fail-closed upload-preparation checks passed.
- Prior exact mainline evidence remains [run 31662942583](https://github.com/dheeraj5612/filmy-camera/actions/runs/31662942583) on SHA `0067f437fab079c8c09d7436de8eae86c58804e8`.
- Exposure-control PR: [PR #39](https://github.com/dheeraj5612/filmy-camera/pull/39) — merged after green hosted checks; adds bounded ±2 EV compensation, quantized one-third-stop adjustment, full touch targets, VoiceOver adjustment actions, and CI coverage for the required release gate.
- Current mainline evidence GitHub Actions run: [31662479936](https://github.com/dheeraj5612/filmy-camera/actions/runs/31662479936) — green on exact main SHA `d2fdbf7ff480eb309a6ffb1ab5b4ac181de5a454`; Xcode 16.4 generated-project reproducibility, 50 unit/renderer tests, 2 UI tests, release preflight, artifact/log retention, ShellCheck, metadata validation, and the fail-closed upload-preparation lane passed.
- Production-hardening PR: [PR #37](https://github.com/dheeraj5612/filmy-camera/pull/37) — merged after green hosted checks on source SHA `0f8374a5b62a3e8560d22762aa40d0c492a9256a`.
- Previous mainline evidence GitHub Actions run: [31659792102](https://github.com/dheeraj5612/filmy-camera/actions/runs/31659792102) — green on exact main SHA `b5445f070da440280743fc0943c50adcafae60c8` before the exposure-control merge.
- App-code merge GitHub Actions run: [31650506505](https://github.com/dheeraj5612/filmy-camera/actions/runs/31650506505) — green Xcode 16.4 simulator build; the 39 unit/renderer tests and 2 UI tests passed, with generated-project reproducibility, release preflight, artifact/log retention, ShellCheck, metadata validation, and the fail-closed upload-preparation lane.
- Previous `main` evidence GitHub Actions run: [31655106199](https://github.com/dheeraj5612/filmy-camera/actions/runs/31655106199) — historical green run on SHA `e18528a48c381837df697ba35a0caa10c3506b74` before the production-hardening merge.
- Previous mainline evidence run: [31653949298](https://github.com/dheeraj5612/filmy-camera/actions/runs/31653949298) — green on exact SHA `a1da1b7fb7ec9b8d46f04db4d6516924a1517045` before the branded launch-screen update.
- Previous main evidence run: [31650845960](https://github.com/dheeraj5612/filmy-camera/actions/runs/31650845960) — green on exact SHA `0306526e7fc9f323dc159140a0032e7d600e76e4` after the earlier release evidence update.
- Previous mainline baseline: [31647529461](https://github.com/dheeraj5612/filmy-camera/actions/runs/31647529461) — green Xcode 16.4 simulator build before this production-hardening pass.
- Current local simulator verification: 67 unit/renderer tests plus 3 UI tests passed on both iOS 18.5 and iOS 26.5; camera-stop authorization state, onboarding handoff, hardware-selection state, native YUV preview-format selection with BGRA fallback, session-scoped preview/capture grain parity, sRGB export boundary, recipe provenance metadata, gallery zoom gestures with VoiceOver adjustment/reset actions, fail-closed asset ownership/cache path checks, typed toast outcomes, review dismissal guard, gallery/settings UI flow, renderer-backed recipe thumbnails, Tune flow, capture-review handoff, Photos authorization policy, privacy/support links, grouped accessibility semantics, stable 48pt permission actions, Reduce Motion onboarding behavior, and contrast-safe overlays were verified.
- Local release project preflight: `scripts/release/validate-project.sh` passed for bundle `com.dheeraj.filmycamera`, version `1.0.0 (1)`, the privacy manifest, the 1024×1024 icon, and all expected schemes/tests.
- Current local simulator: iPhone 17 Pro, iOS 26.5 — camera shell, recipe editor, Gallery/Settings navigation, accessibility tree, screenshots, and simulator capture fallback verified.
- Historical unsigned archive: `/tmp/filmycamera-rc-20260812-ui-deterministic.xcarchive` — contains dSYM and `PrivacyInfo.xcprivacy`, but predates current main; rebuild and pin a current archive before release use.
- Current product evidence covers Natural Standard, typed camera-session recovery, deterministic UI-test mode, saved recipe/date provenance, original-resource share and owned-asset delete actions in Gallery, removable local-cache controls, in-app privacy/support links, VoiceOver center focus/exposure actions, tactile exposure controls, and release-script fail-closed behavior. The archive validator now fails closed on a missing profile, mismatched team/bundle/version/build, expired profile, enabled `get-task-allow`, missing dSYM/privacy manifest, or non-distribution signature. Signing is only declared in project settings for team `AQW5C8DEEG`; CI remains simulator-only and unsigned, with no signed device archive or App Store submission proven.
- Mainline evidence now includes normalized spatial effect radii across preview and export, an explicit negative-clarity softening path, normalized vignette behavior, renderer-backed synthetic recipe rails, canonical look parity across quality tiers, typed monochrome channel response, hue-aware Color Chrome/FX Blue behavior, deterministic grain, explicit photo dimensions, capture provenance, filtered JPEG metadata, shared preview/still aspect-fill framing, and a fail-closed render path. The exact merged mainline SHA and hosted run above are green; signed-device and App Store evidence remain open.
- Signing follow-up: [PR #4](https://github.com/dheeraj5612/filmy-camera/pull/4) and [PR #5](https://github.com/dheeraj5612/filmy-camera/pull/5) merged with green simulator/XCTest checks.
- Physical QA and App Store Connect submission remain open until device and Apple account access are available.
