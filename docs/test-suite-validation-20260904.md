# Test suite validation — September 4, 2026

The expanded routine suite passed locally with **193 app tests and 18 portable runner checks**, with zero failed or skipped tests in those completed runs. The inventory contains 212 declared app tests: 193 in routine CI and 19 in hardware, performance, fixture, or store-media lanes.

| Completed gate | Result | Local evidence under `build/comprehensive-tests-20260904/` |
| --- | --- | --- |
| Unit and integration | 173 passed, 0 skipped | `final/FilmyCameraUnit.xcresult`, `final/filmycamera-core-summary.json` |
| Camera UI and accessibility | 18 passed, 0 skipped | `final/FilmyCameraUI.xcresult`, `final/filmycamera-e2e-summary.json` |
| Normal Photos E2E | 2 passed, 0 skipped | `photos-v4/FilmyCameraPhotosE2E.xcresult`, `photos-v4/filmycamera-photos-e2e-summary.json` |
| Runner self-tests | 18 passed | `python3 -m unittest discover -s scripts/testing -p 'test_*.py' -v` |
| Generic iOS test compilation | Passed, unsigned | `device-current/filmycamera-build-for-testing.log` |
| Workflow/project checks | Passed | `actionlint`, generated project preflight, release metadata/media checks, and `git diff --check` |

Local XCTest used Xcode 26.6 and an iPad Pro 13-inch simulator running iOS 26.5. The Photos lane created and deleted its own simulator, exercised the native permission prompt, imported the public cafe fixture, cancelled without adding a Roll frame, and saved/relaunched into a populated G7 X Roll detail. Its final driver was rebuilt after the other lanes; each JSON summary records its own build-input digest and source state. CI runs the three lanes from one shared build on Xcode 16.4 / iOS 18.5 / iPhone 16 Pro.

New coverage includes denied/write-failed save retries preserving the exact review image, encoded bytes, recipe, and timestamp; duplicate Save/in-flight Retake prevention; all eight EXIF orientations; import pixel-budget boundaries; atomic cache-write failure; cancellation before image-request continuation registration; recipe Back/Reset/Apply persistence; and onboarding Skip.

The runner rejects stale or unverified build products, source changes during a build, unclassified tests, missing/zero results, incomplete test counts, and unexpected deterministic skips. Hardware Photos writes require an explicit flag. Benchmarks and fixture galleries remain opt-in, with no extra routine macOS matrix or scheduled runs. See [testing.md](testing.md) for commands and remaining coverage limits.

The physical iPad remained locked at the final device-state check. Generic-device compilation is not hardware acceptance; current capture, flash, live preview, add-only permissions, and performance acceptance still require an unlocked device and updated signed build. Earlier hardware evidence is recorded separately in [ipad-ui-acceptance-20260904.md](ipad-ui-acceptance-20260904.md). No claim of full line/branch coverage or launch readiness is made by this report.
