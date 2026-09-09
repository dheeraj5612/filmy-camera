# Current iPad 13-inch App Store screenshot pack

Five actual 2064×2752 PNGs from version 1.0.0 (11), captured September 5, 2026 with review look selection, Original comparison, and Instant Print. This replacement pack was uploaded to App Store Connect on September 5, 2026; a reload verified all five files in numeric order.

1. G7 X Compact import
2. Muted Color import
3. Fine Monochrome import
4. Populated Roll with exactly three matching saved treatments
5. Fine Monochrome photo detail

The public generated cafe original in `../demo-source/` was imported through the normal production Photos picker, renderer, review, save, Roll, and detail flows. This demonstrates imported media, not live camera capture. No private photos or composited app UI are included. The third import/detail flow shows the white Instant Print border and larger bottom margin.

The store-media flow used an isolated iPad Pro 13-inch (M5) simulator on iOS 26.5 with zero prior saves. All five images were visually inspected: G7 X is vivid, Muted Color is restrained, and Fine Monochrome is grayscale; the Roll shows their corresponding saved outputs.

Evidence: `build/instant-print-20260905/store-ipad-release/filmycamera-store-media-summary.json` and the attachment source directory `build/instant-print-20260905/store-ipad-release-attachments/` (ignored). The one store-media flow passed with zero failures/skips, exercising all three imports, review bounds, covered-camera interaction, saving, Roll, and detail. Build-input source digest: `fb1462ac724e88bcb7c2bea860fd618fa44360dc8e0b1c7b20af542094ac4673`.

Run `scripts/release/validate-store-media.sh` for format/dimension checks. Structural validation is separate from visual inspection and App Store Connect acceptance.
