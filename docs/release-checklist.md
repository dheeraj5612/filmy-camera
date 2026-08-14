# Filmy Camera release checklist

## Current workspace gate

- [x] Current hardening branch is `codex/security-hardening-20260813`; the exact source revision for any release artifact is recorded in `FilmyCamera.source-sha` and must equal the checked-out branch HEAD.
- [x] Reconcile the App Store signing configuration across `project.yml`, `FilmyCamera.xcodeproj/project.pbxproj`, `scripts/release/prepare-upload.sh`, `scripts/release/validate-archive.sh`, and `scripts/release/validate-project.sh` for Developer team `6ALSCF5GBV`.
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

- [x] Run `xcodegen generate` and verify generated-project reproducibility after reconciling the signing-team update.
- [x] Run the credential-free release project preflight (`scripts/release/validate-project.sh`) against team `6ALSCF5GBV`.
- [x] Compile the current source with `xcodebuild build-for-testing` on the available `FilmyCamera iPhone` iOS 18.5 simulator; full local runtime execution remains environment-blocked while the Mac is locked.
- [x] Hosted hardening run [31788694032](https://github.com/dheeraj5612/filmy-camera/actions/runs/31788694032) passed on exact branch HEAD `9af4c07b9d74619cf4c59f7c81881fd12f48816e`; `change-scope`, `release-scripts`, unit tests, UI tests, artifact provenance, and cleanup all passed on Xcode 16.4.
- [x] Keep release-script syntax, ShellCheck, and fail-closed upload-preparation checks in CI.
- [x] Run a signed Release archive for a generic iOS device destination and validate the app bundle with the Apple Distribution certificate and App Store profile `Filmy Camera App Store 1.0.0`; generated archives use `build/FilmyCamera-<source-sha>-signed.xcarchive` and are restamped after every checkout change.
- [x] Export and independently validate a distribution IPA from the latest exact-head archive; generated exports use `build/export-<source-sha>/FilmyCamera.ipa` and their SHA-256 is recorded at export time.
- [x] Validate `Info.plist`, launch behavior, app icon, version `1.0.0`, and build number `1`.
- [ ] Run App Store Connect upload validation and retain the archive plus dSYM/ symbol artifacts.
- [x] App Store metadata draft prepared.
- [ ] Finalize App Store Connect metadata decisions: pricing, availability, screenshots, legal copy, and support contact.
- [x] App Privacy answer matrix reviewed against the source tree in `docs/app-store/app-privacy.md`; entering the answers in App Store Connect remains an account-owner step.
- [ ] Produce required device screenshots and an optional preview video.
- [x] Confirm the privacy policy, public support URL, and marketing URL are live.

## App Store Connect and Apple requirements

- [ ] Enroll in the Apple Developer Program and accept current agreements.
- [x] Create the App Store Connect app record with bundle ID `com.dheeraj.filmycamera` (Apple ID `6801404866`).
- [x] Register/verify the bundle identifier in the Apple Developer portal.
- [x] Configure the local Apple Distribution certificate and App Store provisioning profile for device archives; CI remains simulator-only and does not receive signing material.
- [ ] Create an App Store Connect API key or use an authenticated Xcode/Transporter account for upload.
- [ ] Complete App Privacy publication, pricing, availability, and tax/banking setup; age rating and export-compliance answers are saved.
- [ ] Supply/verify the final support contact; privacy, support, and marketing URLs are saved in the App Store record.
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
# When an IPA has already been exported:
scripts/release/validate-ipa.sh --ipa build/export-<source-sha>/FilmyCamera.ipa \
  --archive build/FilmyCamera-<source-sha>-signed.xcarchive
```

The archive wrapper requires a clean checkout, generates the project, refuses a pre-existing destination, and creates a Release archive for a generic iOS device stamped with the exact source SHA. The upload-preparation wrapper is read-only by default, validates the archive provenance and local signing material before export, requires explicit `--export` or `--upload` modes, and keeps App Store Connect keys outside the repository. The standalone IPA validator independently checks an exported IPA against its exact validated archive, including bundle/version/build parity, App Store provisioning, distribution signing, dSYM/privacy-manifest presence, and source provenance. These gates never store credentials in the repository or CI logs.

For headless provisioning, `archive-device.sh --allow-provisioning-updates` accepts the same `FILMY_ASC_KEY_ID`, `FILMY_ASC_ISSUER_ID`, and `FILMY_ASC_KEY_PATH` environment variables as the upload wrapper. Partial credentials and repository-local key paths are rejected before Xcode runs.

The hosted workflow keeps the release-script gate on metadata and checklist changes, while the simulator build lane runs only when binary-affecting files change. Unknown or manually dispatched scopes fail open so required validation is never silently skipped.

## Verified evidence

- Current repository evidence: branch `codex/security-hardening-20260813` contains the camera-shell UI revamp, typed Color Chrome/FX Blue/Grain controls, canonical public film vocabulary, Dynamic Range and D Range Priority modes, named white-balance modes, persisted Kelvin color temperature, monochromatic color axes, Sepia coverage, capture identity hardening, accessibility coverage, Xcode 16.4 compatibility, interactive zoom presets, tab-aware camera lifecycle, transactional recipe editing, and team-aligned release configuration.
- Current hosted evidence: [run 31788694032](https://github.com/dheeraj5612/filmy-camera/actions/runs/31788694032) passed on exact source revision `9af4c07b9d74619cf4c59f7c81881fd12f48816e`; [PR #55](https://github.com/dheeraj5612/filmy-camera/pull/55) remains open and draft.
- Current local simulator evidence: 97 unit tests and 6 UI tests pass on the iPhone 17 Pro iOS 26.5 simulator for the current source; hosted Xcode 16.4 execution independently covers the current-head camera shell, recipe details, Gallery, Settings navigation, simulator fallback, typed Color Chrome/FX Blue/Grain editing, Dynamic Range/D Range Priority, named white balance, monochromatic axes, Sepia recipe coverage, status accessibility, Reduce Motion gallery reset, and renderer parity. The sixth UI test exercises the physical viewfinder-first chrome through the `-ui-testing-viewfinder-chrome` design-preview flag and verifies that simulator capture remains disabled.
- Current signed device archive: the latest generated `build/FilmyCamera-<source-sha>-signed.xcarchive` contains the app, dSYM, privacy manifest, version `1.0.0`, embedded App Store provisioning profile, and a `FilmyCamera.source-sha` marker matching the exact source revision used for the build. Archive validation passes with Apple Distribution identity `Apple Distribution: DHEERAJ SRINIVASA NAMBURU (6ALSCF5GBV)`. A matching IPA was exported and independently verified; upload remains pending final metadata and authenticated App Store Connect access.
- Current UI hardening: the recipe-detail hero no longer duplicates the swatch label; recipe-editor section icons participate in layout; simulator fallback hides the unavailable live-preview accessibility target; Photos permission badges remain readable at narrow widths; and the 2026-08-13 revamp adds floating navigation, ambient page surfaces, a film-stock header, pinned quick controls, and bounded Dynamic Type chrome. The current revamp adds a viewfinder-first physical-camera hierarchy, an explicit controls reveal, a compact current-look menu, a shutter-dominant action plate, progressive More controls, a labeled Current Look recipe shelf, edge fades/browse cue, a stronger capture-review hero, and a prominent Keep Frame action. The modern darkroom/amber camera shell, recipe rail, accessibility labels, and touch-target work remain covered by the simulator gate.
- Current security/release hardening: CI checkout credentials are not persisted; ShellCheck and XcodeGen are pinned and verified; the credential scan covers tracked files; local photo-cache orphan cleanup is reconciled; exported JPEG metadata uses an explicit privacy-safe allowlist; archive project generation is reproducibility-checked; App Store profiles are team-validated and reject development-device entitlements; and late photo callbacks cannot consume newer capture state.
- Pre-PR #55 mainline: `27dbd3a353c6171aa9a33c95acf92f97fc955555`.
- Historical hardening commits: `fb51d6879a10146837ea3212ac698049eefed8fa` (headless release credential checks), `47c93dce619bcc031b89d2802fa91013c1c49c00` (CI workflow), `f6799ab9fbcb87b9b28c4d9569e4a13de27b7cfd` (Photos ownership/cache safety), and `1662f833f8909e1dd535a05075282ea230b1202b` (camera/review error states).
- Historical app-code evidence: [run 31720714081](https://github.com/dheeraj5612/filmy-camera/actions/runs/31720714081) — green on the pre-hardening SHA `255008fd82e0a3d8d834e256638f827a19390904`; Xcode 16.4 generated-project reproducibility, 65 unit/renderer tests, 3 UI tests, release preflight, artifact retention, ShellCheck, metadata validation, and fail-closed upload-preparation checks passed.
- Previous full iOS evidence: [run 31671146304](https://github.com/dheeraj5612/filmy-camera/actions/runs/31671146304) — green on exact code SHA `3ae90dd64e37d31e9ee6c1d84d223eec2fc3070a`; Xcode 16.4 generated-project reproducibility, 61 unit/renderer tests, 2 UI tests, release preflight, artifact retention, ShellCheck, metadata validation, and fail-closed upload-preparation checks passed.
- Prior exact mainline evidence remains [run 31662942583](https://github.com/dheeraj5612/filmy-camera/actions/runs/31662942583) on SHA `0067f437fab079c8c09d7436de8eae86c58804e8`.
- Exposure-control PR: [PR #39](https://github.com/dheeraj5612/filmy-camera/pull/39) — merged after green hosted checks; adds bounded ±2 EV compensation, quantized one-third-stop adjustment, full touch targets, VoiceOver adjustment actions, and CI coverage for the required release gate.
- Historical mainline evidence GitHub Actions run: [31662479936](https://github.com/dheeraj5612/filmy-camera/actions/runs/31662479936) — green on exact main SHA `d2fdbf7ff480eb309a6ffb1ab5b4ac181de5a454`; Xcode 16.4 generated-project reproducibility, 50 unit/renderer tests, 2 UI tests, release preflight, artifact/log retention, ShellCheck, metadata validation, and the fail-closed upload-preparation lane passed.
- Production-hardening PR: [PR #37](https://github.com/dheeraj5612/filmy-camera/pull/37) — merged after green hosted checks on source SHA `0f8374a5b62a3e8560d22762aa40d0c492a9256a`.
- Previous mainline evidence GitHub Actions run: [31659792102](https://github.com/dheeraj5612/filmy-camera/actions/runs/31659792102) — green on exact main SHA `b5445f070da440280743fc0943c50adcafae60c8` before the exposure-control merge.
- App-code merge GitHub Actions run: [31650506505](https://github.com/dheeraj5612/filmy-camera/actions/runs/31650506505) — green Xcode 16.4 simulator build; the 39 unit/renderer tests and 2 UI tests passed, with generated-project reproducibility, release preflight, artifact/log retention, ShellCheck, metadata validation, and the fail-closed upload-preparation lane.
- Previous `main` evidence GitHub Actions run: [31655106199](https://github.com/dheeraj5612/filmy-camera/actions/runs/31655106199) — historical green run on SHA `e18528a48c381837df697ba35a0caa10c3506b74` before the production-hardening merge.
- Previous mainline evidence run: [31653949298](https://github.com/dheeraj5612/filmy-camera/actions/runs/31653949298) — green on exact SHA `a1da1b7fb7ec9b8d46f04db4d6516924a1517045` before the branded launch-screen update.
- Previous main evidence run: [31650845960](https://github.com/dheeraj5612/filmy-camera/actions/runs/31650845960) — green on exact SHA `0306526e7fc9f323dc159140a0032e7d600e76e4` after the earlier release evidence update.
- Previous mainline baseline: [31647529461](https://github.com/dheeraj5612/filmy-camera/actions/runs/31647529461) — green Xcode 16.4 simulator build before this production-hardening pass.
- Historical local simulator verification: 67 unit/renderer tests plus 3 UI tests passed on both iOS 18.5 and iOS 26.5; camera-stop authorization state, onboarding handoff, hardware-selection state, native YUV preview-format selection with BGRA fallback, session-scoped preview/capture grain parity, sRGB export boundary, recipe provenance metadata, gallery zoom gestures with VoiceOver adjustment/reset actions, fail-closed asset ownership/cache path checks, typed toast outcomes, review dismissal guard, gallery/settings UI flow, renderer-backed recipe thumbnails, Tune flow, capture-review handoff, Photos authorization policy, privacy/support links, grouped accessibility semantics, stable 48pt permission actions, Reduce Motion onboarding behavior, and contrast-safe overlays were verified.
- Local release project preflight: `scripts/release/validate-project.sh` passed for bundle `com.dheeraj.filmycamera`, version `1.0.0 (1)`, the privacy manifest, the 1024×1024 icon, and all expected schemes/tests.
- Current local simulator: `FilmyCamera iPhone`, iOS 18.5 — current source compiles with `xcodebuild build-for-testing`; runtime execution is covered by hosted Xcode 16.4 simulator tests while local interactive verification awaits an unlocked Mac.
- Historical unsigned archive: `/tmp/filmycamera-rc-20260812-ui-deterministic.xcarchive` — contains dSYM and `PrivacyInfo.xcprivacy`, but predates current main; rebuild and pin a current archive before release use.
- Current product evidence covers Natural Standard, typed camera-session recovery, deterministic UI-test mode, saved recipe/date provenance, original-resource share and owned-asset delete actions in Gallery, removable local-cache controls, in-app privacy/support links, VoiceOver center focus/exposure actions, tactile exposure controls, and release-script fail-closed behavior. The archive validator now fails closed on a missing profile, mismatched team/bundle/version/build, expired profile, enabled `get-task-allow`, development-device entitlements, missing dSYM/privacy manifest, or non-distribution signature. Signing is declared in the project settings for team `6ALSCF5GBV`; App Store submission remains unproven.
- Mainline evidence now includes normalized spatial effect radii across preview and export, an explicit negative-clarity softening path, normalized vignette behavior, renderer-backed synthetic recipe rails, canonical look parity across quality tiers, typed monochrome channel response, hue-aware Color Chrome/FX Blue behavior, deterministic grain, explicit photo dimensions, capture provenance, filtered JPEG metadata, shared preview/still aspect-fill framing, and a fail-closed render path. The current PR-head SHA and hosted run above are green, but PR #55 is not merged into `main`; signed-device and App Store evidence remain open.
- Signing follow-up: [PR #4](https://github.com/dheeraj5612/filmy-camera/pull/4) and [PR #5](https://github.com/dheeraj5612/filmy-camera/pull/5) merged with green simulator/XCTest checks.
- Physical QA and App Store Connect submission remain open until the Mac is unlocked, a physical iPhone is connected and trusted, final price/availability and privacy publication are confirmed, and an authorized upload session or ASC API credentials are available. The current local `scripts/release/prepare-upload.sh --check` passes project/profile/archive validation and fails closed only on draft metadata plus missing ASC API credentials; no authenticated upload was attempted. A local IPA export was prepared separately from the validated archive so the binary artifact is ready when the account gate is cleared.
