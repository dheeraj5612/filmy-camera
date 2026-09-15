# Fuji-inspired shooting system

Open **Q**, enable **Shooting system**, and choose a drive mode. Off preserves the original camera workflow. No network service, credentials, subscription, or proprietary Fujifilm LUT is used.

## Implemented paths and boundaries

| Control | Implementation | Boundary |
| --- | --- | --- |
| C1–C7 | Seven named persistent banks, full customized recipe, shooting settings, physical-lens identity, exposure/WB/focus, zoom, flash, timer, aspect and finish; copy and recall | Recall on the same lens; hardware still validates applied values |
| Film BKT | One camera original developed with up to three selected recipes | Independent approximations, not proprietary Fuji conversions |
| Auto ISO 1/2/3 | Three persisted min/max ISO and preferred-minimum-shutter profiles; bounded metering feedback | Needs custom exposure; device limits override profile; minimum shutter can relax at max ISO |
| Computational ND | Half-float linear-light temporal averaging, bounded preview copies, measured frame count and elapsed span | Up to 8 samples/s, 1280 px; not an ND filter or continuous shutter; cannot recover clipped highlights |
| Hybrid finder | Natural electronic feed and developed inset; OVF-style frame lines | No optical path, parallax measurement, or image beyond the sensor |
| Digital prime | Fixed 1.4x, 2x, 3x crop in preview and capture; matching focus coordinates; pinch disabled | Relative to existing lens/zoom, no upsampling or claimed optical resolution |
| Q menu | Up to 16 persistent, reorderable/removable slots; all controls remain reachable | Accessible labeled buttons; disabled during a sequence |
| Focus aids | Magnified live/reference split comparison and local-contrast microprism-style view | No fabricated phase or defocus-direction measurement |
| Multiple exposure | Separate shutter presses, 2–9 sources, average/additive/bright/dark blend, onion skin and retake | 4096 px composite; additive highlights can clip; originals retained |
| Pre-shot | Age- and count-bounded copied preview ring followed by a full-resolution still | Up to 12 frames / 2 seconds, 1280 px, up to 8 samples/s, not RAW pre-capture |
| DR100/200/400 | DR200/400 shorten RAW exposure 1/2 stops at the metered ISO, verify EXIF and develop with matching linear sensor-domain shoulder | Requires RAW + custom exposure; phone sensor behavior is not Fuji calibration; shadow-noise tradeoff |
| Natural live view | Bypass film renderer in live preview only | Camera ISP processing still applies; captured recipe is unchanged |
| Focus stack | Real actuator sweep, local sharpness selection with feathered masks, immutable source retention | Tripod/stationary subjects; no registration or focus-breathing correction; inspect seams; 4096 px output |
| Drive/BKT | Single, CL, CH, AE/ISO/film/WB/DR/focus BKT, focus merge, multiple exposure, pre-shot, temporal average, interval | Bounded counts, sequential still completion; no guaranteed FPS; interval is pause after completion |
| RAW development | Native CIRAWFilter decode, push/pull, as-shot/manual WB, tint, RAW sharpness/noise reduction, film recipe, tone, original sharing and JPEG export | Original DNG immutable; edits in JSON sidecar; not Fujifilm's proprietary RAW converter |

## Safety and lifecycle

`FujiCaptureBridge` borrows CameraService's serial session queue, device and photo output. Only one lease and photo callback can be active. Ordinary capture and lens/zoom/manual-control mutations are blocked during that lease. Exposure and focus completion handlers are awaited before capture. State restoration is also serialized. Timeout forces session recovery instead of admitting overlapping captures.

Preview retention owns CGImages, not AVFoundation pool buffers. Backgrounding, camera changes and memory warnings clear transient previews. Cancellation propagates to development workers. Every accepted still is archived before development or Photos export. Export failures leave an original available for explicit retry. The on-device archive has a 2 GB budget; reaching it fails rather than silently deleting photographs. The library is app-container storage, not a substitute for a backup; use Share unchanged original before removing the app.

`DR200/400` is distinct from the legacy recipe's rendering-only DR intent. The capture path requires real RAW, takes a shorter verified shutter exposure at constant ISO, disables RAW decoder baseline/boost/local tone mapping for this path, and applies a shadow-gain/highlight-shoulder function in `CIRAWFilter.linearSpaceFilter`. The legacy recipe DR stage is set to DR100 to avoid applying a second DR treatment. DR cannot be reassigned to a previously captured JPEG.

## Validation

`FujiShootingTests` covers defaults, profile solving and sensor bounds, serialization, corrupt preference backup, bracket ordering, one-original film/WB BKT, interval bounds, pre-shot eviction, crop geometry, linear-light blend values, linear RAW shoulder values, no JPEG-as-RAW fallback, immutable originals and archive quota. Hardware behavior still requires physical-device acceptance; simulator tests cannot certify RAW availability, exposure readback, focus motor timing, actual burst rate, thermal behavior, optical equivalence, or visual Fuji matching.

### Physical-device acceptance checklist

- Standard shooting with system off: capture, flash, manual controls, gallery and background/resume unchanged.
- Each supported physical rear lens: inspect RAW/custom-exposure/focus capabilities; reject unsupported modes with actionable text.
- DR target: fixed illumination, DR100/200/400 DNGs show approximately 1x/0.5x/0.25x exposure duration and stable ISO; inspect highlight and shadow ramps after development.
- AE and ISO BKT: independent EXIF values, distinct exposures, original controls restored; repeat cancellation and interruption during each callback phase.
- CL/CH: no concurrent photos, accurate frame count; interval remains foreground-only.
- Focus sweep: near/far endpoints, motor movement, original focus restored; inspect stack seams and breathing on stationary macro subjects.
- Pre-shot and ND: frame timestamps/elapsed span match actual sampled frames, app memory stays bounded, no stale buffers after backgrounding or changing lenses.
- Multiple exposure: all four blend modes, onion skin, retake, cancellation and Photos permission failures.
- RAW editor: preserve original bytes across edit/export, share DNG, delete confirmation, full-library error, relaunch persistence.
- VoiceOver, largest Dynamic Type, portrait iPad, Q reorder, bank recall and lens mismatch.

## API and behavior references

- [Apple RAW and ProRAW capture](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats)
- [Apple CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter)
- [Apple custom exposure](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(duration:iso:completionhandler:))
- [Apple manual focus completion](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setfocusmodelocked(lensposition:completionhandler:))
- [Fujifilm X-T5 image-quality controls](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/)

Fuji minimum-ISO thresholds depend on the Fuji sensor generation and are not copied onto unrelated iPhone sensors. Camera capability checks, actual exposure metadata and explicit limitations take precedence over feature labels.
