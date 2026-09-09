# Filmy UI experience redesign

## Product changes

- A quiet ink-and-sage visual system with a pale blue action accent, editorial serif headings, and a restrained Filmy wordmark.
- The camera keeps the existing shutter, flash, zoom, focus, framing, session lifecycle, and explicit save behavior. The current look now has a renderer-backed thumbnail. Larger quick swatches lead to a full visual library rather than requiring long nested-row hunting.
- The shared Looks library has large renderer-backed sample cards, name/descriptor search, All/Favorites/Compact/Film/Monochrome filters, separate heart controls, persistent favorites, selected state, and actionable empty results. Selecting a card applies and dismisses; favoriting never applies. Search/filter changes return to the start of the results. A compact landscape header and single-column accessibility layout preserve room for content. These are sample previews, explicitly labeled, not a promise of live scene preview inside this sheet.
- Review puts the photo first in portrait, retains reachable tools in short landscape, and replaces the old textual look menu with the shared visual library. Save to Photos remains explicit and uses the existing save/retry state machine. Viewing the original states which filtered look will actually be saved. Imports remain non-destructive new copies.
- The Roll supports compact contact-sheet and roomy-grid density with a saved preference. Empty states keep their actual authorization/recovery actions and add a direct return to shooting without requesting broader Photos access.
- Onboarding has larger rendered choices and useful look descriptors. The editor separates its image from wrapping text instead of placing large text over a fixed-height image.

## Preservation boundaries

No camera or Photos service, renderer pipeline, recipe catalog, image encoder, view-model save/import lifecycle, dependency, signing setting, deployment target, or generated project membership is changed by this redesign. New types and tests live in existing source files. The library reuses the bounded thumbnail renderer/cache. Hidden camera drawer swatches detach while the library is presented; there is no second camera session. Favorites use stable IDs, deterministic bounded encoding, and the inherited preferences store, including isolated UI test suites.

## Verification

Baseline: UI experience run 34295744143 recorded actual iPhone 16 Pro/iOS 26 screenshots and passed all eight targeted pre-redesign tests. It is before evidence, not validation of changed UI.

Before hosted compilation, all changed Swift sources passed syntax parsing, all 53 portable runner tests passed, and workflow YAML plus 29 shell blocks parsed. Eighteen Linux checks ran the actual discovery/index code against a small model fixture. Those checks are not an iOS SDK typecheck or app execution.

Added eight discovery/favorites unit tests and four no-Photos-write UI scenarios, routed through the existing suite inventory. Existing Photos acceptance still checks comparison, look changes, guarded save, cancellation, and relaunch into the saved photo; only its menu navigation was updated for the new library. The read-only screenshot workflow now runs on iPhone 16 Pro and iPad Pro 13-inch, and normal Photos acceptance exports its actual review screenshots even on successful runs.

Use exact-commit CI results in PR 88 for final status. No simulator or compile result establishes real-camera, VoiceOver, iCloud, thermal, signing, or App Store acceptance. No main merge or Apple upload is part of this pass.

## Source transfer

The source files were transferred as a fixed checksummed patch with verified Git preimage/postimage hashes. A temporary same-repository, PR-88-only job created unreferenced content objects without executing app code or moving branches. That helper and its compressed payload are absent from this resulting tree; normal validation workflows remain contents-read-only. The final commit/ref update is explicit through the connected repository tools.
