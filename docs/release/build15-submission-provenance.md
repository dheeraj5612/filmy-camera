# Build 15 submission provenance

The rejected 1.0.0 submission was replaced with build 15 after the required physical-device review flow was completed.

- **Version/build:** 1.0.0 (15)
- **Source:** `7076d23f58c6ab8fb476411947b87468949cd02c` on PR [#94](https://github.com/dheeraj5612/filmy-camera/pull/94)
- **Physical unit/render run:** 245 passed, 0 failed, 6 skipped (251 total)
- **Focused physical checks:** portrait rotation, representative Flow 15, and Flow 8c each passed with 0 failures
- **Review evidence:** `build/test-runs/device-release-physical/FilmyCamera-Build15-Physical-iPad-Review.mp4`
- **App Store Connect submission:** `6235ba06-24bc-4d62-be09-48571b051384`
- **Submitted:** September 10, 2026 at 2:57 PM EDT
- **Current submission status:** Waiting for Review

The binary was exported with Apple Distribution signing for team `6ALSCF5GBV`; the exported IPA reported `get-task-allow=false`. The App Review response is in [app-review-response-final.txt](app-review-response-final.txt). No simulator tests were run or scheduled for this release update; the source commit uses `[skip ci]` to honor the physical-iPad-only validation constraint.
