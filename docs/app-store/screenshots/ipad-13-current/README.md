# Current iPad 13-inch App Store screenshot pack

Five actual 2064×2752 PNGs from version 1.0.0 (12), captured September 9, 2026 from clean source `731b285d1e3e9b28f9a960e21466a4a001b23e3e`. The application/project inputs match signed archive source `e73c5ee`; the intervening changes correct the screenshot test helper and privacy documentation. This pack has not been uploaded to App Store Connect.

1. G7 X Compact import
2. Muted Color import
3. Fine Monochrome import with Instant Print border
4. Populated Roll with exactly three matching saved treatments
5. Fine Monochrome Instant Print photo detail

The public generated cafe original in `../demo-source/` was imported through the normal production Photos picker, renderer, review, save, Roll, and detail flows. These images demonstrate imported media. No private photos, composited app UI, debug overlays, or camera-unavailable placeholders are included.

The runner created and seeded an isolated iPad Pro 13-inch (M5) simulator on iOS 26.5 with zero prior saves. All five images were visually inspected: G7 X is vivid, Muted Color is restrained, Fine Monochrome is grayscale, and the Roll shows the corresponding saved outputs. The test also verifies complete photo bounds, source/Instant Print aspect ratio, reachable Look/Compare/Finish/Save controls, safe areas, and disabled covered-camera controls.

Evidence: `build/pr90-evidence/store-media-build12/ipad-pack-run/filmycamera-store-media-summary.json` and `ipad-13-attachments/manifest.json` (ignored). The complete store-media flow passed one test with zero failures/skips. Build-input digest: `2bedbf23ff30a5073b12b1e1ce716bbef9f660520bf62d240e308d231002db15`. Toolchain: Xcode 26.6, build 17F113.

Capture provenance and per-image hashes are tracked in [build12-provenance.json](../build12-provenance.json).

Run `scripts/release/validate-store-media.sh` for format/dimension checks. Local validation is separate from Apple upload and acceptance.
