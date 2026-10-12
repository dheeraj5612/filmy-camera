# Filmy Camera: agent guide

Native iPhone/iPad film-recipe camera. SwiftUI, AVFoundation, Core Image. Shipping version and build live in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).

Read `docs/agent-notes.md` before rediscovering context, and append reusable decisions, failed attempts, commands with results, and evidence paths there. No secrets or raw dumps.

## Layout

| Path | Contents |
| --- | --- |
| `FilmyCamera/Services` | Camera session (`CameraService.swift`), renderer (`FilmRenderer.swift`), Photos and local store, encoders |
| `FilmyCamera/ViewModels` | `CameraViewModel.swift`: capture, review, import, save state |
| `FilmyCamera/Models` | Recipes, catalog, pure policy types (unit-test these) |
| `FilmyCamera/Views` | Camera, Roll, review, look picker, settings |
| `FilmyCamera/CaptureModes`, `FilmyCamera/Shooting` | Advanced capture workspace; Fuji-style banks, Drive/BKT, RAW library |
| `FilmyCamera/Monetization` | StoreKit, auth, ads. Dormant in Release |
| `FilmyCameraTests`, `FilmyCameraUITests` | XCTest and XCUITest |
| `scripts/testing` | Lane runner `run.py`, routing in `suites.json` |
| `Config`, `StoreKit` | xcconfig flags, StoreKit configuration |

## Build and test

Requires full Xcode. A Command Line Tools only machine cannot build, test, or run a simulator: there, limit local checks to `xcrun swiftc -parse <files>` (syntax only) and the portable Python suite, state that limit in the report, and get compile and test proof from CI.

```sh
xcodegen generate
python3 -m unittest discover -s scripts/testing -p 'test_*.py' -v
python3 scripts/testing/run.py inventory
python3 scripts/testing/run.py core \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  --derived-data build/TestSuiteDerivedData
python3 scripts/testing/run.py e2e --skip-build \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  --derived-data build/TestSuiteDerivedData
```

- `FilmyCamera.xcodeproj` is generated from `project.yml` and committed. CI pins XcodeGen `2.45.4` (`.github/workflows/ios-build.yml`); regenerate with that version only, another version produces spurious project diffs. If the local `xcodegen --version` differs, download the `2.45.4` release zip, check its SHA256 against the workflow, and run that binary. A clean tree must regenerate with zero diff before you trust the tool.
- New Swift file: add it, regenerate the project, commit both. New test class: classify it in `scripts/testing/suites.json` or the portable gate fails.
- Lanes: `unit`, `integration`, `core`, `e2e`, `photos-e2e`, `ci`, `device`, `performance`, `fixtures`, `lens`, `add-only`, `capture-sheet`, `store-media`, `build`, `device-build`. `--dry-run` prints the selection. Details: `docs/testing.md`.
- `MembershipStoreKitTests` hang on iOS 27 simulators; exclude those selectors there and cover StoreKit on iOS 18.5. `xcodebuild` may exit 133 after all tests pass: read the result, not only the exit code.
- Never infer success from missing output. Quote the result line.

## Rules

- Portrait iPhone is the primary acceptance layout. Every camera or controls UI change is checked on an iPhone simulator or device: viewfinder, shutter, look picker, Pro controls, dismissal, large text. Keep screenshots with the revision. iPad runs supplement, never replace, this gate.
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY: minimal`, deployment target iOS 17.0. CI compiles with Xcode 16.4, 26.x, and 27: guard newer SDK API with the `FILMY_IOS27_SDK` condition and availability checks, and keep expressions simple enough for the older type checker.
- Monetization: `FILMY_MONETIZATION_ENABLED` is `NO` in Release and `YES` in Debug (`Config/Monetization.*.xcconfig`). Release must never show a paywall, ad, sign-in, or quota gate, or block capture or save. Re-answer the privacy matrix in `docs/app-store/app-privacy.md` before any monetized build. Entitlements are per configuration (`CODE_SIGN_ENTITLEMENTS` in `Config/Monetization.*.xcconfig`): Release signs with the empty `FilmyCamera.Release.entitlements` and resolves the Google URL scheme to the bundle identifier so no placeholder ships. `python3 scripts/monetization/validate.py` must pass after any change there.
- A capture is never committed silently and never lost: save failures must leave a retryable copy. Photos exports write a receipt sidecar (`PhotosExportReceipt`) inside the change block and adopt it on retry, so a crash between commit and index update does not create a second asset. Add-only authorization cannot adopt: a duplicate is possible there, a loss is not.
- Settings keys shared across files are a contract: `locationTaggingEnabled.v1` (default on), `mirrorFrontPhotos.v1` (default on), `g7x.dateStamp.enabled` (default off), `cameraGestureHintSeen.v1`. UI tests launched without `-ui-testing` pass `-cameraGestureHintSeen.v1 YES` so the first-run hint cannot cover controls.
- Preview and export must render the same recipe identically. Preview aids (zebras, peaking, guides, histogram) never reach saved pixels.
- Do not rename `accessibilityIdentifier` values without updating `FilmyCameraUITests`.
- Do not retune looks or edit catalog data as part of an unrelated fix.
- `g7x-compact` ("G7 X Compact", film base `compactDigital`) is the default look and switches the camera screen into compact-digital mode (`isCompactDigitalMode`). Code inside `#if G7_APP` belongs to the separate `G7Camera` product (branch `codex/g7x-camera-experience`); this branch's `project.yml` never defines `G7_APP`, so CI does not compile it. The date stamp is opt-in in Filmy: Settings writes `g7x.dateStamp.enabled` (default off), read at shutter time through `G7DateStampPreferences`.
- `DailyPhotoQuota.advance` deliberately freezes when the clock moves backwards. Do not "fix" it to re-anchor on rollback: that refills an exhausted allowance. The freeze heals only after 24 h of monotonic time (`RollbackHeal`, `CLOCK_MONOTONIC_RAW`) accrue while the clock stays behind the anchor. `MembershipTests.testClockRollbackCannotRefillExhaustedAllowance` and `testRollbackThenForwardToOriginalTimeNeverRefills` pin this.
- A Live Photo whose movie fails still delivers the still (`liveMovieFailed`); never fail or drop the photo because the paired movie failed.

## Git hygiene

- Never commit agent worktrees. `.claude/worktrees/` is ignored; a tracked gitlink there has no `.gitmodules` entry and fails `actions/checkout` on every workflow.
- Stage explicit paths. No blanket "save pending changes" commits.
- No force-push on shared PR branches; reconcile by merge.
- `build/`, `artifacts/`, `.ci/` are ignored evidence dirs. Keep evidence there, not in tracked paths.

## Agent roles

Codex "Astra" is the main thread: plan, decide, review every diff, own integration. Codex "Luna" is a worker or subagent: one bounded brief with scope, exact paths, constraints, and an acceptance check. Workers never delegate further and never edit files outside their brief. Parallel workers get disjoint file sets, each in its own worktree.

- Create worker worktrees from the integration branch HEAD (`git worktree add --detach <dir> HEAD`), outside the repo. Tool-managed worktrees may branch from a stale `origin/main`.
- Every fix gets an independent skeptic review (a second agent told to assume the fix is wrong) before integration, then one integrated review of the combined diff for cross-worker compile seams. On a machine without Xcode this review is the only type check before CI: say so in the report.
- Workers leave changes uncommitted; the integration owner applies each diff, reruns the gates, and commits explicit paths only when the owner asks.
