# Camera UX redesign — September 4, 2026

This pass makes Filmy Camera easier to compose with and gives finished photos more screen space. The camera has one control area: a centered shutter, Roll and Import, with the current look immediately above. Wide iPad windows and phone landscape use an edge column. Settings opens directly from the camera.

The look drawer opens only when requested. Compact digital, color film, and monochrome looks have distinct groups, and the selected group and tile appear when reopening it. Tune is available in the drawer; adjustable controls precede reference information. Closing the drawer detaches its live-thumbnail consumer. Expanded tools and looks overlay the existing viewfinder instead of changing the framing rectangle.

Capture/import review and saved-frame detail use full-screen presentation. Review keeps metadata outside the photo and has one discard/save action pair. Its root-sized overlay avoids a second UIKit presentation during PhotosPicker dismissal, which could leave the status-bar and home-gesture insets missing on fast imports. Covered camera controls are accessibility-hidden, disabled, and excluded from hit testing; live recipe thumbnails detach. Review still uses the existing capture/save/pause/Retake state policy. Portrait iPad review enlarges the photo; only landscape uses a side panel. Action bars account for their actual height at larger text sizes; save errors remain scrollable. Roll and Settings retain a pinned return to the camera while scrolling.

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
- Final normal-app import/review/save/Roll/detail passed for all three treatments on both iPhone 6.5-inch and iPad 13-inch simulators. Refreshed packs use the same generated original, with an explicit prior-save offset for the partially populated iPhone test library. Checks cover status-bar/home-gesture clearance, photo width, and covered camera controls being noninteractive. XCTest existence alone includes covered elements and is not a VoiceOver focus audit.
- Required CI passed on the initial redesign commit `ba14aaa` in [run 33929562252](https://github.com/dheeraj5612/filmy-camera/actions/runs/33929562252), including unit/UI suites and release checks. The final review/layout follow-up requires its own PR check before merge.
- The live legal index, support page, and privacy policy returned successfully and were read back in the in-app browser on September 4. App Store Connect still lists build 5 as the latest processed build; build 7 has not yet been uploaded.
- Generic physical iOS build-for-testing passed; build 7 installed on the connected iPad. The latest lock readback still required its passcode. Build 6's physical evidence does not establish the new presentation's hardware behavior.

Local evidence: `build/ux-redesign-20260904/` (ignored), including `full-regression-v2.xcresult`, `focused-final.xcresult`, `recipe-editor-final.xcresult`, `iphone-review-accepted.xcresult`, `ipad-review-accepted.xcresult`, `device-build.log`, and `ipad-install.json`. The installed development build predates the final review overlay and narrow-label follow-up; its hardware pass remains pending unlock.
