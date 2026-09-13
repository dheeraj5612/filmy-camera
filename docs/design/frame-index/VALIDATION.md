# Frame Index — validation record

## Source and boundaries

Upstream base: `04228ed7754d677ba99db495ecd9b3753db096e2`.
Baseline tree: `1a1903ccf324ced3d916241d5247279a343d2c26`.
No `AGENTS.md` was present in the complete source snapshot. `README.md`, project configuration, existing workflows, tests and the camera/import/Photos/renderer boundaries were inspected. The separate draft App Review hardening PR #95 is not merged or overwritten by this pass.

The working runtime is Linux with Swift 6.2.1, not Xcode. Native builds and screenshots run on ephemeral **GitHub-hosted macOS simulators**, never an attached physical camera. `swiftc -frontend -parse` is syntax-only, explicitly not an iOS build.

## Baseline (unchanged source)

[Baseline run 34786498959](https://github.com/dheeraj5612/filmy-camera/actions/runs/34786498959) checked out the exact upstream base, used Xcode 26.3 / iOS 26.2 and disabled code signing. Both **iPhone SE (3rd generation)** and **iPhone 16 Pro Max** passed all **7 selected tests**, with 0 failed and 0 skipped. Real XCTAttachment screenshots, logs, device IDs, source SHA and xcresult summaries were downloaded and inspected. These are not full-suite or hardware results.

Observed before: a large non-live preview card obscures the sample photograph; serif/pill chrome lacks a distinct graphic index; Tune is behind the drawer; Original is absent from the camera; onboarding repeats guidance over three pages and incorrectly describes camera saves as manual. Accessibility/roll/editor baseline screenshots are retained for comparison.

## Initial implementation checks

New test coverage is explicit in `scripts/testing/suites.json`: renderer bypass/framing invariants, original/look geometry, EV quantization, original-preview UI state, direct Tune, largest Dynamic Type, system-light neutral workspace, first-use privacy, and real Photos import comparison/discard recovery. Existing permission and hardware opt-in gates are retained. Portable test routing initially rejected missing simulator-method overrides; the manifest and its expected inventory were corrected rather than weakening the runner.

Native validation and two screenshot-led refinement passes are **pending** at this intermediate commit. Do not treat this record as a completed acceptance report until the results below are populated.

## Reproduction

```sh
python3 scripts/design/generate_identity.py
python3 -m unittest discover -s scripts/testing -p 'test_*.py' -v
# On macOS, use the repository's pinned XcodeGen 2.45.4 to regenerate the project.
xcodegen generate --spec project.yml
python3 scripts/testing/run.py ci --help
```

The read-only `Frame Index UI acceptance` workflow creates and deletes only its own small/large simulators and exports actual XCTest attachments and result summaries. The existing iOS gate remains the broader regression suite on Xcode 16.4 / iOS 18.5.

## Physical device gates (not verified here)

Live MTKView comparison with camera buffers, lens/front-camera switching, focus/exposure settling and lock, capture latency, preview/capture matching and grain alignment, interruption/recovery, hardware shutter buttons, Photos denial/limited/add-only transitions on a user's real device, metadata export and share-sheet cancellation need the existing opt-in physical acceptance lanes. No App Store release or signing change is authorized or performed.
