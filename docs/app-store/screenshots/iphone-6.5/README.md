# App Store screenshot pack

This directory contains the five 1242×2688 JPEGs staged for the iPhone 6.5-inch Display slot in App Store Connect. The numeric prefixes preserve the upload order:

1. Camera preview and recipe rail
2. Settings and camera controls
3. Camera film-stock rail
4. Recipe details and tuning controls
5. Roll / recent-photo surface

This historical pack was generated from an earlier iPhone simulator UI-test capture set. It includes Preview mode, clipped recipe text, and an empty Roll, and is not approved for launch. Replace it with current physical-device camera, review, tuning, and populated Roll screenshots after camera and Photos QA is complete. Run `scripts/release/validate-store-media.sh` after replacement; its structural checks do not establish visual quality or freshness.
