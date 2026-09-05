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
- **19 portable runner tests passed.** Routine CI selects 201 app tests (180 core, 18 simulator UI, three Photos E2E), compiles once, and reuses products. Hardware-only and benchmark lanes remain opt-in.

The first device attempt timed out while enabling UI automation. Relaunching the app recovered the next run. That run's strict summary initially reported a count mismatch: the source inventory selected two simulator-only declarations absent from the device bundle. The explicit `simulator-e2e` group now retains those cases in simulator CI and excludes them from hardware; the completeness check remains strict. The original result and its failed count summary are preserved as evidence rather than rewritten.

Landscape attachments now capture the complete `XCUIScreen`; `app.screenshot()` on the local XCTest version produced a cropped landscape image. Review E2E assertions also wait for landscape geometry and require the controls to fit inside the app frame. The extended physical capture test passed at 05:57 EDT after the device became available: real capture → Original comparison → Fine Monochrome selection → landscape controls → saving the chosen look while Original is visible. Its result is `device-review-final.xcresult` (one passed, zero failures/skips), with local complete-screen attachments.

The final three-case Photos E2E rerun passed with the stronger bounds assertions and complete-screen attachments. The landscape screenshot was visually inspected: the entire photo, look/Original controls, and both actions fit in the two-column review. Final evidence is `photos-final/FilmyCameraPhotosE2E.xcresult`, with build-input digest `68d3a74939f6beb7e78e9463a07e21a710489a22cd773144dafef2a204805486`.

Physical screenshot inspection found the look name truncated in the narrower 11-inch landscape panel. Stacking the chooser and Original control fixes this; the strengthened physical capture case passed again in `device-review-layout.xcresult`, and its screenshot shows the full look name and reachable actions. The normal app was relaunched afterward. The captured scene is nearly black, so these captures establish interaction and export behavior, not useful exposure or camera image quality; a well-lit scene is still needed to distinguish obstruction/lighting from a camera-path issue.

All three normal Photos E2E cases passed again after this layout correction, with zero failures/skips (`photos-layout/FilmyCameraPhotosE2E.xcresult`, build-input digest `525d363d4441b9195753b2ceeea0a51204d8d0b151181756ea5b453729a09197`). The image pipeline is unchanged from the 180-test core pass; the final CI run also exercises that suite on the committed source.

Local evidence is under ignored `build/review-editing-20260905/`: `final-core/FilmyCameraUnit.xcresult`, `photos-v2/FilmyCameraPhotosE2E.xcresult`, and `device-v2/FilmyCameraDevice.xcresult`. Their build-input digest is `9f031ae70aa4e9aaa23413f9713591ea495a61dc56d965b29c1e72a5df89061a`. Later changes strengthen UI assertions/screenshots and fix runner routing; production rendering/UI code is unchanged. The updated signed test build also passed (`device-final-build.log`). Photographs, screenshots, and device diagnostics remain local.

This validates the implemented review behavior, not comparative camera fidelity or launch readiness. Sustained frame pacing, thermal/memory pressure, iPhone-specific lens coverage, controlled G7 X/Fuji reference comparisons, and App Store delivery remain separate release gates. Source retention lasts for the current review; this change does not introduce RAW capture or editing saved Roll originals.

The configured public support and privacy-policy pages returned HTTP 200 with the expected Filmy content on September 5. They are hosted separately and were not redeployed by this change.
