# Testing Filmy Camera

The suite covers camera policy, recipes, rendering and exports, persistence, Photos recovery, and the complete camera UI. Routine CI uses one simulator build followed by unit/integration tests, UI tests, and real Photos import/save/relaunch tests. Hardware, performance, and private-fixture runs are explicit lanes.

## Run the suite

Use XcodeGen **2.45.4**, the same version pinned in CI, after adding source files. The generated project must be committed. Choose an installed simulator UUID with `xcrun simctl list devices available`.

```sh
xcodegen generate
python3 -m unittest discover -s scripts/testing -p 'test_*.py' -v
python3 scripts/testing/run.py ci \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID'
```

`ci` builds once, then executes every deterministic test without rebuilding between phases. `core` runs unit and integration tests; `unit`, `integration`, and `e2e` select narrower groups. The `e2e` lane includes UI cases compiled only for the simulator. The physical `device` lane excludes those cases while retaining every platform-independent UI acceptance, so selected and reported counts remain exact on both platforms. Reuse products built by this runner with `--skip-build --derived-data PATH`. A source/resource/project digest and Xcode/coverage stamp reject stale or unverified products. After changing Swift source or project membership, rebuild first.

```sh
python3 scripts/testing/run.py core \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  --derived-data build/TestSuiteDerivedData
python3 scripts/testing/run.py e2e --skip-build \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  --derived-data build/TestSuiteDerivedData
python3 scripts/testing/run.py photos-e2e --skip-build \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  --derived-data build/TestSuiteDerivedData
```

Photos E2E creates its own simulator using the reference UUID's device type and runtime, seeds the tracked public cafe image, handles the native Photos permission flow, and deletes only that created simulator afterward. It uses normal app launches and real PhotoKit persistence. It never seeds or erases the reference simulator or a physical device's library. Built-in simulator sample images may also be present; each import skips newer saved outputs to select the same unfiltered cafe source.

`--dry-run` prints the exact selection without building or touching a simulator. `inventory` prints every declared test and its assigned group:

```sh
python3 scripts/testing/run.py inventory
python3 scripts/testing/run.py ci --dry-run \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID'
```

## Coverage map

Counts describe declared test methods, not line coverage or proof of hardware behavior. `scripts/testing/suites.json` is the routing source of truth; adding an unclassified test class or leaving a stale override fails the portable gate.

| Area | Primary test classes | Behaviors checked |
| --- | --- | --- |
| Camera policy and lifecycle | `CameraServiceAvailabilityTests` | Authorization/availability, capture callback identity, preview ownership, recovery backoff, background/review policy, rotation/mirroring, focus and exposure, flash and lens calculations |
| Recipes and preferences | `RecipeInvariantsTests`, `RecipeReferenceCatalogTests`, `CameraViewModelPersistenceTests`, `RecipeDetailCommitPolicyTests` | Built-in identity and bounds, G7 X contract, public reference provenance, legacy migration, corrupt overrides, launch selection, reset/update/discard policy |
| Renderer and JPEG output | `RendererOutputBoundsTests`, `ColorSpaceBoundaryTests`, `PhotoOutputEncoderTests` | Output extent/alpha, render-stage effects, preview/export equivalence, grain behavior, color-space boundaries, JPEG decoding and embedded provenance, location metadata policy |
| Import and review | `CameraViewModelRenderingTests`, `CameraReviewSaveTests`, `CameraReviewEditingTests` | Invalid/cancelled import, selected-recipe snapshot, orientation/mirrors, pixel budget, reversible look auditions, source comparison, stale-work rejection, deferred export, denied/write-failed save and exact retry, duplicate Save and in-flight Retake prevention |
| Photos and local cache | `PhotoLibraryMetadataTests` | Permission policies, app-owned asset IDs, safe paths, atomic cache writes and failure recovery, cleanup/reconciliation, thumbnails, completion ordering and cancellation before callback registration |
| UI and accessibility | `FilmyCameraUITests` | Camera shell, G7 X controls, tuning and persistence, Back discards edits, Reset+Apply, onboarding and Skip, Roll/Settings navigation, large text, portrait/landscape, foreground/recipe-switch responsiveness |
| Normal Photos E2E | `NormalPhotoFlowTests` | Public fixture → G7 X review → Photos save → app relaunch → Roll detail; Original comparison and monochrome review selection survive save/relaunch without changing the shooting look; large-text import cancellation leaves Roll count unchanged |
| Test infrastructure | `scripts/testing/test_runner.py` | Complete routing, no duplicate CI selection, opt-in isolation, physical write guards, fresh-simulator cleanup ownership, rejection of zero/missing/skipped deterministic results |

Each deterministic UI case receives a unique preferences suite that persists across its own relaunches. Normal app launches ignore that testing environment variable. The Photos E2E uses its disposable simulator's real preferences and library.

## Hardware and optional lanes

Compile device-only branches before a release, even when hardware is unavailable:

```sh
python3 scripts/testing/run.py device-build
```

This builds unsigned generic-iOS test products. It cannot prove capture, autofocus, flash, thermal behavior, or the device's frame rate.

Run the physical suite on an unlocked, paired device with Developer Mode and working Xcode signing. It includes regular UI flows plus capture/import/save, Retake, Roll/detail/share cancellation, and flash checks. It retains test photos, so the runner requires the explicit write flag:

```sh
python3 scripts/testing/run.py device \
  --destination 'platform=iOS,id=YOUR_DEVICE_UDID' \
  --derived-data build/DeviceTestDerivedData \
  --allow-photos-writes
```

| Lane | Prerequisite / output |
| --- | --- |
| `performance` | Physical-device renderer/import/detector and launch benchmarks. Compare the same device, build configuration, scene, and thermal state. |
| `lens` | Physical iPhone 16 Pro lens/telephoto acceptance. Unsupported hardware is reported as skipped. |
| `add-only` | Configure **Add Photos Only** in Settings first; requires `--allow-photos-writes`. Checks readable local Roll/cache after save and relaunch. |
| `capture-sheet` | Physical device with a stable scene; attaches recipe captures without saving them to Photos. |
| `fixtures` | Local render fixtures under `FilmyCameraTests/Fixtures`; regenerate the project after adding them. Private fixture files and results stay untracked. Empty fixture sets skip explicitly. |
| `store-media` | Pass any reference simulator UUID. The runner creates a fresh simulator with the same device type/runtime, seeds only `docs/app-store/screenshots/demo-source/cafe-original.png`, forces zero prior saves, and destroys its owned simulator afterward. The reference simulator is untouched. Screenshots are attached to the result bundle. |

Optional lanes report prerequisites and skips explicitly. A passing supported subset with skips does not validate the skipped hardware behavior. Physical screenshot attachments may contain personal surroundings or photos; keep them local.

## Results, coverage, and CI cost

Every test phase writes an `.xcresult`, text log, and compact JSON summary under a unique `build/test-runs/` directory (or `--output-dir`). The summary records selected tests, actual pass/fail/skip counts, destination, elapsed time, source commit and dirty state, build-input digest, and Xcode version. Existing result bundles are never overwritten. Keep these with the build being evaluated.

Every lane fails for a failed test, missing bundle, zero passed tests, or a mismatch between selected and reported test counts. Deterministic lanes also fail on any skip. A green `xcodebuild` exit alone is insufficient. Opt-in environment flags inherited from the shell are cleared before the selected lane enables its own flags.

Coverage instrumentation is optional and requires a fresh instrumented build; do not add `--skip-build` to the first coverage run:

```sh
python3 scripts/testing/run.py core --coverage \
  --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  --output-dir build/coverage-run
xcrun xccov view --report --json build/coverage-run/FilmyCameraUnit.xcresult
```

CI runs portable routing checks on Linux before starting macOS. It retains the existing one-device lane, reuses compiled products, cancels superseded runs, and skips the simulator for unrelated changes. Benchmarks, fixture galleries, store media, and physical-device runs are excluded from routine CI. The workflow's manual **include_device_build** input adds unsigned generic-device compilation. Compact logs/summaries are retained for 14 days; full result bundles upload only on failure for 7 days.

## Remaining validation limits

The deterministic suite does not inject every PhotoKit service-level interleaving (for example, cache maintenance racing a save), or pause a renderer mid-import to force every cancellation schedule. Real permission revocation, add-only/limited access, storage pressure, thermal interruption, and long camera sessions still need device acceptance. Pixel-level assertions and public fixture E2Es do not replace visual comparison of skin tones, flash scenes, G7 X character, and Fuji looks on current hardware. See `docs/ipad-ui-acceptance-20260904.md` for the separate physical-device evidence.
