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
