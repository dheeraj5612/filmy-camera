# Filmy Camera release checklist

## Current workspace gate

- [x] Verify the production Swift app target is present under `FilmyCamera/`.
- [x] Exercise the production `FilmRecipe.builtIns` and `FilmRenderer.render` APIs from XCTest.
- [x] Confirm the generated Xcode project exposes the `FilmyCamera` scheme and `FilmyCameraTests` target.
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
- [x] Run the iPhone Simulator build and XCTest workflow in `.github/workflows/ios-build.yml`.
- [ ] Run a Release archive on a physical-device destination.
- [x] Validate `Info.plist`, launch behavior, app icon, version `1.0.0`, and build number `1`.
- [ ] Run App Store Connect upload validation and retain the archive plus dSYM/ symbol artifacts.
- [x] Complete the App Store metadata draft in `docs/app-store/metadata-en-US.md`.
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

## Verified evidence

- Main release commit: `fe05608715d5a4acd670086f65861b499abee522`
- GitHub Actions run: [31574353149](https://github.com/dheeraj5612/filmy-camera/actions/runs/31574353149) — simulator build and 9 XCTest cases passed.
- Local simulator: iPhone 17, iOS 26.5 — camera shell, recipe editor, accessibility tree, and simulator capture fallback verified.
- Local archive: `/tmp/filmycamera-rc-20260812-v3.xcarchive` — current unsigned validation archive with dSYM and privacy manifest present.
- Current working-tree hardening adds Provia Standard and camera-session interruption/restart recovery; it still needs the next merged CI run.
- Physical QA and App Store Connect submission remain open until device and Apple account access are available.
