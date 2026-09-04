# Camera UX redesign — September 4, 2026

This pass makes Filmy Camera easier to compose with and gives finished photos more screen space. The camera has one control area: a centered shutter, Roll and Import, with the current look immediately above. Wide iPad windows and phone landscape use an edge column. Settings opens directly from the camera.

The look drawer opens only when requested. Compact digital, color film, and monochrome looks have distinct groups, and the selected group and tile appear when reopening it. Tune is available in the drawer; adjustable controls precede reference information. Closing the drawer detaches its live-thumbnail consumer. Expanded tools and looks overlay the existing viewfinder instead of changing the framing rectangle.

Capture/import review and saved-frame detail use full-screen presentation. Review keeps metadata outside the photo and has one discard/save action pair. Action bars account for their actual height at larger text sizes; save errors remain scrollable. Roll and Settings retain a pinned return to the camera while scrolling.

Neutral black surfaces keep attention on the image. Amber identifies compact digital looks and muted green identifies color film. The rendering recipes, image processing, export resolution, metadata, and save policy are unchanged in this UI pass.

## Design references

- [Halide Mark III](https://www.lux.camera/halide-mark-iii/): essential controls first, chosen-look access near capture, progressive tools.
- [Halide for iPad](https://www.lux.camera/halide-pro-camera-for-ipad/): edge controls and intentional tablet ergonomics.
- [Moment Pro Camera manual](https://www.momentprocamera.com/manual): explicit grouping of exposure, lenses, color, and quick actions.

These are interaction references, not copied artwork, branding, or processing implementations.

## Validation

Validation evidence is recorded with the completed change. Simulator layouts do not establish physical-camera quality, sustained preview performance, or an App Store release. Existing build 6 artifacts and their device evidence remain separate from this redesign.

- The full iOS 18.5 run completed 174 passes and 12 explicit hardware/fixture/opt-in skips, with two failures investigated: a renderer test host SIGSEGV and a test tapping the pinned Done button while the information toggle was partly visible.
- All 46 renderer output/bounds tests passed on the isolated rerun, including identical pixels across preview/photo/export. No renderer source changed; diagnostics did not include a crash stack, so the simulator attribution remains provisional.
- Updated UI tests reveal controls fully before tapping and inspect reference headings rather than treating a noninteractive card as a button. The editor test then passed; portrait, landscape, accessibility-size controls, G7 X details/quick controls, monochrome controls, pinned navigation, and foreground/return flows passed their exercised runs.
- Normal simulator import/review/save/Roll/detail completed successfully. Refreshed media uses fresh devices so an already-filtered saved frame cannot accidentally become the source.
- Generic physical iOS build-for-testing passed; build 7 installed on the connected iPad. The latest lock readback still required its passcode. Build 6's physical evidence does not establish the new presentation's hardware behavior.

Local evidence: `build/ux-redesign-20260904/` (ignored), including `full-regression-v2.xcresult`, `focused-final.xcresult`, `recipe-editor-final.xcresult`, `iphone-import-v2.xcresult`, `device-build.log`, and `ipad-install.json`.
