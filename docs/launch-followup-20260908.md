# Launch follow-up: accessibility recovery and submission SDK gate

This continues [PR 88](https://github.com/dheeraj5612/filmy-camera/pull/88), not a public release. The original [implementation record](launch-readiness-20260908.md) is historical. Use the exact-commit CI links in the PR for current validation, not the older build 8 archive or an earlier green workflow.

## Fixes driven by actual UI failures

The downloaded logs from [run 34287522525](https://github.com/dheeraj5612/filmy-camera/actions/runs/34287522525) show a successful iOS build and 201 passing unit/integration tests, followed by three UI failures. The failures were not a demonstrated persistence defect: two tests could not find the Skip/Continue identifiers, and an existing test measured Skip at about 31 points wide instead of the required 44.

The root onboarding identifier had propagated into its child buttons. The screen and recipe chooser now explicitly contain child accessibility elements. The Skip, Back, and Skip for now labels own their minimum-size frames and rectangular interaction regions. This fixes the control itself instead of loosening the existing tests. The import progress container and Cancel import button receive the same containment and hit-target treatment.

App-source fix: `e7137fc51ac5df5ed3a434089de065c222235ef4`. Its dedicated new UI regression checks that the screen identifier does not replace a button identifier, every primary onboarding action is hittable with at least a 44 by 44 point frame, and Back remains reachable after navigation. It records an actual simulator screenshot as an XCTest attachment. The two selection/persistence UI flows explicitly establish portrait orientation rather than inheriting it from another test.

No persistence assertion, existing hit-target minimum, or normal Photos acceptance check was removed. The renderer and explicit-review/save policy are unchanged.

## SDK minimum enforced before distribution

[Apple's submission requirements](https://developer.apple.com/news/upcoming-requirements/), verified September 8, 2026, require Xcode 26 or later and an iOS 26 or later SDK for uploads since April 28, 2026. The existing Xcode 16.4/iOS 18.5 CI job remains an older-SDK compatibility test; it must not be mistaken for distribution-toolchain acceptance.

`scripts/release/validate-sdk.py` has two read-only modes:

```sh
python3 scripts/release/validate-sdk.py --current
python3 scripts/release/validate-sdk.py --app-info /path/to/FilmyCamera.app/Info.plist
```

`archive-device.sh` invokes the first mode before creating output directories, generating the project, or handling signing. `validate-archive.sh` invokes the second mode against the built app, rather than assuming the currently selected Xcode built an existing archive. Existing export/upload preparation and IPA validation already delegate to archive validation, so they inherit this check.

The checker rejects obsolete Xcode/SDK versions, simulator platform metadata, missing or malformed build stamps, inconsistent SDK stamps, unavailable tools, and command timeouts. It reads XML and binary plists, avoids shell interpolation, and does not echo arbitrary subprocess diagnostics. It does not change the app's iOS 17 deployment target. The stamp check verifies recorded SDK metadata, not authenticity by itself; the existing strict signature, provisioning, source provenance, executable/dSYM, and IPA checks remain necessary. Passing this minimum check is not proof that Apple accepts a particular beta, signs the app, processes an upload, or approves a submission.

## Tests and verification boundaries

There are 25 new portable SDK tests. They cover version boundaries, malformed/missing inputs, simulator rejection, matching SDK stamps, older deployment targets, subprocess errors/timeouts, XML/binary/corrupt plists, CLI modes, archive wiring, and an actual archive-script invocation with mocked old tools that verifies no output folder is created. All 25 passed locally, as did the three existing concurrency tests. Both modified shell scripts passed `bash -n`. The local working copy is a source subset, so those 28 local tests are not represented as the complete repository suite.

The new SDK test file is under the existing `scripts/testing/test_*.py` CI discovery path. It needs no Apple credentials, network, signing identity, additional Python packages, or real Photos writes. The portable tests verify behavior with controlled tool/plist fixtures; they are not a new signed archive or a device run.

## Still required for public release

Pass the final commit's hosted checks. Then use an accepted distribution Xcode to build the reviewed source and complete iPhone/iPad device acceptance, including slow iCloud imports and cancellation, lens/flash behavior, interruption recovery, VoiceOver, accessibility text sizes, and sustained thermals. Assign the next unused build number only after an App Store Connect readback, validate archive/IPA/source parity, refresh matching screenshots where needed, upload, and submit for review. Keep manual release until those checks are complete. No new Apple upload, review submission, or public release is claimed here.
