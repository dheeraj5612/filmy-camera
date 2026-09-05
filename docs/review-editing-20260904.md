# Reversible photo review

## Product intent

A captured moment should remain available while the photographer tries G7 X, color film, and monochrome looks. The review should make the difference visible and save exactly the chosen treatment. This is the next focused improvement toward the camera's quality target; it does not establish superiority over other camera apps or replace physical-device acceptance.

The interaction takes inspiration from post-capture look selection in [Halide Photo Lab](https://www.lux.camera/halide-mark-iii/), while retaining Filmy's existing shooting controls and G7 X/Fuji-inspired collection.

## Acceptance contract

- Changing the review look uses the same compressed source and capture context. The camera's selected look for the next shot is independent.
- The previous valid image remains visible while a replacement renders. A newer selection supersedes older pending work; discarded reviews cannot reappear.
- Audition previews are bounded to 1800 pixels on their longest edge. Only one review render runs at a time. A changed look receives a full-resolution export when Save is pressed, using the existing capture/import resolution policy.
- Original comparison shows the source photo without Filmy's treatment, with the same orientation and framing. It is an on-demand preview, not a RAW file or a different save mode.
- Image, recipe, and saved metadata agree. Save freezes editing until the export and Photos write finish. Photos failures retain the finished bytes for an exact retry.
- Controls remain usable with large text and in iPad portrait/landscape. Comparison has an explicit accessible control and visible state.

## Validation

September 5 local validation used Xcode 26.6 (17F113), an iPad Pro 13-inch simulator on iOS 26.5, and the connected iPad Pro 11-inch (2nd generation) on iPadOS 26.6.1. Development app version 1.0.0 (8) was signed, installed, and exercised on the physical iPad.

- **180 unit/integration tests passed**, with no failures or skips. Seven new review cases cover deferred full exports, source comparison, latest-selection wins, cancellation and stale results, exact save retry, original camera crop/orientation/flash/date/subject mapping, maximum-grain output parity, and reuse when returning to the cached look.
- **Three real Photos E2E tests passed**, with no failures or skips: G7 X import/save/relaunch/Roll detail; largest accessibility text with cancellation preserving Roll count; and Original comparison, monochrome selection, landscape controls, and saving the selected treatment while Original is visible. Each test selects the same public source fixture, skipping newer outputs from preceding cases.
- **All 23 applicable physical tests passed**: two hardware flash tests and 21 UI tests. This covers fresh Metal preview revisions, capture/Retake, import/save, G7 X flash review, save/Roll/detail/zoom/share cancellation, recipe editing, navigation, large text, portrait/landscape, and lifecycle recovery. Test photos remain on the device; share sheets were cancelled.
- **20 portable runner tests passed.** Routine CI selects 201 app tests (180 core, 18 simulator UI, three Photos E2E), compiles once, and reuses products. Hardware-only and benchmark lanes remain opt-in.

The first device attempt timed out while enabling UI automation. Relaunching the app recovered the next run. That run's strict summary initially reported a count mismatch: the source inventory selected two simulator-only declarations absent from the device bundle. The explicit `simulator-e2e` group now retains those cases in simulator CI and excludes them from hardware; the completeness check remains strict. The original result and its failed count summary are preserved as evidence rather than rewritten.

Landscape attachments now capture the complete `XCUIScreen`; `app.screenshot()` on the local XCTest version produced a cropped landscape image. Review E2E assertions also wait for landscape geometry and require the controls to fit inside the app frame. The extended physical capture test passed at 05:57 EDT after the device became available: real capture → Original comparison → Fine Monochrome selection → landscape controls → saving the chosen look while Original is visible. Its result is `device-review-final.xcresult` (one passed, zero failures/skips), with local complete-screen attachments.

The final three-case Photos E2E rerun passed with the stronger bounds assertions and complete-screen attachments. The landscape screenshot was visually inspected: the entire photo, look/Original controls, and both actions fit in the two-column review. Final evidence is `photos-final/FilmyCameraPhotosE2E.xcresult`, with build-input digest `68d3a74939f6beb7e78e9463a07e21a710489a22cd773144dafef2a204805486`.

Physical screenshot inspection found the look name truncated in the narrower 11-inch landscape panel. Stacking the chooser and Original control fixes this; the strengthened physical capture case passed again in `device-review-layout.xcresult`, and its screenshot shows the full look name and reachable actions. The normal app was relaunched afterward. The captured scene is nearly black, so these captures establish interaction and export behavior, not useful exposure or camera image quality; a well-lit scene is still needed to distinguish obstruction/lighting from a camera-path issue.

All three normal Photos E2E cases passed again after this layout correction, with zero failures/skips (`photos-layout/FilmyCameraPhotosE2E.xcresult`, build-input digest `525d363d4441b9195753b2ceeea0a51204d8d0b151181756ea5b453729a09197`). The image pipeline is unchanged from the 180-test core pass; the final CI run also exercises that suite on the committed source.

Local evidence is under ignored `build/review-editing-20260905/`: `final-core/FilmyCameraUnit.xcresult`, `photos-v2/FilmyCameraPhotosE2E.xcresult`, and `device-v2/FilmyCameraDevice.xcresult`. Their build-input digest is `9f031ae70aa4e9aaa23413f9713591ea495a61dc56d965b29c1e72a5df89061a`. Later changes strengthen UI assertions/screenshots, fix runner routing, and stack the iPad landscape controls; production rendering code is unchanged. The updated signed test build also passed (`device-final-build.log`). Physical photographs, screenshots, and device diagnostics remain local; the separate App Store pack uses only the public fixture.

This validates the implemented review behavior, not comparative camera fidelity or launch readiness. Sustained frame pacing, thermal/memory pressure, iPhone-specific lens coverage, controlled G7 X/Fuji reference comparisons, and App Store delivery remain separate release gates. Source retention lasts for the current review; this change does not introduce RAW capture or editing saved Roll originals.

The configured public support and privacy-policy pages returned HTTP 200 with the expected Filmy content on September 5. They are hosted separately and were not redeployed by this change.

## Cross-version test and media corrections

GitHub run `33959819984` passed all 180 core and 18 UI tests on iOS 18.5, then failed one of three Photos E2Es because the phone's three-page native menu had not materialized its offscreen monochrome option. The test now scrolls that menu with a bounded gesture until the exact option is present and hittable. All three Photos E2Es passed on a fresh local iPhone 16 Pro simulator running iOS 18.5 (`photos-fixed18/FilmyCameraPhotosE2E.xcresult`). The selected-look, Original, save, and relaunch assertions remain intact.

Store-media capture on previously used test libraries selected earlier monochrome output instead of the public source. Reseeding preserved the original's older Photos date and did not move it ahead of saved frames. The resulting review and saved JPEG agreed; this was fixture contamination, not evidence of a renderer mismatch. The media runner now creates/seeds its own fresh simulator, forces zero prior saves, and removes only that owned simulator afterward. Portable tests cover the environment and cleanup boundaries. The contaminated images are retained as local diagnosis evidence and must not be published. Fresh iPhone 11 Pro Max and iPad Pro 13-inch (M5) runs on iOS 26.5 each passed the store-media flow with zero failures/skips. All ten replacement images were inspected: the same public cafe source has three distinct treatments, and each Roll contains exactly their three matching outputs. The tracked build 8 packs replace build 7 locally; Apple upload remains pending. Fresh evidence is under `build/store-media-build8-fresh-20260905/{iphone,ipad}/`, with build-input digest `85e5c804f1ed8fe195a19812b1b19fe00e4af9a76bb522ec42fffc3adaaf9c41`.

## Physical performance and release preparation

Three existing synthetic renderer benchmarks passed on the A12Z iPad in Debug, with nominal thermal state at the import test start. G7 X preview rendering averaged 15.7 ms at 988×1316 across eight measured iterations after warmup. Its 12 MP import-to-review samples were 403.9, 213.5, and 216.7 ms (216.7 ms median). These are renderer/import measurements, not sustained camera frame pacing or a comparison against another build. Results are in `device-performance.xcresult`.

Clean source `ed72d4f1ec1bb9c1edb305dcdd9b0612f0e771c7` produced a validated distribution archive and matching 1.0.0 (8) IPA: `build/FilmyCamera-ed72d4f-signed.xcarchive` and `build/export-ed72d4f/FilmyCamera.ipa`. IPA size is 4,068,624 bytes; SHA-256 is `e12b6500d256daa87fe89f7f7f968a7704339211901e10d2cfca9c4772535d08`. Later test/media-runner corrections do not change application source. This is local preparation, not an Apple upload; the API uploader has no configured credentials, and App Store Connect browser sign-in remains pending.

## Final build 8 evidence

Clean source `1b68673a75acabd9667897b35b3cce3d456f6ce4` supersedes the earlier archive above. [GitHub run 33961809201](https://github.com/dheeraj5612/filmy-camera/actions/runs/33961809201) passed all 180 core, 18 UI, three Photos E2E, and 20 portable runner checks. There were zero app failures or skips. GitHub tested merge commit `d3a6ea231a9053f0242026dbd7f81f0e87f98bd3`; its build-input digest `85e5c804f1ed8fe195a19812b1b19fe00e4af9a76bb522ec42fffc3adaaf9c41` matches the clean local build. The final paged-menu driver also passed all three Photos E2Es on iPadOS 26.5, without rebuilding unchanged products.

The validated distribution archive is `build/FilmyCamera-1b68673-signed.xcarchive`; its matching 1.0.0 (8) IPA is `build/export-1b68673/FilmyCamera.ipa`, 4,068,626 bytes, SHA-256 `3fede91f3b5df09a7e1c3a76e00f601380cee41074f7edbe9f1aab21328442d3`. Both the archive and independent IPA parity checks passed. The ten current public-fixture screenshots were inspected and committed with this source.

A fresh Xcode account upload attempt exited 70 with `Failed to Use Accounts`; the diagnostic identifies a missing `Xcode-Token` in the saved credentials. Build 8 was not uploaded. Xcode's Apple Accounts page and App Store Connect in Chrome both require sign-in. The live support/privacy pages passed browser inspection and navigation. Apple delivery, lit-scene camera quality, iPhone lens coverage, and sustained thermal/frame-pacing acceptance remain open; prior dark captures and synthetic benchmarks do not establish those outcomes.
