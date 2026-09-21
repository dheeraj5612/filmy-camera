# Deep regression expansion

This change adds **46 XCTest methods** to existing registered suites. The counts
below describe only the four touched classes, not the app's entire test suite.
Production behavior, Xcode project membership, suite routing, and physical Photos
write opt-ins are unchanged.

| Existing class | Lane | Before | After | Added |
| --- | --- | ---: | ---: | ---: |
| GalleryPagingPolicyTests | unit | 6 | 18 | 12 |
| ReviewComparisonStateTests | unit | 15 | 28 | 13 |
| ColorSpaceBoundaryTests | integration | 1 | 14 | 13 |
| SignalFrameUITests | e2e | 2 | 10 | 8 |
| Total for touched classes | | 24 | 70 | 46 |

## What the assertions protect

**Gallery policy:** An independent small-roll oracle checks valid neighbors and
retained indices. Retention stays within three frames, even with Int.max counts;
invalid offsets and indices cannot overflow or wrap. Identity resolution is
checked after ordering and deletion changes. Gesture tests cover both sides of
minimum/proportional/maximum thresholds, diagonal equality, exact zoom equality,
and 1,024 reproducible mirrored samples. These are policy guarantees, not a
measurement of the gallery's actual resident memory.

**Comparison state:** Visible mode, pending intent, and divider position are
asserted separately across transition matrices. Late or duplicate completions
cannot reopen canceled comparisons; rejected requests do not destroy pending
intent; failure and reset behavior are idempotent. Geometry tests cover different
resolutions, invalid values in every dimension, and both sides of the split
framing tolerance. These tests simulate event order without wall-clock sleeps;
they are not a concurrency stress test of the image loader.

**Real image integration:** Synthetic CIImage input passes through FilmRenderer,
PhotoPrintCompositor, sRGB materialization, PhotoOutputEncoder, and ImageIO decode.
Pixel assertions use JPEG-aware tolerances, including P3 conversion and paper
borders. Other cases verify alpha flattening, offset crops, EXIF dimensions,
recipe provenance, malformed metadata, all eight source orientation tags,
reimport/reexport, an owned temporary disk round trip, and legacy metadata.
The private-metadata fixture is first decoded to prove GPS/owner/comment data
actually exists before asserting its removal. ISO and exposure must survive.
No network fixtures, private captures, or personal Photos writes are required.

**App E2E:** Unique defaults suites isolate every journey. Tests drive per-look
favorites, deletion of the final favorite, duplicate prevention, cold launch,
background/foreground, drawer filter cycles, and largest accessibility text.
Relaunches remove the recipe seed so command-line overrides cannot fake successful
persistence. All-looks navigation scrolls the grouped picker, verifies the selected
row, then explicitly closes it. Bounded predicate waits attach screenshots and an
accessibility tree on timeout. Existing tests remain in place.

## Run the portable policy suite

Requires Python 3 and Swift 6 or newer on macOS or Linux. No third-party Python
packages or Swift package dependencies are used.

```bash
python3 scripts/testing/check_policy_regressions.py --mutation-checks
```

The checker copies current production policies and the current two XCTest files
into an owned temporary Swift package. On Linux only, it removes the unavailable
CoreGraphics import in that copy; Foundation supplies the geometry types. It does
not edit the repository. The printed evidence directory contains source SHA-256
hashes, toolchain details, baseline and mutation logs, and summary.json. To choose
an evidence destination, pass `--output-dir` with a path that does not exist yet.
Existing evidence is never overwritten.

The optional mutation check seeds six independent defects: unbounded retention,
invalid offset acceptance, paging while zoomed, losing a visible comparison on
failure, resetting the divider on selection, and accepting mismatched framing.
Each must compile, execute the full policy test count, and fail an XCTest.
Compilation errors, missing cases, and empty runs do not count as detection.
Mutation anchors must match exactly once; source changes require deliberate
review of any stale anchor. This finite check is not a coverage percentage.

## Run native unit, integration and E2E lanes

Use the repository's pinned XcodeGen and Xcode/runtime from ios-build.yml. First
verify discovery and project reproducibility:

```bash
xcodegen generate --spec project.yml
git diff --exit-code -- FilmyCamera.xcodeproj
python3 scripts/testing/run.py inventory
```

With an available iPhone simulator matching CI:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
python3 scripts/testing/run.py core --destination "$DESTINATION" --coverage
python3 scripts/testing/run.py e2e --destination "$DESTINATION" --coverage --skip-build
```

The runner creates unique evidence directories by default. Keep coverage options
consistent when reusing build products. Inspect each lane's selectedTests,
passed/failed/skipped counts and xcresult, not only the xcodebuild exit status.
The existing CI completeness checks reject unexpected skips and missing tests.
For the full routine gate, use the existing `ci` lane with an explicit simulator
UDID; the Photos phase creates and deletes only its own disposable simulator.
Physical camera, flash, Photos permission, and device acceptance remain separate
from this simulator-safe expansion and still require their existing opt-ins.

## Validation recorded when authored

Based on main commit `3d1428ec8497ad6b3836db256cb75145828f5add` on September 15, 2026.
Swift 6.2.1 on x86_64 Linux executed **46 policy tests with zero failures**:
21 existing tests plus 25 additions. All six seeded mutations were detected by
completed XCTest runs. Swift frontend syntax parsing passed for all four changed
Swift files; `git diff --check` also passed.

This environment cannot compile or execute Core Image, ImageIO, UIKit or XCUITest.
The 13 added image integration tests and 8 added UI journeys therefore still need
native macOS/Xcode validation. The portable checker explicitly records
`nativeIOSValidated: false`. Consult this PR's GitHub checks for native results;
do not treat the portable result as a full app pass or claim an unmeasured code
coverage increase.
