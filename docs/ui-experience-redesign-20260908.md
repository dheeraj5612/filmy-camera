# Filmy UI experience redesign

## Product changes

- A quiet ink-and-sage visual system with a pale blue action accent, editorial serif headings, and a restrained Filmy wordmark.
- The camera keeps the existing shutter, flash, zoom, focus, framing, session lifecycle, and explicit save behavior. The current look now has a renderer-backed thumbnail. Larger quick swatches lead to a full visual library instead of requiring long nested-row hunting.
- The shared Looks library has large renderer-backed sample cards, name/descriptor search, All/Favorites/Compact/Film/Monochrome filters, separate heart controls, persistent favorites, selected state, and actionable empty results. Selecting a card applies and dismisses; favoriting never applies. Search/filter changes return to the beginning of the results. Compact landscape and accessibility headers omit nonessential marketing copy instead of shrinking the user's text. Accessibility sizes use a single column, shorter images, and fixed-size heart symbols inside 48-point targets. These are explicitly labeled sample previews, not live scene previews inside the sheet.
- Review puts the photo first in normal portrait and retains reachable tools above the photo in short landscape and accessibility layouts. The old textual menu becomes the shared visual library. Save to Photos remains explicit and uses the existing save/retry state machine. Viewing the original states which filtered look will actually be saved. Imports remain non-destructive new copies. The image budget leaves room for the pinned save explanation and actions.
- The Roll supports compact contact-sheet and roomy-grid density with a saved preference. Empty states retain actual authorization/recovery actions and add a direct return to shooting without requesting broader Photos access.
- Onboarding has larger rendered choices and useful look descriptors. The editor separates its image from wrapping text instead of placing large text over a fixed-height image. Its Reset control moves below the heading at accessibility sizes and owns its full hit target.

## Photographic demonstration previews

`LookPreviewCafe.imageset` reuses the repository's original generated [cafe demonstration input](app-store/screenshots/demo-source/README.md). It contains no private photographs, people, brands, or app UI. The PNG is byte-identical to `docs/app-store/screenshots/demo-source/cafe-original.png`, Git blob `68cbf5847f21d3335dd754cabff341cb0a882e12`. It is demonstration artwork, not evidence of a captured scene or a universal film calibration.

The UI swatch actor prepares a single 384-by-512-pixel source off the main actor and applies each actual production recipe. A count- and cost-limited NSCache retains at most 48 entries within a 12 MB cost budget; keys include the complete effective recipe so edited controls cannot reuse a stale grade. Live camera swatches still use the existing live snapshot when supplied. The renderer's deterministic diagnostic thumbnail API, its reference scene, disk cache, and pixel-parity tests are unchanged. No full-resolution per-card rendering, new camera session, network fetch, or Photos read is introduced. Missing demo artwork falls back to the existing deterministic preview, but a new hosted test requires the real asset to be bundled and verifies exact PNG equality with a direct production render.

## Preservation boundaries

No camera or Photos service, film-rendering pipeline, recipe catalog, image encoder, view-model save/import lifecycle, dependency, signing setting, deployment target, or generated project membership is changed by this redesign. New types and tests live in existing source files; the new image is inside the existing asset catalog. Hidden camera drawer previews detach while the library is presented. Favorites use stable IDs, deterministic bounded encoding, and the inherited preferences store, including isolated UI test suites.

## Verification

Baseline: UI experience run 34295744143 recorded actual iPhone 16 Pro/iOS 26 screenshots and passed all eight targeted pre-redesign tests. It is before evidence, not validation of changed UI.

Initial redesign: commit ab688fce6736d038b19c00e491b020bc62340c1a passed Release and physical-device-test compilation with Xcode 26.3/iOS SDK 26.2 in run 34297399589. Its iPad Pro 13-inch/iOS 26.0.1 run 34297399673 passed all twelve targeted UI tests with no failures or skips. Those actual screenshots informed the subsequent accessibility and photographic-preview polish. Do not treat that earlier pass as final-commit acceptance; use the current PR checks and artifact provenance.

All changed Swift sources passed local syntax parsing, all 53 portable runner tests passed, and workflow YAML plus shell blocks parsed. Eighteen Linux checks exercised the actual discovery/index code against a small model fixture. These local checks are not an iOS SDK typecheck or app execution.

This pass adds ten discovery/favorites/sample-render unit tests and four no-Photos-write UI scenarios through the existing suite inventory. The large-text library case also verifies an actual 48-point favorite control can be used without selecting or dismissing. Existing Photos acceptance still checks comparison, look changes, guarded save, cancellation, and relaunch into the saved photo; only its menu navigation changed for the new library. The read-only screenshot workflow runs on iPhone 16 Pro and iPad Pro 13-inch, and normal Photos acceptance exports actual review screenshots even on successful runs.

Use exact-commit CI results in PR 88 for final status. No simulator or compile result establishes real-camera, VoiceOver, iCloud, thermal, signing, or App Store acceptance. No main merge or Apple upload is part of this pass.

## Source transfer

The source changes were transferred as fixed checksummed patches with verified Git preimage/postimage hashes. Temporary same-repository, PR-88-only jobs created unreferenced content objects without executing app code or moving branches. The helper and compressed payload are absent from the resulting source tree; normal validation workflows remain contents-read-only. Final commit/ref updates are explicit through the connected repository tools.
