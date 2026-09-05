# Current iPad 13-inch App Store screenshot pack

Five actual 2064×2752 PNGs from version 1.0.0 (8), captured September 5, 2026 with reversible review look selection and Original comparison. Uploading this replacement pack to App Store Connect remains a separate release gate.

1. G7 X Compact import
2. Muted Color import
3. Fine Monochrome import
4. Populated Roll with exactly three matching saved treatments
5. Fine Monochrome photo detail

The public generated cafe original in `../demo-source/` was imported through the normal production Photos picker, renderer, review, save, Roll, and detail flows. This demonstrates imported media, not live camera capture. No private photos or composited app UI are included.

The hardened store-media runner created and seeded an isolated iPad Pro 13-inch (M5) simulator on iOS 26.5, forced zero prior saves, and removed only that owned simulator afterward. Reference simulator libraries were untouched. All five images were visually inspected: G7 X is vivid, Muted Color is restrained, and Fine Monochrome is grayscale; the Roll shows their corresponding saved outputs.

Evidence: `build/store-media-build8-fresh-20260905/ipad/FilmyCameraStoreMedia.xcresult` and its attachment manifest (ignored). The one store-media flow passed with zero failures/skips, exercising all three imports, review bounds, covered-camera interaction, saving, Roll, and detail. Build-input digest: `85e5c804f1ed8fe195a19812b1b19fe00e4af9a76bb522ec42fffc3adaaf9c41`.

Run `scripts/release/validate-store-media.sh` for format/dimension checks. Structural validation is separate from visual inspection and App Store Connect acceptance.
