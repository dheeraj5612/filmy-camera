# App Store screenshot pack

This directory contains the five 1242×2688 JPEGs staged for the iPhone 6.5-inch Display slot in App Store Connect. The numeric prefixes preserve the upload order:

1. Camera preview and recipe rail
2. Settings and camera controls
3. Camera film-stock rail
4. Recipe details and tuning controls
5. Roll / recent-photo surface

The current pack mirrors the media already attached to the Filmy Camera 1.0 submission. It was generated from the iPhone 17 Pro UI-test capture set and is suitable for the current simulator-safe submission flow. Replace the preview-state captures with physical-device captures after camera and Photos QA is complete; run `scripts/release/validate-store-media.sh` after replacement.
