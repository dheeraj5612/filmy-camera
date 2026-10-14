# Filmy Camera

Filmy Camera is a native iPhone and iPad camera built around the feeling of choosing a film recipe before you shoot. It combines a low-friction SwiftUI camera UI with a Core Image/Metal-ready rendering pipeline for live preview and full-resolution exports.

## Start here

[Download on the App Store](https://apps.apple.com/us/app/filmy-camera-film-filters/id6801404866) · [Rendering decisions](docs/research.md) · [Testing guide](docs/testing.md)

**Engineering focus:** balancing a responsive live camera preview with full-resolution processing, keeping preview and capture visually consistent, and recovering from camera-session interruptions. Built with SwiftUI, AVFoundation, and Core Image.

For a code walkthrough, begin with [`FilmyCamera/ContentView.swift`](FilmyCamera/ContentView.swift), then explore [`FilmyCamera/Services`](FilmyCamera/Services) and [`FilmyCamera/Models`](FilmyCamera/Models). The feature and validation notes below distinguish implemented behavior from performance targets and roadmap work.

## Current product slice

- Live camera session through `AVCaptureVideoDataOutput` and `AVCapturePhotoOutput`.
- GPU-backed Core Image processing with a generated 3D color cube, dynamic range, tone curve, temperature/tint, Color Chrome, FX Blue, detail, grain, halation, and vignette stages.
- Native bi-planar YUV preview buffers when available, with a BGRA fallback, and a session-scoped grain phase shared by preview and capture for a more faithful WYSIWYG frame.
- A dedicated G7 X Compact profile and curated editable film recipes based on public Fujifilm-style controls: film base, tone curve, color, white-balance shift, dynamic range, Color Chrome, FX Blue, sharpness, noise reduction, clarity, grain, grain size, halation, and vignette.
- 758 editable looks: 595 source-linked public camera recipes, 20 neutral camera foundations, and the 143 original looks. No random combinatorial expansion.
- A 19-pack recipe manager with whole-pack and individual quick-menu controls, mixed states, search, favorites-only setup, bulk actions, and undo. All 758 looks may be active at once. Existing users retain their original quick menu; source-linked packs and Camera Foundations start hidden.
- Source sheets preserve published camera settings, original recipe names, publisher links, retrieval dates, implementation differences, and before/after samples. Source-camera settings are separate from Filmy's editable approximation.
- A cancelable 3-, 5-, or 10-second capture timer; 4:3, square, 3:2, and 16:9 framing; composition guides; and optional horizon, histogram, clipping zebras, and focus peaking. Preview aids never enter saved photos.
- Camera captures save to Photos automatically after the shutter, and a failed save keeps a retryable copy. Imported photos open a full-resolution review with Cancel or explicit Save to Photos. Reviews can keep the full photo edge to edge or add the optional white Instant Print border with its generous bottom margin.
- Try another look on an import and compare with Original before saving. Review previews are bounded to 1800 pixels, and changed looks export at full resolution on Save without changing the next shot's recipe.
- System photo picker import (Import lives in Roll) that preserves the original framing and applies the selected recipe at full resolution up to the 40 MP processing budget; larger images are resized and labeled in review.
- First-run recipe-first onboarding with a direct handoff into the camera.
- Recipe swatches apply each look to the same bundled café image, making comparisons consistent while the live viewfinder continues independently.
- Camera-first SwiftUI UI in the shape of an iPhone camera: a viewfinder on a black body that follows the chosen aspect (Fit screen by default), a top bar with flash, the Q menu, Capture setup, and Settings on one row (Smart looks, Scene Auto, and capture-format indicators sit on a line below it), Apple-style zoom presets over the frame, a bottom dock with the Roll thumbnail, the shutter, and Flip, and a row above the dock with the current look, Adjust, a favorite heart, and a Controls toggle. Controls opens a tool strip with exposure, grid, lens, Pro, and a one-tap timer. The current look opens a slim look picker (Active and Favorites, a search of every look that starts from your recent looks, Browse all, Packs, and Tune) with renderer-backed swatches that stays open after a pick. Also Liquid Glass chrome on iOS 26 (material fallback earlier), persistent tuning, a recipe detail sheet, import review, and a three-column contact-sheet Roll (two columns at large text) with a pinch-to-zoom frame viewer and an Edit look action that saves a new frame.
- Optional semantic haptics for shutter, recipe and camera selections, focus, editor commits, discards, saves, and failures.
- Flash sits at the left of the top bar and in Settings, and the last explicit choice is remembered; the G7 X profile applies a distinct whole-frame tone curve to flash frames.
- Failed starts and runtime errors reconnect with backoff, and interruptions explain the cause (background, another app, multitasking, heat). The app declares full screen only (`UIRequiresFullScreen`), so on iPadOS versions that honor the key (17 and 18; deprecated from iPadOS 26, not verified there) Split View and Slide Over are not offered; the session still enables multitasking camera access where the OS supports it and explains the interruption if one occurs. It stays warm during review and quick tab switches to reduce restart work when returning to the viewfinder.
- The film pipeline compiles off the main thread while the session configures, and photo cache maintenance runs after the first frame.
- Front/back switching (Flip, beside the shutter) and available-lens selection (in the tool strip) on iPhone and iPad, with simulator-safe preview behavior.
- Expandable Pro controls for coupled manual ISO and shutter, sensor white balance by Kelvin and tint, and manual focus on supported hardware. The panel reports applied device values, disables still flash during manual exposure, offers one Reset Auto action, and can switch from a virtual camera to an eligible physical lens when advanced controls require it.
- The live preview renders into a bounded drawable (about 1.3 MP) with a 30 fps target while stills and exports retain their full processing resolution. Sustained frame pacing and thermals require separate device measurement; isolated renderer timing does not establish camera frame rate.
- Saved photos default to Display P3 HEIF; JPEG and sRGB are selectable in Pro controls. Embedded recipe provenance metadata travels with the file.
- Simulator-safe empty state: the full interface runs without camera hardware and clearly asks for a physical iPhone or iPad for capture.
- iPad support: readable-width pages, an adaptive Roll contact sheet, and the same viewfinder chrome verified on an iPad Pro and on iPhone-size layouts.

## Fuji-style shooting controls

The camera's **Q** button opens persistent C1–C7 banks, customizable quick controls, three Auto ISO programs, digital prime cropping/lens lock, electronic/OVF-style/hybrid finders, natural live view, contrast-based split/microprism focus aids, and the Drive/BKT system. Capture tools include same-shot film/ISO/WB brackets, real exposure/RAW dynamic-range brackets, focus bracketing/stacking, computational ND, multiple exposures, preview-resolution pre-shot, and foreground interval shooting. The RAW library keeps untouched originals and editable development sidecars; failed Photos exports remain recoverable.

See [the shooting-system guide](docs/fuji-shooting-system.md) for setup, supported behavior, resolution limits, hardware requirements, and device acceptance tests. OVF-style and focusing aids are electronic interpretations, ND is temporal averaging rather than an optical filter, and sensor DR200/400 requires RAW plus real underexposure. Physical-device validation remains necessary before release.

## Build

```sh
xcodegen generate
xcodebuild -project FilmyCamera.xcodeproj \
  -scheme FilmyCamera \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

If that simulator is not installed, replace the destination with any available iPhone ID from `xcrun simctl list devices available`.

For deterministic simulator tests on CI or a busy development machine, add `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1` to the test invocation.

Run the complete test suite with `python3 scripts/testing/run.py ci --destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID'`. See [the testing guide](docs/testing.md) for unit, integration, Photos E2E, hardware, performance, coverage, and CI commands.

The app requires iOS 17 or later. Camera and Photos permissions are requested only when the relevant feature is used.

## Filmy Pro, accounts, and advertising

Dormant in Release (`FILMY_MONETIZATION_ENABLED = NO`; enabled only in Debug builds): the monetized candidate adds a 10-photo daily free tier, three starter looks, native monthly App Store subscriptions with an eligible one-month trial, optional Apple/Google sign-in, and AdMob banners outside the camera. Trial and paid access unlock Pro and remove ads. Existing saved images remain accessible. No watermark is added.

The product target is an exceptional film-simulation and G7X-inspired camera with additional capture and editing tools in a premium monthly subscription. Price, trial duration, and the exact feature split remain open. See the [premium camera vision](docs/premium-camera-vision.md) for the staged feature and quality targets and the [monetization roadmap](docs/monetization-roadmap.md) for future access and export proposals. Subscription restrictions and watermarking are not enabled in the current launch; RAW capture/development is now implemented in the Q shooting system with hardware validation pending; general HDR output remains roadmap work.
Production activation still requires App Store Connect products, Firebase provider configuration, AdMob publisher IDs/consent messages, and reviewed legal disclosures. The shipping Release build starts no purchases, accounts or ads and never gates capture or save; a monetized Release needs the steps in docs/monetization.md and docs/app-store/monetized-release.md. See the [implementation and setup guide](docs/monetization.md) and [monetized release checklist](docs/app-store/monetized-release.md). The [older roadmap](docs/monetization-roadmap.md) is historical; RAW/HDR and other capabilities are not implied by the new paywall.

## Rendering note

The recipe controls intentionally model the public vocabulary used by Fujifilm cameras, but this app is not affiliated with Fujifilm and does not ship Fujifilm firmware, LUTs, or proprietary calibration data. Exact camera output varies by sensor generation, exposure, white balance, and lighting; the bundled recipes are transparent, adjustable interpretations rather than claims of identical hardware output.

## Research

See [docs/research.md](docs/research.md) for the open-source architecture review and the rendering decisions used here.

## Recipe packs and fidelity

Open the camera's look picker (tap the current look above the shutter), then **Packs**. Open a pack to choose individual looks, or use **Actions > Enable all 758 looks**. Hiding a look does not change the current capture, delete edits, or remove favorites. **Browse all** and import review retain the full catalog.

See [the catalog and fidelity audit](docs/recipe-library-and-fidelity.md), [the 128-row original-look audit, covering 128 of the 143 originals](docs/original-recipe-audit.csv), and [the machine-readable source audit](docs/recipe-catalog-audit.json). The rendering tests check operational consistency, not a measured match to camera JPEGs.

## Smart looks

The Smart looks control above the viewfinder offers on-device, scene-aware recipe suggestions.
Tap **Use** beside it to apply the leading recommendation, or tap **Smart looks** to compare
three renders of the same frame, pick a Style (Natural, Vivid, Cinema, or B&W), and apply a look
with one tap. Undo restores the previous look unless you have since chosen another manually.
Suggestions never select a recipe or save a photo automatically. Toggle analysis off in the Smart looks sheet.

The engine combines Apple Vision scene/face detection with light, contrast, and color measurements
and ranks the actual available recipes, including edited controls. It uses bounded, throttled
background work, pauses for capture and heat, and never uploads image data. These are aesthetic
starting points, not a guarantee of the best filter. See [the implementation and device-validation
notes](docs/smart-recipes.md).

## Pro capture and persistent originals

Capability-gated resolution, RAW/ProRAW, HEIF/P3, HDR highlight preservation,
original Live Photos (audio is off by default and opt-in), exposure priority, focus aids and a persistent
non-destructive photo library are documented in
[Pro camera features and limitations](docs/PRO_CAMERA_FEATURES.md).
