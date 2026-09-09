# Launch experience and reliability pass: September 8, 2026

Status: **implemented for review, not certified for public release**. Base revision: `0c7f1021fd4e3bf008f1eef4958e995c45d99ee2`. This changes application source; earlier build 8 archive, device, and CI evidence does not validate this candidate. The existing [release checklist](release-checklist.md) remains the account-owner release record.

## Product changes

The first introduction screen now lets the photographer choose a real, renderer-backed look. The four-card selection uses stable recipe IDs rather than catalog indexes, retains the initial card order after a choice, resolves existing customized controls, and passes the choice through the existing CameraViewModel persistence path. Later introduction pages preview that choice. Back, Skip, and completion preserve it. The page is width-bounded on iPad; accessibility text sizes use a single-column recipe list, and motion respects Reduce Motion. Sample scenes are explicitly labeled, not represented as live camera output.

Import now uses an image file representation instead of immediately requesting an unbounded Data payload. A cancellable, chunked reader rejects empty, non-regular, and over-100,000,000-byte inputs before full allocation and rechecks the byte limit during reading. This encoded-file ceiling is separate from the existing 40 MP decoded-image budget. It is not a claim that peak app memory is limited to 100 MB.

Opening a provider/iCloud photo, applying the look, and cancelling are distinct accessible states. Download cancellation invalidates the operation identity immediately, so a late callback cannot start rendering or clear a newer import. Once rendering starts, cancellation keeps controls locked until the existing view-model render has drained; no cancelled result is admitted to review. Import does not bypass explicit Save. Failures offer another photo and preserve useful size-limit messages even when a provider wraps the error, without exposing provider paths. The camera's existing busy/lifecycle policy also covers the system photo picker.

CI cancellation is scoped to superseded pull-request runs. Main and manually dispatched runs use unique concurrency groups, preventing a later documentation-only run from cancelling an app run and then skipping its own app lane. Unique groups also protect pending runs, which `cancel-in-progress: false` alone would not do. Existing test lanes, pinned tools, required check names, signing boundaries, and generated-project checks remain intact.

## Regression coverage and evidence

Added 23 app tests: four onboarding catalog/persistence cases, seven import-operation lifecycle cases, ten bounded-file/error/cancellation cases, and two onboarding UI flows. Every new test class is assigned to routine CI in `scripts/testing/suites.json`. Existing XCTest source files carry the additional classes so the committed Xcode project and its generated references remain unchanged. The opt-in store screenshot class is unchanged and remains separate from routine onboarding tests.

Executed in the Linux editing environment:

- **17 Foundation XCTest cases passed, zero failures**, using the actual PhotoImportSession, PhotoImportFailure, and PhotoImportPolicy source extracted from ContentView.swift, with their actual XCTest methods. This validates the portable implementation, not UIKit, PhotosUI, or rendering integration.
- **Three workflow concurrency regression tests passed** with Python unittest.
- All **five changed Swift source files passed syntax parsing** with `swiftc -frontend -parse`. Parsing is not iOS SDK type checking or an app build.
- Workflow YAML parsed and all **22 embedded shell run blocks passed `bash -n`**. The original workflow was checked against its Git blob hash before changing only its concurrency policy.

The four model/onboarding tests and two UI tests require the iOS test host and were not executable locally. Review the pull request's exact-commit checks before merging; do not substitute older green runs. No new signed archive, IPA, App Store upload, real-device run, or screenshot acceptance was performed in this editing environment.

## Acceptance required before shipping

1. Pass the existing full core, UI, and normal Photos E2E lanes on this revision. Recheck generated-project reproducibility and Release/device compilation. Confirm the new onboarding tests are present in the selected-test inventory and counts, rather than skipped.
2. On iPhone and iPad, check first-run selection and persistence, smallest-screen and accessibility-text layout, VoiceOver focus, Back/Skip, and Reduce Motion. Validate imported JPEG, HEIC, PNG, portrait/landscape, and supported RAW inputs. Reconfirm Original comparison, alternate looks, save, and relaunch in the existing normal Photos flows.
3. Exercise a slow iCloud download, cancel before and during rendering, then import another photo. Confirm no stale result, duplicate save, stuck overlay, or permanently paused preview. Check the explicit 100 MB error, malformed files, permission denial, background/resume, and low-storage behavior. Measure memory and sustained thermals on device.
4. Complete the still-open iPhone lens/flash/interruptions and controlled image-quality checks from the release checklist. Prior iPad evidence does not prove iPhone telephoto behavior or image-quality claims.
5. From a clean reviewed commit, assign the next unused build number, archive and validate signed IPA/source parity, upload with the authorized Apple account, verify processing and matching media, and submit for review. Keep manual release enabled until acceptance is complete. Existing build 8 evidence and the last recorded build 5 upload are historical, not evidence of this revision's Apple status.

## Commands

```sh
python3 -m unittest discover -s scripts/testing -p 'test_*.py' -v
xcodegen generate --spec project.yml
git diff --exit-code -- FilmyCamera.xcodeproj
python3 scripts/testing/run.py ci --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID'
```

Use the existing release workflow for signing/export/upload. This pass deliberately adds no analytics service, network backend, account system, dependency, signing secret, or automatic release behavior.
