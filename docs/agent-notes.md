# Agent implementation notes

## 2026-09-13 CI review

- The catalog and UI workflows have no Swift package dependency or `Package.resolved`; Swift package download caching was therefore not added. DerivedData sharing remains unsafe across the macOS runner matrix.
- Classified `RendererRedCreaseRegressionTests` and `SignatureCharacterTests` as `integration`: both use deterministic in-memory Core Image fixtures and renderer assertions.
- Classified `RendererSkinCaptureDiagnosticsTests` as `fixtures`: its diagnostic export requires caller-supplied local capture metadata and output paths, so it remains opt-in and is skipped without the private fixture.
- Validation: `actionlint .github/workflows/catalog-acceptance.yml .github/workflows/ui-experience.yml`, inventory, and the full portable suite (`66` tests) passed.
