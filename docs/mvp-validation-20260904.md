# MVP validation — September 4, 2026

Candidate: version 1.0.0, build 5, branch `codex/mvp-launch-sweep-20260904`. This record distinguishes the app installed on test hardware from the version available through Apple. Local result bundles and photos stay under ignored `build/mvp-20260904/`; no private photographic fixtures are included in the project or release.

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

Hardware screenshots show a stationary indoor fabric/wallet scene. They establish capture and visible controls, but are unsuitable as final store artwork or a controlled portrait/color comparison. The G7X flash review explicitly reports flash fired. Saved source byte/metadata readback and further physical performance checks are recorded below as they complete.

## Live distribution readback

App Store Connect was inspected in an authenticated browser on September 4. Version 1.0 is Developer Rejected with build 3 selected. Builds 1 through 4 have completed processing; build 4 is Ready to Submit and was uploaded August 25. Build 5 was not present at this readback. The five existing iPhone screenshots depict historical UI and require replacement. Review-contact phone/email were blank. The public App Store URL for app ID 6801404866 returned HTTP 404.

These observations supersede older checklist statements that describe a build as current. An installed development build, an uploaded TestFlight build, and a public App Store release are separate states.

## Remaining launch acceptance

- Complete final-source physical regression and device performance readback; investigate the SwiftUI publication warning seen in the first hardware result.
- Verify iPhone hardware-specific lens/flash behavior. The paired iPhone was locked during initial checks; the connected iPad cannot establish 5x telephoto switching.
- Replace historical screenshots with approved current physical camera/review/populated-Roll images. Do not present simulator placeholders or private fixture photos as launch media.
- Complete signed archive/IPA validation, exact-commit CI, upload processing, build selection and final Apple review requirements.
- Establish controlled same-scene G7X/flag7x/vendor references before claiming superior or camera-exact image quality. Current G7X live preview deliberately omits still-photo subject analysis; capture and import use matching detected subject context.
