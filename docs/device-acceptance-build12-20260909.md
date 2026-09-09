# Build 12 device acceptance — September 9, 2026

Build 12 (1.0.0) uploaded successfully at 18:27 UTC. App Store Connect subsequently showed processing Complete and build 12 Ready to Submit. Build selection, TestFlight installation, and App Review submission remain incomplete. The signed archive source is `e73c5eed7487a7024ff9b6097d4f0ccbd48f55fa`; the test corrections preserve every production application and project input for those runs. The subsequent build 13 icon refresh is a separate candidate and does not restamp build 12. Device checks below use development-signed products from that application source, not the uploaded distribution binary.

## Recorded iPhone results

The unlocked iPhone 16 Pro ran iOS 26.6.1. The first four rows record the initial focused runs. After a second unlock, the corrected five-case pass completed and is recorded separately.

| Focused run | Passed | Failed | Skipped | What the evidence establishes |
| --- | ---: | ---: | ---: | --- |
| Flash, Retake, aid persistence | 2 | 1 | 0 | Flash capture reached review and repeated Retake restored fresh preview frames. Aid values persisted after relaunch, but the final zebras On-to-Off tap failed. |
| Manual exposure, autofocus, service flash | 3 | 0 | 0 | Capture EXIF/resolution, explicit sensor controls and session reuse, autofocus behavior, and the flash-fired result passed. |
| Save and Roll flow | 1 | 1 | 0 | Both new QA photos saved successfully. The second test stopped on an obsolete Roll accessibility label before detail/share. |
| iPhone lens acceptance | 0 | 0 | 1 | The zoom sequence and capture ran, but physical 5× telephoto confirmation was inconclusive for the scene. A bright, distant scene is still needed. |
| Corrected and expanded acceptance | 4 | 1 | 0 | Aid persistence, timer/square/histogram, background recovery, and full Save/Roll/Detail/Share passed. Synthetic volume-up did not reach review; volume-down was not reached. |

Three fresh QA photos were retained across both save runs: one Fine Monochrome and two G7 X Compact with Instant Print. The recorded Roll screenshot and hierarchy show both frames with `Newest first` and `Local cache`. No arbitrary personal photo was imported and no share recipient was selected.

## Test corrections and added coverage

The Roll test expected a combined `Newest first. Source:` accessibility label that the current app does not expose. Tests now require the actual separate `Newest first` and populated source labels; the add-only test still requires `Local cache` after save and relaunch. The frame, detail, and share assertions remain intact.

The aid test now taps the unique nested native switch instead of assuming a fixed inset from its enclosing SwiftUI row. It retains exact On/Off and relaunch assertions without retries or preference injection. The corrected simulator case passed once with zero failures/skips. The physical rerun also passed, including zebras On-to-Off and a final relaunch. This supports an interaction-targeting correction; no production preference change was needed.

Two new cases are routed exclusively to the device lane:

- `testPhysicalTimerCancellationAndSquareCaptureWithLiveHistogram`: require fresh preview frames, configure a 10-second timer and square framing, observe live histogram output, cancel and wait beyond the original deadline without a review, then complete a timed square capture and Retake. It never saves.
- `testPhysicalVolumeButtonsCaptureAndRetake`: press volume up and down through XCTest's physical-device button API, require a rendered review after each press, and Retake to fresh preview frames. It never saves.

All 66 portable runner/release checks and the signed generic-iOS test build passed. The new cases compile for physical iOS and are excluded from routine simulator CI. Static review found no actionable issue in these test changes.

## Completed second physical pass

The first preflight was blocked by a locked phone. After the user unlocked it, the following exact cases ran:

1. `CaptureSetupUITests/testCaptureSetupOpensAndKeepsAidsAcrossRelaunch`
2. `FilmyCameraUITests/testPhysicalTimerCancellationAndSquareCaptureWithLiveHistogram`
3. `FilmyCameraUITests/testPhysicalVolumeButtonsCaptureAndRetake`
4. `FilmyCameraUITests/testBackgroundingAndForegroundingRestoresTheViewfinder`
5. `FilmyCameraUITests/testPhysicalG7XSaveRollDetailAndShareAcceptance`

The fifth case saved exactly one newly captured QA photo, verified the populated Roll and detail zoom/pan/reset, and opened/dismissed the share sheet without sending anything. No arbitrary personal photo was imported. The timer case captured a square review and discarded it; canceled capture never reached review beyond the original deadline.

The volume-button case failed after a documented XCTest volume-up event while the preview remained live. No review or system volume HUD appeared in the inspected frames. The evidence does not distinguish application behavior from synthetic-event delivery. Actual user volume-up/down confirmation is required before calling hardware-shutter acceptance complete; if it also fails, inspect the modifier’s enabled state and received event phases before changing production behavior.

The timer case measures review-image aspect, not saved-file dimensions. Histogram publication does not prove continuous updates or zebra/peaking pixels. Volume-button testing does not prove the dedicated Camera Control button or suppression in every disabled state. Full acceptance still includes the scene-dependent telephoto check, controlled import/image-quality work, sustained behavior, iPad testing, and the uploaded distribution build.

Private result bundles, logs, screenshots, hashes, and exact commands are retained under the ignored `build/pr90-evidence/build12-resume-physical-20260909T182408Z` and isolated worktree's `build/device-qa-evidence` directories. They are not store media or public attachments. The release checklist remains incomplete until the remaining evidence is recorded.
