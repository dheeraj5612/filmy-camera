# Fuji-style shooting system

Open **Q** in the camera's top bar. Ordinary Single-frame shooting remains on the existing capture path unless RAW, Auto ISO, a digital crop, pre-shot, or another drive mode requires the sequence coordinator. This is an independent implementation of publicly documented shooting concepts, not Fujifilm firmware, sensor calibration, or an exact-camera-output claim.

## Controls and behavior

| Feature | Implemented behavior | Boundaries |
| --- | --- | --- |
| C1–C7 | Seven named, explicit-save banks containing the complete recipe, shooting settings, active camera/lens, zoom, exposure/ISO/shutter, WB/focus, flash preference, framing, timer, and print finish. Recall does not silently overwrite a bank. | An unavailable saved lens is an error. Device values are limited to its supported ranges. |
| Film Simulation BKT | One real sensor capture, developed with three selected recipes and exported as three photos. | Not three different moments. Choose the recipes in BKT settings. |
| Auto ISO 1/2/3 | Three persistent editable profiles with base ISO, ISO ceiling, preferred minimum shutter, and optional reciprocal focal-length/motion rule. Closed-loop metering changes real shutter and ISO. | At the ISO ceiling, the shutter can get slower. Sensor custom exposure support is required. |
| Computational ND | A fixed-exposure sequence of 2, 4, 8, 16, or 32 still frames; linear-light temporal averaging produces a longer-exposure motion effect. | Not an optical ND filter; cannot prevent clipping within each frame. Gaps between stills are possible. Tripod recommended. Composite limited to 6 MP. |
| Hybrid finder | Electronic preview, natural wide-context OVF-style preview with crop bright lines, or the latter plus a processed-crop inset. | All views are electronic. A phone cannot become an optical finder. |
| Digital prime | Shared center crop at 1×, 1.4×, 2×, or 3× for preview, saved image, tap-focus mapping, and composition aids. Optional physical-lens lock prevents automatic lens substitutions and zoom changes. | Cropped sensor pixels, not additional optical resolution or upscaling. |
| Q Menu | Reorder, remove, and add the 16 available controls; layout persists. All Controls remains reachable when the grid is empty. | Changes are locked during capture/assembly. |
| Split image / microprism | Magnified monochrome focus patch with contrast-dependent split displacement or alternating prism tiles, relative-contrast readout, reference reset, and manual lens-position control. | Contrast-based visual aids, not sensor phase-detection measurements or a guarantee of correct focus. |
| Multiple exposure | 2–9 deliberately composed shutter presses; prior-layer ghost overlay; average, additive, bright, or dark blending; cancel/discard and optional source retention. | Settings freeze at the first layer. Composite limited to 6 MP. |
| Pre-shot | A bounded rolling buffer of owned preview images; exports preceding frames plus the normal still using their original timestamps. | 0–1.5 seconds, at most 16 frames / 32 MB / 768-pixel longest edge. Single-frame only, no RAW/DR. Not full-resolution sensor pre-capture or half-press hardware. |
| Capture DR100/200/400 | DR200/400 request actual −1/−2 EV sensor exposure, retain RAW, verify captured EXIF exposure against the request, restore midtones in RAW linear-space development, and compress highlights. DR BKT takes three separate sensor exposures. | Requires RAW plus custom exposure on the selected lens. Rejects unattainable exposure; never labels an ordinary JPEG tone edit as protected RAW. This is separate from a recipe's legacy Dynamic Range aesthetic. |
| Natural Live View | Bypasses the film recipe for the viewfinder only. | Saved images still use the selected recipe. It does not undo sensor exposure, sensor WB, or the phone's ISP preview processing. |
| Focus stack | Explicit near/far endpoints, settle delay and 2–20 real lens-position captures, translation registration, and per-pixel local-sharpness fusion. Source frames may be retained. | Tripod/static subject. No full breathing, parallax, rotation, or moving-subject correction. Rejects excessive translation. Composite limited to 6 MP. |
| Drive/BKT | Single, bounded Continuous Low/High, AE 3/5/7/9 frames with selectable order and spacing, same-source ISO/WB/film BKT, three-exposure DR BKT, focus BKT/stack, ND, multiple exposure, foreground interval shooting, and the existing self-timer. | High means fastest sequential still delivery, not a guaranteed FPS. ISO BKT is same-source exposure development, not different sensor noise. WB BKT is a temperature-axis variant. Intervals are start-to-start without catch-up bursts; no background scheduling. |
| RAW development | Capture Bayer RAW or Apple ProRAW when exposed by the lens; retain untouched files, import supported RAW files, edit exposure/as-shot or custom WB/highlight shoulder/shadows plus the full film recipe, preview, persist edit sidecars, export JPEG, and share the untouched source. | Decoder support comes from Core Image. Originals up to 200 MB / 100 MP; development bounded to 40 MP, interactive preview to 1200 pixels. RAW capture conservatively requests the smallest supported still dimensions. Photos export is SDR JPEG; this does not implement a general HDR exporter. |

## Safety, concurrency, and ownership

- `CameraService` owns AVFoundation on its existing serial session queue. A capture lease excludes ordinary capture, camera/lens changes, and competing manual changes. Sensor configuration completion handlers are awaited before each exposure; photo completion waits for the final native callback and both RAW/JPEG payloads when requested.
- Capture requests snapshot settings/recipes. Captures are written to disk before expensive development. Only metadata grows with sequence length, not a RAM array of full-resolution images. Composite processing is serialized and materialized between frames to keep filter graphs bounded.
- Every native callback, cancellation, timeout, and interruption races through an exactly-once completion gate. Leases restore prior exposure, focus, WB mode, monitoring, and frame-duration configuration; cancellation waits for restoration. A failed restoration is surfaced instead of silently reporting success.
- All advanced-coordinator captures use flash **Off**. The remembered ordinary-camera flash preference is restored. Auto ISO and manual exposure must not fight each other; turn off Auto ISO before using the ordinary manual exposure panel.
- Background/tab changes, memory warnings, and critical thermal state cancel active sequences and clear preview buffers. Interval capture deliberately requires foreground operation and temporarily keeps the screen awake.
- Preview aids never enter exported photos. The pre-shot sampler copies scaled images instead of holding camera-owned pixel buffers. Its queue allows one frame in flight and does not create a second live display layer.
- Originals and pending rendered JPEGs are atomically persisted under Application Support, with manifests written last. Failed Photos exports remain in the outbox with a Retry action. Successfully exported temporary processed originals are removed unless composite-source retention is enabled; RAW originals remain until explicitly deleted. App deletion removes this local library: share important originals first.

## Source layout

`FilmyCamera/Shooting` contains persistent settings and exposure/drive planning, the RAW/original/outbox actor, native photo delegates, linear image processing, bounded preview sampling, the sequence controller, Q/bank configuration, RAW development UI, and viewfinder/status overlays. The existing camera service, screen, preview, and assist store have small integration hooks. New files are included by `project.yml`; regenerate the checked-in Xcode project whenever adding a source.

## Automated validation

`FujiShootingTests` is registered in the integration test suite. It covers all drive plans, same-source vs sensor brackets, Auto ISO policy, exposure bounds, persistence/recovery, pre-shot bounds/timestamps, exactly-once completion, crop geometry, rejecting fake RAW/DR, linear development/compositing, focus-fusion ties, original/outbox recovery, sequencing, restoration before Photos writes, and save-failure retention.

```sh
xcodegen generate --spec project.yml
xcodebuild -project FilmyCamera.xcodeproj -scheme FilmyCamera \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FilmyCameraTests/FujiShootingTests test CODE_SIGNING_ALLOWED=NO
```

Syntax parsing and model-only tests do not establish native camera behavior. The PR's build/test checks are the record of which native checks actually ran. No physical iPhone camera was available during implementation; the following checks remain required before release.

## Physical-device acceptance checklist

1. Supported Bayer RAW and ProRAW lenses plus an unsupported front/virtual lens: capture/import/reopen, original-byte identity, EXIF orientation, flash-off policy, and explicit unsupported-state messages.
2. Manual exposure, focus, WB, flash, lens lock, and C1–C7: switch away/back, restore on success/error/background/timeout, and verify device readback values rather than labels alone.
3. A fixed high-contrast scene on a tripod: inspect RAW EXIF and histogram at DR100/200/400 for −1/−2 EV capture, shadow-noise tradeoffs, highlight retention, color, and development midtone accuracy. Do not claim extra dynamic range from already clipped input or proprietary-ISP equivalence.
4. An exposure ramp: verify three Auto ISO ceilings/shutter preferences, reciprocal rule, cadence, no oscillation, and handoff to manual exposure. Verify new OS versions do not silently ignore custom controls.
5. Focus ruler/static near/far scene: inspect every original for distinct focus, then fused regions, registration direction, borders, breathing artifacts, and rejection on excessive movement. Compare to simple whole-frame selection to confirm local fusion actually adds detail.
6. Moving water/light trails: evaluate ND sampling gaps, stable brightness, composite fidelity and heat at all frame counts. Compare multiple-exposure blend modes and ghost crop alignment.
7. Pre-shot: compare original frame times to shutter time, verify buffer clearing on lens/recipe/framing/background changes, inspect preview-resolution labeling, and measure live-preview pacing/memory.
8. Deny Photos permission and force disk errors/interruption: retry without losing pending bytes or originals, relaunch the app, discard partial assemblies, and check that UI controls cannot deadlock the camera.
9. VoiceOver, largest Dynamic Type, iPhone/iPad layouts: Q, bank confirmation, reorder/remove, all-control recovery, progress cancellation, RAW sidecars, and unchanged ordinary capture/roll/import flows.

## Primary references

- [Fujifilm X100VI shooting settings](https://fujifilm-dsc.com/en/manual/x100vi/menu_shooting/shooting_setting/index.html): Auto ISO profiles, bracketing, multiple exposure, digital teleconverter and pre-shot vocabulary.
- [Apple RAW and ProRAW capture](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats): hardware capability discovery and paired capture.
- [CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter) and [linear-space filter](https://developer.apple.com/documentation/coreimage/cirawfilter/linearspacefilter): genuine RAW development before display rendering.
- [Photo dimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions): device-supported per-photo dimensions.
