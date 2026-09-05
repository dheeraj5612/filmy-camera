# Current iPad 13-inch App Store screenshot pack

Five actual 2064×2752 PNGs from version 1.0.0 (7), captured September 4, 2026 after the camera UX redesign and review-inset fix. These replace the build 5 baseline locally; uploading them to App Store Connect is a separate release gate.

1. G7 X Compact import
2. Muted Color import
3. Fine Monochrome import
4. Populated Roll
5. Photo detail

The public generated cafe original in `../demo-source/` was imported through the normal production Photos picker, renderer, review, save, Roll, and detail flows. This demonstrates imported media, not live camera capture. No private photos or composited app UI are included.

Evidence: `build/ux-redesign-20260904/ipad-review-accepted.xcresult` and its exported attachment manifest (ignored). The run passed all three treatments, status-bar/bottom-gesture clearance, photo width, covered-camera interaction, saving, and Roll/detail checks. The final narrow camera-look label adjustment is outside the screens represented in this pack.

Run `scripts/release/validate-store-media.sh` for format/dimension checks. Structural validation is separate from visual inspection and App Store Connect acceptance.
