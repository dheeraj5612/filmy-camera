# Camera capability and catalog expansion

This is a feature implementation in PR 90, not a claim of complete competitor parity. Start from `fed817aaca1c389c62db6c1105cae0e164c58e74`, preserving the merged Pro controls, Instant Print, visual library, cancellable imports and explicit save flow. Use exact-commit hosted results for current acceptance.

## Implemented in this pass

| Capability | Behavior and boundary |
| --- | --- |
| Self-timer | Off, 3, 5 or 10 seconds; monotonic deadlines; single operation identity; cancel stays reachable. Leaving the active camera, opening another destination, importing or interruption invalidates the countdown. Capture eligibility is rechecked before firing. No automatic photo saving. |
| Aspect ratios | Existing Fit screen plus exact 4:3, square, 3:2 and 16:9 framing. Preview geometry feeds the existing full-resolution capture crop; shutter waits for the requested viewport. Portrait/landscape reciprocals are tested. Imports preserve their own aspect; Instant Print remains a separate finish. |
| Composition | Thirds, golden-section, centered square and crosshair guides; optional gravity-based horizon level. Motion updates stop offscreen and near-flat device orientation does not report a false level. |
| Exposure assistance | 64-bin luminance histogram, highlighted clipping percentage and zebra mask over the unfiltered display-referred preview. Not RAW clipping measurement, finished-grade histogram or exposure recovery. |
| Focus assistance | Red local-contrast edges from the preview. This is a downsampled aid, not depth estimation, calibrated focus confirmation or a focus loupe. |
| Hardware shutter | Public AVKit/SwiftUI camera-capture event handling on supported iOS versions, routed through the same eligibility/countdown path. No private volume interception, silent-shutter hack or custom Camera Control focus/zoom menu. Hardware behavior still needs physical-device acceptance. |
| Expanded discovery | 128 looks, including the unchanged original 36. Library search includes collection names; filters distinguish negative, slide, cinema, instant color, digital, experimental and monochrome. Existing stable IDs, favorites and customized controls remain usable. |

### Preview resource limits

The assist consumer uses the existing immutable frame callback, never a second capture session. Its largest analysis dimension is 192 pixels, and it admits at most one frame every 0.25 seconds with only one operation in flight. GPU work is off the main actor. Cancellation uses generations so stale work cannot repopulate a new session; canceled GPU work must drain before another starts. Transparent masks use premultiplied color. No guides enter the renderer or encoder. Aids detach when the camera is hidden, inactive, unavailable, capturing or presenting modal tools. The optional level uses 10 Hz device motion and does not save or upload samples. These bounds are design limits, not measured power/thermal guarantees.

## Original creative catalog

The 92 new treatments comprise 16 color negatives, 10 slides, 12 cinema grades, 8 instant-color looks, 16 digital-camera-inspired styles, 6 experimental colors and 24 monochrome/toned looks. Examples include Portrait 160/400/800, Chrome 50/100, Tungsten 500, Cream Square, CCD Daylight/Twilight, Pocket Positive/Negative, Rangefinder Color, Mirrorless Clean, Silver 100/400/1600, red/yellow/green filter monochromes and warm/cool print tones.

These are explicit original parametric designs. Their provenance is `originalCreativeDesign` and calibration is `notCalibratedToCameraHardware`, retained in edited recipes and exported JPEG metadata. They are not manufacturer LUTs, measured sensor emulations, reproduced copyrighted recipes, literal ISO settings, RAW modes, long exposures or proof of matching a commercial film. The digital styles do not invoke the G7 X-specific face/flash treatment. New neutral monochromes disable colored halation rather than acquiring an unintended red cast. Existing 36 recipes and renderer version remain unchanged.

## Competitor audit and remaining gaps

Primary sources checked September 9, 2026:

- [Apple Camera tools](https://support.apple.com/en-mide/guide/iphone/iph3dc593597/ios): timer, aspect, grid/level and exposure/focus reference.
- [Halide](https://halide.cam/): manual controls, Process Zero, film Looks, RAW import, peaking and focus loupe. Filmy's recipes do not reproduce Process Zero or Halide's proprietary processing.
- [ProShot iOS guide](https://www.riseupgames.com/proshot/ios): photo/video/slow-motion/time-lapse/light-painting modes, ratios, manual controls, peaking, histogram, formats and bracketing.
- [ProCamera feature overview](https://www.procamera-app.com/en/features/): RAW capture/editing, exposure bracketing, intervalometer, perspective correction, video and remote tools.
- [Apple camera capture controls session](https://developer.apple.com/videos/play/wwdc2025/253/): public shutter-event integration and distinction from custom camera controls.

Manual ISO/shutter/focus/white balance, lenses, AE/AF locking, import, favorites, photo review and Instant Print existed before this pass and are preserved, not counted as new. Remaining substantive modes include RAW/ProRAW acquisition and paired resource persistence; Live Photos; depth/Portrait; multi-frame night/HDR; video, slow motion, ProRes/Log and audio; panorama stitching; bursts, exposure bracketing and interval capture; long-exposure accumulation; independent metering/focus points and a focus loupe; exposure presets; QR scanning; perspective/anamorphic correction; and lock-screen/Watch/extensions integration. None has a decorative nonfunctional toggle here.

Implement each remaining mode with a real capability query, resource/save model, interruption behavior and physical-device tests before advertising it. No collection of color recipes constitutes these capture capabilities.

## Test coverage and acceptance

Routine app tests add 128 concrete recipe-render cases, six catalog/provenance/discovery/persistence cases, fifteen timer/geometry/analysis/layout cases and two setup/new-camera-style UI cases. Each recipe executes the production pipeline at both preview and photo quality on a color/grayscale chart, the bundled public-safe cafe sample, and an underexposed sample: 768 render paths. Photo outputs also exercise JPEG encoding, dimensions, metadata round-trip and location stripping. Every case retains a three-panel contact sheet. Missing fixtures fail instead of silently skipping. Small fixtures establish rendering/export correctness, not full-resolution performance or visual fidelity under all real scenes.

The dedicated pinned-Xcode catalog lane requires all 149 selected core cases with zero failures/skips, exports the actual rendered sheets and retains source/toolchain evidence. Routine CI still includes all tests, existing normal Photos flows and generated-project checks. Phone/tablet screenshot acceptance also exercises the new setup and digital style. Five portable contract checks prevent a recipe definition or fixture from losing its always-on render case.

The initial pre-hosted checkpoint passed 64 Python tests and eleven Foundation XCTest policy methods on Linux; all 128 model definitions validated/round-tripped with unique original control signatures using a Color-only stub module, and changed Swift files syntax-parsed. Those checks did not establish iOS SDK typechecking or rendering. Review fixes increased portable coverage to 66 passing tests. Final iOS results and signed-release evidence belong in the PR and downloadable exact-commit artifacts.

Still required on actual devices: hardware shutter press/release behavior, camera interruption just before timer completion, lens changes, portrait/landscape capture-crop parity, edge-overlay registration, gravity calibration, VoiceOver, peak memory and sustained thermals. Consult the [release checklist](release-checklist.md) for current archive, upload and submission gates. Full competitor equivalence is not claimed.
