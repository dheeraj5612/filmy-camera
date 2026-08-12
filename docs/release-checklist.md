# Filmy Camera release checklist

## Current workspace gate

- [x] Verify the production Swift app target is present under `FilmyCamera/`.
- [x] Exercise the production `FilmRecipe.builtIns` and `FilmRenderer.render` APIs from XCTest.
- [x] Confirm the generated Xcode project exposes the `FilmyCamera` scheme, unit tests, and UI tests.
- [x] Verify the simulator camera shell, editable recipe controls, accessibility labels, and empty-state recovery surface.

## Product and device QA

- [ ] Test camera permission denial, recovery, and first-run messaging on a physical iPhone.
- [ ] Test photo-library permission denial, limited access, save, and recent-photo behavior.
- [ ] Verify preview and saved output use the same selected recipe, including the capture-review handoff.
- [ ] Verify output bounds, orientation, image dimensions, metadata, and memory use with representative photos.
- [ ] Test every bundled recipe in bright daylight, low light, skin tones, sky, and mixed lighting.
- [ ] Test interruption/resume for phone calls, backgrounding, camera unavailable, and low storage.
- [ ] Verify VoiceOver labels, Dynamic Type, contrast, hit targets, and Reduce Motion behavior.
- [ ] Confirm the app never claims affiliation with or ships proprietary Fujifilm data.

## Build and release artifacts

- [x] Run `xcodegen generate` from a clean checkout.
- [x] Run the credential-free release project preflight (`scripts/release/validate-project.sh`).
- [x] Run the iPhone Simulator build and XCTest workflow in `.github/workflows/ios-build.yml` (9 unit/renderer tests plus 2 UI tests).
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
```

The wrapper generates the project, creates a Release archive for a generic iOS device, and fails closed unless the archive has the expected bundle/version, distribution signature, provisioning profile, dSYM, and privacy manifest. It does not upload or store credentials.

## Verified evidence

- Last verified main baseline: `9315ea8cd77d65681434abd80e49ce3e07b862bd`
- GitHub Actions run: [31609484402](https://github.com/dheeraj5612/filmy-camera/actions/runs/31609484402) — green Xcode 16.4 simulator build; 9 unit/renderer tests plus 2 UI tests (11 total) passed.
- Local release project preflight: `scripts/release/validate-project.sh` passed for bundle `com.dheeraj.filmycamera`, version `1.0.0 (1)`, the privacy manifest, the 1024×1024 icon, and all expected schemes/tests.
- Local simulator: iPhone 17, iOS 26.5 — camera shell, recipe editor, Gallery/Settings navigation, accessibility tree, screenshots, and simulator capture fallback verified.
- Historical unsigned archive: `/tmp/filmycamera-rc-20260812-ui-deterministic.xcarchive` — contains dSYM and `PrivacyInfo.xcprivacy`, but predates current main; rebuild and pin a current archive before release use.
- Current product evidence covers Provia Standard, camera-session recovery, and deterministic UI-test mode. The archive validator now fails closed on a missing profile, mismatched team/bundle, enabled `get-task-allow`, missing dSYM/privacy manifest, or non-distribution signature. Signing is only declared in project settings for team `AQW5C8DEEG`; CI remains simulator-only and unsigned, with no signed device archive or App Store submission proven.
- Signing follow-up: [PR #4](https://github.com/dheeraj5612/filmy-camera/pull/4) and [PR #5](https://github.com/dheeraj5612/filmy-camera/pull/5) merged with green simulator/XCTest checks.
- Physical QA and App Store Connect submission remain open until device and Apple account access are available.
