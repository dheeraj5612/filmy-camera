# Physical iPad interface acceptance — September 4, 2026

The Halide-inspired camera interface is implemented and installed as development version 1.0.0 (8) on the connected 11-inch iPad Pro (2nd generation), running iPadOS 26.6.1. The design uses a dominant viewfinder, edge controls on iPad, an on-demand grouped look drawer, adjustable recipe controls before reference information, and full-screen photo review. See [the design pass](design-pass-20260904.md) for the interaction references.

## Hardware evidence

The first physical run exercised 13 interface tests: 11 passed, none skipped, and two failed while the test driver scrolled the recipe information panels. Passing flows included large text, portrait/landscape controls, monochrome controls, background/foreground, page navigation, rapid look switching, capture and Retake, import and save, and G7 X capture/save/Roll/detail/zoom/share cancellation. Real test photos were retained in Photos; no photo was sent through the share sheet.

The recordings showed that the old generic editor scrolling gesture crossed sliders and the pinned action button. The replacement gesture stays inside the editor's leading gutter and above its action bar; losing the editor now fails immediately. Picker taps also avoid a floating AssistiveTouch button overlapping the center of the iPad edge control.

Some screenshots captured a black viewfinder despite successful still capture. An enabled shutter proves session readiness, not displayed frames. Explicit test launches now expose successful Metal render revisions through the preview accessibility value, and hardware helpers require two advancing revisions. This instrumentation does not change render scheduling, image processing, or normal VoiceOver descriptions.

On the iPadOS 26 simulator, XCTest reported the first tile in a nested recipe row as non-hittable despite fully visible bounds. A direct tap selected G7 X correctly and the complete profile editor flow passed. The simulator test now checks the tile's minimum size and visible bounds, selects another film look, taps G7 X, and verifies that its selection and Tune action update. Physical-device tests retain the normal hittability check and button tap.

The final focused iPad simulator run passed all four tests with no skips: large-text camera/editor controls, Muted Color controls and public reference, G7 X selection and profile reference, and landscape camera/drawer layout. Both the simulator and signed physical iOS build-for-testing passed.

## Remaining acceptance

- Complete both recipe information-panel tests with the corrected gestures.
- Verify fresh rendered frames and visually inspect settled portrait, landscape, and G7 X views on hardware.
- Run final PR checks on the finished commit. The initial PR run was cancelled intentionally while these checks were being corrected.

The iPad locked between runs. The final signed generic iOS build-for-testing passed, and the app was installed again from that output. Eight focused hardware checks are queued waiting for unlock, covering recipe information, rendered-preview progress, rotation, navigation, Retake, and normal G7 X capture/save/Roll/share. Installation and a successful build do not establish those checks' results. This report does not claim App Store upload, release readiness, or visual parity with Halide.

Local evidence is retained under ignored `build/ipad-ui-20260904/`: `physical-ui.xcresult`, `accepted-simulator-ui.xcresult`, `accepted-device-build.log`, `accepted-ipad-install.json`, `installed-build-evidence.json`, and exported attachments. Device screenshots and photographic fixtures are kept local.
