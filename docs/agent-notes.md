# Agent implementation notes

## 2026-09-13 CI review

- The catalog and UI workflows have no Swift package dependency or `Package.resolved`; Swift package download caching was therefore not added. DerivedData sharing remains unsafe across the macOS runner matrix.
- Classified `RendererRedCreaseRegressionTests` and `SignatureCharacterTests` as `integration`: both use deterministic in-memory Core Image fixtures and renderer assertions.
- Classified `RendererSkinCaptureDiagnosticsTests` as `fixtures`: its diagnostic export requires caller-supplied local capture metadata and output paths, so it remains opt-in and is skipped without the private fixture.
- Validation: `actionlint .github/workflows/catalog-acceptance.yml .github/workflows/ui-experience.yml`, inventory, and the full portable suite (`66` tests) passed.

## Build 26 / Signal Frame integration

- Integrated main `04228ed` and UX `75d9e64`, retaining renderer v19, live recipe controls and selfie mirroring. Recovery now rebuilds invalid graphs after interruption; debug capture diagnostics use complete file protection. Simulator protection attributes differ from hardware, so only that assertion is device-only.
- At `eb70442`, local Xcode 26.6/iOS 26.5 passed 468 core tests; GitHub release SDK compilation and 149 catalog acceptance tests passed. Full UI/Photos evidence remains required before merge.
- GitHub Photos fixture job `103814343176` passed the mandatory 160-photo test but rejected the new local diagnostic skip. Added its exact selector to the existing optional fixture allowlist, retaining strict required PhotoKit execution and regression coverage.

- Combined UI validation caught an undersized quick All filter (42.7pt); quick filters now guarantee 44pt width. Favorites persistence and largest Dynamic Type checks pass on iPhone 17 Pro/iOS 26.5. Updated legacy onboarding and simulator expectations for Signal Frame, and wait for stable controls before animated drawer/navigation taps. Two targeted simulator/navigation tests pass; full final CI remains the merge gate.
- iPad portrait compatibility windows scale controls to 75% in landscape. Use 64pt compact targets and element-relative test coordinates; app-normalized coordinates derived from accessibility frames can miss. Enlarged drawer/library controls retain bounded scrolling. Large-text review groups Look and Finish together; delete confirmation uses an alert with explicit Cancel. Updated simulator build passes; Photos and iPad acceptance reruns are pending.
- At `6211dbb`, iPhone acceptance passed 14/14 and local Photos passed 6/7, including split, save/relaunch, delete cancellation and permission recovery. Remaining accessibility fixes group Look/comparison beside Finish, cap library previews at 260pt, disable decorative onboarding and unavailable-preview hit testing, and put Roll's permission CTA before expanded explanatory text. A fresh-install XXXL test exposed the latter independently of previously granted Photos access. Exact final CI and Photos acceptance remain required; see PR #97 for final run evidence.
- At `75fc0e5`, actual XXXL review video showed the two-column Look title collapsing and controls below pinned actions. Use full-width accessible control rows and put actions in the same portrait content scroll. The AX test reveals and checks complete control bounds in `review-content-scroll`; normal-size controls retain their no-scroll assertions. Independent source review found no blockers; focused execution and final CI remain gates.
- iPad library evidence at `75fc0e5` showed the aspect-ratio child exceeding a 260pt maximum-height proposal. Use an explicit 220pt accessibility preview height so the first favorite action stays visible. Final integrated simulator build passes; acceptance evidence is tracked on PR #97.

- At `12965e7`, hosted iPad acceptance passed 14/14; iOS fallback hierarchy proved the native preview remained exposed despite SwiftUI hit-testing modifiers. Keep the renderer mounted, expose its diagnostic accessibility node only while running, and create live gesture/accessibility controls only for a running camera. Local Xcode 26.6/iOS 26.5 build and focused fallback, portrait rotation, and capture-setting persistence tests passed 3/3 with these changes. Hosted exact-head acceptance remains the merge gate.
