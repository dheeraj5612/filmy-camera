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

- [ ] Run `xcodegen generate` from a clean checkout.
- [ ] Run the iPhone Simulator build and XCTest workflow in `.github/workflows/ios-build.yml`.
- [ ] Run a Release archive on a physical-device destination.
- [ ] Validate `Info.plist`, launch behavior, app icon, version `1.0.0`, and build number `1`.
- [ ] Run App Store Connect upload validation and retain the archive plus dSYM/ symbol artifacts.
- [ ] Complete the App Store metadata draft in `docs/app-store/metadata-en-US.md`.
- [ ] Produce required device screenshots and an optional preview video.
- [ ] Confirm crash reporting, support inbox, privacy policy, and marketing URLs are live.

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
