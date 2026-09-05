# Build 10: full-resolution output and physical Pro controls

Version 1.0.0 (10) preserves full-resolution camera and filtered output, explicitly encodes finished JPEGs at quality 0.95, and fixes flash restoration when returning from a reused manual-exposure lens to Auto. The Pro sheet has a pinned 44-point Done button and individually accessible control groups. Subscriptions, trials, and free-export watermarks remain planned work.

## Image pipeline

- The camera requests the largest photo dimensions supported by its active format. On the reference iPad Pro 11-inch (2nd generation), all three hardware acceptance captures retain 4032 × 3024 pixels (12,192,768 pixels).
- Aspect-fill framing crops pixels without scaling. Imports retain full resolution through the existing 40 MP memory budget; larger imports report their resizing. Filter rendering uses the full still-image extent.
- The 1800-pixel review image is display-only. Save uses the full rendered JPEG data for Photos and the local Roll.
- Finished exports explicitly use ImageIO JPEG quality 0.95, sRGB, and the existing metadata privacy allowlist. No extra sharpening or upscaling is introduced.

A reproducible 320 × 240 fine-edge fixture measured 71,616 bytes and RGB mean absolute error 7.015 with ImageIO's default, versus 90,211 bytes and error 6.245 at quality 0.95: 26% larger and 11% lower decoded error. A 1600 × 1200 fixture measured 29% larger files and 6% lower global error. These are fixture measurements, not measured improvements in camera optics or comparisons with another app.

The regression compares decoded production output with an independent explicit-quality 0.95 encode and verifies dimensions. Default-relative size/error remain diagnostic attachments because Apple's undocumented default can change between OS versions. Bitmap drawing keeps its backing storage valid through the complete CGContext operation.

## Physical acceptance

The build-10 targeted hardware run passed on iPadOS 26.6.1. It independently varies ISO and shutter, verifies settled sensor settings and saved JPEG EXIF, and checks white-balance gains, manual focus, session reuse, front-camera reset, rear-camera restoration, and rapid Reset to Auto. Flash On and actual output support both restore after the rear-camera transition.

| Request | Saved EXIF | Capture dimensions |
| --- | --- | --- |
| ISO 100, 1/125 s | ISO 100, 1/125 s | 4032 × 3024 |
| ISO 200, 1/125 s | ISO 200, 1/125 s | 4032 × 3024 |
| ISO 200, 1/60 s | ISO 200, 1/60 s | 4032 × 3024 |

An initial resumed run exposed a 36-point native toolbar button and lost Flash On preference. Replacing the toolbar with a pinned header fixed the touch target. The flash failure came from a reused rear device still reporting Custom before desired Auto settings reapplied; the suppression path now preserves the user's flash choice. Subsequent UI runs exposed inherited accessibility identifiers and a test scrolling the background camera rail; the section containers and explicit sheet-scroll target address those independently.

Local evidence is retained under `build/manual-controls-unlocked-20260905/`, including failed runs, metadata, captures, UI recordings, and per-run source digests. Hardware photographs remain local. The [build-9 record](manual-controls-acceptance-20260905.md) retains the earlier low-ISO EXIF discrepancy and its original failure.

## Saved-file verification

The physical capture/save flows wrote G7 X Compact and Fine Monochrome JPEGs. Readback of those newly saved files from the app's local Roll confirmed 3024 × 4032 pixels, the sRGB profile, Filmy Camera software/recipe provenance, and no GPS dictionary. Their sizes were 7,778,045 and 5,846,832 bytes respectively. These are the full rendered files used by the save path, not screenshots or review thumbnails. Local filenames and readback are recorded in `build10-saved-output-summary.json` within the evidence directory.

The saved G7 X image visibly retains fine fabric weave. This scene is useful for detail inspection but does not replace a controlled portrait/color comparison or an iPhone test.

## Release status

The final local source passed 189 core, 19 UI, and 3 normal Photos E2E tests with zero failures/skips, plus all 20 portable runner tests and project preflight. Its build-input digest is `8a84a53d8bb2d370bf41ab7de89e7b71e705d5a5721f971125f514d6a5c93ee0`. Physical Pro-sheet portrait/landscape and JPEG quality checks also pass on that digest.

The first full iPad run passed 24 of 25 checks. The UI runner disconnected during XCTest's app relaunch in `testRecipeFirstOnboardingFlow`, before the first onboarding assertion; no crash stack or jetsam reason was collected. On unchanged binaries, the onboarding test and its two neighboring tests all passed. Both the failure and the successful recheck remain separate evidence; the kill's exact cause is unresolved. A complete confirmation run is planned while hosted CI runs.

Subsequent exact-source CI, device confirmation, signed archive/export, and Apple processing readbacks are recorded in [PR 87](https://github.com/dheeraj5612/filmy-camera/pull/87) and the local evidence directory. Build 9's successful CI and signed IPA do not validate build 10. Apple sign-in is still required for upload. A controlled, well-lit sharpness/film comparison, iPhone lens acceptance, and sustained thermal testing remain launch gates; the current iPad checks establish dimensions and capture behavior, not superiority to Halide or a physical G7 X/Fuji camera.
