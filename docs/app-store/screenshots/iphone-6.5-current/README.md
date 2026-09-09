# Current iPhone 6.5-inch App Store screenshot pack

Five actual 1242×2688 PNGs from version 1.0.0 (11), captured September 5, 2026 with reversible review, Original comparison, and optional Instant Print borders. This replacement pack was uploaded to App Store Connect on September 5, 2026; a reload verified all five files in numeric order.

1. G7 X Compact import
2. Muted Color import
3. Fine Monochrome import with Instant Print border
4. Populated Roll with exactly three matching saved treatments
5. Fine Monochrome Instant Print photo detail

The public generated cafe original in `../demo-source/` was imported through the normal production Photos picker, renderer, review, save, Roll, and detail flows. This demonstrates imported media, not live camera capture. No private photos or composited app UI are included.

The hardened store-media runner created and seeded an isolated iPhone 11 Pro Max simulator on iOS 26.5, forced zero prior saves, and removed only that owned simulator afterward. Reference simulator libraries were untouched. All five images were visually inspected: G7 X is vivid, Muted Color is restrained, and Fine Monochrome is grayscale; the Roll shows their corresponding saved outputs.

Evidence: `build/instant-print-20260905/store-iphone/FilmyCameraStoreMedia.xcresult` and its attachment manifest (ignored). The one store-media flow passed with zero failures/skips, exercising all three imports, review bounds, covered-camera interaction, saving, Roll, and detail. Build-input digest: `a9d7f13a45f734b93a0d06ce0a04f69031a79035ae9ffb28db7fa56586ec7d90`.

Run `scripts/release/validate-store-media.sh` for format/dimension checks. Structural validation is separate from visual inspection and App Store Connect acceptance.

The source subsequently received compact-landscape layout changes; this portrait pack represents the unchanged portrait presentation.
