# MVP validation — September 4, 2026

Candidate: version 1.0.0, build 5, archived and uploaded from source `d9ef13836fdacea4929dd60cddb32b8eb0afd785`, on branch `codex/mvp-launch-sweep-20260904`. Subsequent changes are limited to test detection and this evidence record; the application source is unchanged. This record distinguishes the app installed on test hardware from the version available through Apple. Local result bundles and photos stay under ignored `build/mvp-20260904/`; no private photographic fixtures are included in the project or release.

## Scope and changes

Astra Ultra reviewed all 19 production Swift files and the complete tracked configuration/resource/release inventory. Sol and Luna implemented bounded camera, renderer/cache, and interface fixes. The existing uncommitted camera redesign was preserved. The [audit](mvp-audit-20260904.md) records source coverage and remaining acceptance limits.

Changes include hardware-scaled zoom ceilings, actual AE/AF restoration, terminal capture-error recovery, import preview suspension, consistent G7X portrait context for capture/import, typed save recovery, asynchronous JPEG caching with encoded dimensions and clear-generation protection, stable thumbnail identity, reduced thumbnail work, bounded gallery gestures, iPad sharing, applicable monochrome controls, contextual camera guidance, busy navigation, and camera idle-timer ownership. Release preparation now removes temporary credential staging on normal/error/signal exits.

## Executed checks

| Evidence | Result | Scope |
| --- | --- | --- |
| `unit-iphone.xcresult` | 161 passed, 3 skipped | Initial simulator unit suite with ten private local photo fixtures; photographic G7X/Fuji/creator sheets visually inspected. |
| `ui-iphone.xcresult` | 15 passed, 2 skipped | Simulator UI/navigation/onboarding, portrait/landscape and large text. Predates final thumbnail/idle/navigation updates. |
| `final-unit-iphone.xcresult` | 158 passed, 6 skipped | Final color-conversion and strict fixture tests compiled; no local fixtures bundled. Three photo-gallery tests, hardware-only checks and opt-in timing account for skips. |
| `ipad-validation.xcresult` | 175 passed, 6 skipped | iPad Pro 11-inch (2nd generation), iPadOS 26.6.1, development-signed build 5. Includes real shutter, G7X flash with flash-fired review, Photos save, import/save, retake, lifecycle, and responsive recipe switches. Predates the final busy-navigation fix. |
| Release cleanup sentinel test | Passed | Normal exit, explicit failure and SIGTERM remove fake key staging. No real credentials used. |
| Public legal/support website | Passed | Landing, privacy, support and terms rendered in browser. GitHub Pages deployment was already live; this sweep did not redeploy it. |

Hardware screenshots show a stationary indoor fabric/wallet scene. They establish capture and visible controls, but are unsuitable as final store artwork or a controlled portrait/color comparison. The G7X flash review explicitly reports flash fired. The saved JPEG readback confirmed both capture and import outputs at 3024 × 4032, orientation 1, Filmy Camera software attribution, recipe provenance and no GPS metadata. Normal-mode testing also reached a populated Roll and verified zoom, pan and reset. The iPad activity controller appeared as a popover rather than an XCTest sheet; the assertion was corrected to identify its visible Copy and Close controls.

## Live distribution readback

App Store Connect was inspected in an authenticated browser on September 4. The initial state was Developer Rejected with build 3 selected. Build 5 subsequently uploaded successfully through Xcode, completed processing and became Ready to Submit. Build 5 was selected and saved; a separate fresh browser tab confirmed the version is now Prepare for Submission with build 5 associated. The five existing iPhone screenshots depict historical UI and require replacement. Review-contact phone/email remained blank. The published privacy disclosure says Data Not Collected; pricing was verified at $0.00 with 175 available regions. Updated description and review notes were saved and read back after reload. The public App Store URL for app ID 6801404866 returned HTTP 404.

These observations supersede older checklist statements that describe a build as current. An installed development build, an uploaded TestFlight build, and a public App Store release are separate states.

## Remaining launch acceptance

- Final regression, device timing and the resolved test-harness issues are recorded below. Sustained thermal behavior and a controlled portrait/color calibration session remain outside this stationary indoor pass.
- Verify iPhone hardware-specific lens/flash behavior. The paired iPhone was locked during initial checks; the connected iPad cannot establish 5x telephoto switching.
- Replace historical screenshots with approved current physical camera/review/populated-Roll images. Do not present simulator placeholders or private fixture photos as launch media.
- Complete final Apple review requirements and submission. The signed archive/IPA, source-commit CI, upload processing and saved build selection are complete; public release is not complete.
- Establish controlled same-scene G7X/flag7x/vendor references before claiming superior or camera-exact image quality. Current G7X live preview deliberately omits still-photo subject analysis; capture and import use matching detected subject context.

## Final-source regression and release evidence

- `committed-unit-iphone.xcresult`: 159 passed, 6 skipped, 0 failed (165 total).
- `final-regression-iphone.xcresult`: 56 passed, 2 skipped, 0 failed, covering camera publication and simulator UI after the final production edits.
- `ipad-final-regression.xcresult`: 176 passed, 2 failed, 5 skipped. The earlier SwiftUI publishing warnings are gone. The only runtime warning is the intentionally direct flash diagnostic in the test harness, not production camera startup. The new Roll test reached the actual share popover but looked for an XCTest sheet. The long capture-sheet run lost its test launch session and reported SIGKILL; available diagnostics contained no crash/Jetsam report proving which process or cause. These failures are retained as evidence rather than rewritten as a passing full-suite run.
- `ipad-focused-acceptance.xcresult`: both focused tests passed, zero skips/failures. The normal G7X flow verified save, populated Roll, pinch/pan/reset, activity-popover presentation and cancellation. The complete 13-recipe flash-off/flash-on pass produced all 26 review images. The earlier test-session termination did not recur; its cause remains unproven.
- `ipad-performance.xcresult`: both opt-in tests passed. Five app launches measured 0.499–0.522 seconds (mean about 0.507 seconds). On Apple A12Z, G7X rendering took 14.2 ms at 834 × 1112, 21.7 ms at 1206 × 1610, and 41.9 ms at 1668 × 2224. Production preview is capped at 1.3 MP. These isolated rendering timings are not a claim of sustained whole-app frame rate.
- [GitHub Actions 33914142237](https://github.com/dheeraj5612/filmy-camera/actions/runs/33914142237) passed all required jobs on source `d9ef138` with hosted Xcode 16.4.
- `build/FilmyCamera-d9ef138-signed.xcarchive` passed distribution signing, source provenance, privacy and matching executable/dSYM architecture UUID checks. `build/export-d9ef138/FilmyCamera.ipa` passed independent IPA/archive parity validation; SHA-256 `7b1c0670c7a9a6120082968c184caa904290c0bce005c6a2afe5dc3b370880db`.
- The first native upload attempt failed because Xcode lacked a saved account token. After the user signed in, the retry succeeded. Apple completed processing build 5, and the fresh version page read back build 5 in Prepare for Submission.

Archive validation is intentionally tied to the recorded source commit. To revalidate this archived build after later test/documentation commits, use a clean checkout of `d9ef138`; do not change or restamp archive provenance.
