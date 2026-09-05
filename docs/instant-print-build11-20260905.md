# Build 11: free launch and Instant Print

Version 1.0.0 (11) adds an optional Instant Print finish to capture/import review. Every currently implemented recipe and camera control remains free. This version contains no subscription, trial, paywall, or export watermark. Future RAW, HDR, focus peaking, and persistent editing work remains roadmap scope.

## Output and review behavior

Instant Print adds opaque warm-white paper around the finished photo, with a larger bottom margin. It adds no background scene, caption, or watermark. The compositor translates source pixels at 1:1 scale; it does not crop or resample the photo. The side/top margin is 3.5% of the short edge and the bottom is 12%, rounded up to whole pixels.

Composition happens after recipe rendering and before the existing single JPEG encode at quality 0.95. Look changes start from the retained source. Review previews remain bounded to 1800 pixels on their longest edge; Save renders the full output. The ordinary-photo path returns the original Core Image object without imposing new limits.

Preview eligibility checks native export dimensions from ImageIO metadata. Instant Print accepts up to 64 MP of source pixels and 80 MP including paper; existing library imports retain their separate 40 MP limit. An 8000×6000 source fits the geometry budget without resizing. That geometry check does not establish peak-memory behavior of a 48 MP capture on hardware.

Recipe and finish are tracked together through pending changes, preview publication, cached full exports, and exact-byte save retries. Original comparison shows the unframed source without changing the selected export. Returning to Photo removes the border before saving.

## Validation evidence

Local evidence is under `build/instant-print-20260905/` (ignored):

- `ci-final/`: 197 unit/integration and 19 UI tests passed without skips. Its subsequent Photos phase exposed a finish-button accessibility identifier collision, fixed by making the picker contain its children.
- `photos-final/`: all three normal Photos E2Es passed after the identifier fix. These cover border switching, preserving the finish across look changes, Original comparison, save, relaunch, Roll/detail, and cancel without a saved frame.
- `store-ipad-release/`: the one iPad store-media flow passed with zero failures/skips and produced five visually inspected 2064×2752 screenshots. The pack includes G7 X, Muted Color, Fine Monochrome, the populated Roll, and photo detail with Instant Print.
- Visual inspection exposed a cramped landscape review. Compact-height review now uses a fitted photo beside controls, with scrollable actions at accessibility text sizes. Both normal-size landscape and maximum accessibility-text controls passed in the subsequent Photos runs. The final native menu scroll helper passed its focused review/save/relaunch test in `review-menu-final/` (one pass, zero failures/skips, iOS 18.5, build-input digest `aac09e083fa709e651413f14fbcb1f6b85bef49511a50b8d436d794f94064113`). The prior `photos-release-verified/` run passed the maximum-text cancel and save/relaunch cases. Hosted CI remains the complete gate for the final commit.
- Four compositor tests check geometry, exact source-pixel preservation, paper/alpha behavior, identity for ordinary photos, and invalid/native-size budgets. Review tests cover export cache separation, pending customized recipes, failed rendering, frozen saves, and exact retry bytes.
- The 26 portable test-runner tests passed. CI continues to share build products, cancel superseded runs, skip unrelated scopes, and retain large result bundles only for failures. Photos E2Es use one seeded simulator and three separate XCTest invocations without retrying cases. Per-case evidence is merged, and CI uploads the merged bundle without duplicate photo attachments; if merging fails it keeps the original bundles. Portable fixtures verified merged, failed-merge, and no-result artifact selection.
- `store-iphone/`: the real import/save/Roll flow passed and produced five inspected screenshots, including a monochrome Instant Print. Its source digest is recorded in the screenshot pack README; subsequent compact-landscape changes leave that portrait presentation unchanged.

## External and physical state

App Store Connect confirms build 10 processed successfully and is Ready to Submit. It is superseded by build 11. The saved distribution draft still references build 5 and retains manual release. Promotional text, description, and App Review notes now describe the free feature set and Instant Print. Download pricing is zero in all 175 configured storefronts. The public support and privacy pages returned HTTP 200 and match the local, no-account app behavior.

An earlier signed build 11 was installed on the iPad. Its UI runner timed out while enabling automation, before any feature assertions ran. The latest full device restart was requested through the public device CLI; fresh capture/print/save acceptance requires the device to reconnect and be unlocked. The iPhone lens attempt stopped during destination preparation and did not run its hardware assertions. Neither is counted as a passing physical test.

Both build 11 media packs were uploaded, ordered 01 through 05, and verified after reloading the saved App Store Connect listing; `asc-build11-media-saved.txt` records the readback. Build selection still requires the new upload.

Physical iPhone 16 Pro diagnostics (`iphone-manual-diagnostic.xcresult`) passed with no skips: Auto requested, resolved, and encoded 8064×6048 pixels; three manual exposures resolved and encoded 4032×3024 pixels with the requested ISO 100/200 and shutter 1/125 and 1/60 in EXIF. Sensor white balance/focus, retained manual state across stop/start, front/back switching, rapid Reset Auto, and remembered flash support passed. Apple documents that 48 MP processed capture requires balanced/quality prioritization; speed prioritization preserves custom sensor exposure. The test now verifies encoded dimensions against Apple’s resolved dimensions, not the requested maximum. Production capture policy is unchanged. See [Apple high-resolution capture](https://developer.apple.com/videos/play/wwdc2026/304/).

An earlier combined lens/manual run had an additional session-reuse timeout. It is preserved; the same-order diagnostic follow-up stopped before execution because the phone locked. Telephoto acceptance remains inconclusive for the observed scene. The physical Print flow reached capture, border switching, and Original comparison, but stopped at a test menu-scroll issue before saving; it is not a full physical acceptance pass.

The final archive, Apple upload/processing, matching build selection, and App Review submission remain separate release gates in [release-checklist.md](release-checklist.md).
