# Capture modes workspace

This change adds an explicit **Capture modes** entry below the existing app surface.
The original camera, film recipes, photo editor, and Roll remain separate. The new
workspace retains its own capture originals and shares the existing `FilmRenderer`.
It is not a claim of complete Halide or stock iOS Camera parity.

## Features and limits

| Feature | Implementation | Important limit |
| --- | --- | --- |
| Burst | Hold/release or accessible tap-to-start/stop; sequential AVCapturePhotoOutput capture, speed prioritization, 40-frame cap; individually developed files | No advertised fixed frame rate or native Photos burst-group identifier |
| Macro | Dedicated autofocusing ultra-wide, verified minimum focus distance, near-focus restriction where supported | No digital-zoom substitute on fixed-focus hardware |
| Portrait/depth | Real depth delivery, embedded original HEIC depth, f/4 center-subject depth blur, auxiliary metadata retained in unchanged pixel geometry | Center-subject bokeh, not adjustable refocus, Apple's Portrait Lighting, or a universal depth-capable camera |
| Camera Control | AVCaptureEventInteraction shutter handling, native zoom and exposure controls, mode/film pickers, focus slider when capacity permits, all presentation delegate callbacks; CameraCaptureIntent launch | Workspace integration, not a LockedCameraCapture extension; locked launch can require unlocking. Device control-count limits can omit lower-priority controls |
| 4K Film Video | Native 4K/30 where supported; explicitly labeled 1080p fallback; optional audio; existing film renderer applied after recording, with original movie retained | SDR film export, optical/unfiltered live preview, three-minute clip cap, no background rendering guarantee |
| Filmy Night | Eight native photos, AE/AF/WB lock and restoration, translational registration, motion-aware temporal blend in linear working space before film processing | At least three accepted frames; up to 2560-pixel long edge; moving subjects, exposure drift, and large shake can fail. Not Apple's sensor-level Night pipeline |
| Panorama | Up to 12 overlapping photos, pairwise homography, accumulated perspective mapping, overlap feathering and vertical crop; size and motion guards | Experimental short left-to-right sweeps, 1536-pixel input long edge, 24 MP / 12000-pixel width budget; not a cylindrical 180/360-degree panorama |
| Spatial content | Native spatial movie capture on a supported dual-wide format, stabilization and discomfort warnings, stereo metadata preserved end to end | Spatial video, not spatial still photography; deliberately not run through a flattening monocular film export |
| Siri / scene assistance | App Shortcuts open photo, Night, video, or macro; general mode intent; on-device Vision OCR, barcode recognition and image labels; confirmation before opening HTTP(S) codes | No private Apple Visual Intelligence access, general LLM, automatic purchases, silent capture, or automatic code execution |
| Reference image | Photos Picker import, bounded decoding, persistent onion-skin or split comparison, opacity, mirror, scale, replace/remove | Composition guide only; never burned into output. Filmy does not upload it; normal OS backup settings still apply |

## Storage and failure handling

`Application Support/FilmyCaptures/<UUID>/` contains original encoded captures, a
recipe snapshot, a capture manifest, and developed output. Originals and metadata
are saved before processing. Capture counts are bounded and only one photo is in
flight; full-resolution image arrays are not retained during sequences. Night and
panorama materialize the accumulator between frames rather than retaining an
unbounded Core Image graph.

The **Captures** view provides file sharing, retry processing, explicit Photos
export, and confirmed local deletion. A failed processing or Photos operation does
not delete originals. Completed movie files can be rediscovered after an interrupted
manifest update. A file that the OS had not finished writing at termination may be
unrecoverable. A malformed manifest is not a reason to hide other valid captures.

Photos export passes the encoded HEIC/movie resource directly to PhotoKit and does
not move the local source. Confirmed Photos identifiers are persisted per output,
so ordinary retries skip completed exports. There remains a crash window between
Photos committing an asset and the app persisting its receipt; check Photos before
retrying after a termination to avoid duplicates. Local deletion does not delete
assets already exported to Photos.

Camera and microphone use stop when the scene is inactive. Processing cancellation
retains source files for an explicit retry. Interrupted operation does not silently
resume recording. The old and new camera sessions use an acknowledged serial-queue
handoff instead of a fixed delay. Microphone permission is requested only for an
audio-enabled video mode; a denied microphone results in a clearly labeled silent
recording, not a false audio indicator.

The workspace intentionally uses an optical preview. Filmy color is developed
after capture. Spatial content stays native and unfiltered to preserve both eyes and
calibration metadata.

## Build and validation

The normal checked-in Xcode project must include `FilmyCamera/CaptureModes` and both
new test files. `project.yml` already scans these source directories. The scoped CI
integration job applies the small app/service/permission changes, runs XcodeGen,
and commits the generated project to `feature/advanced-capture-modes`, never main.
After that integration commit, opening the checked-in project is sufficient.

To regenerate manually:

```sh
python3 scripts/integrate_capture_modes.py
xcodegen generate
bash scripts/test-capture-modes-policy.sh
```

The Foundation-only policy suite runs on Linux or macOS. During authoring it passed
399 assertions covering all sequence limits, one-in-flight behavior, cancellation,
wrong/duplicate callbacks, macro eligibility, geometry budgets, unsafe URLs, filename
traversal, export receipts and manifest round trips. Swift frontend parsing was also
run. Neither is an iOS SDK typecheck or a hardware acceptance test.

`CaptureModesPolicyTests` and `CaptureModesProcessingTests` add XCTest coverage for
policy, malformed input, thumbnail/reference bounds, identity registration, rejecting
stationary "panoramas," and durable media manifests. The dedicated CI workflow builds
app and test targets with the latest installed Xcode and runs these suites on an
available iPhone simulator. Its result, not this document, determines native CI status.
The preexisting source uses iOS 26 APIs, so a compatible SDK is required even though
the deployment target remains iOS 17.

## Device acceptance before release

1. On a device with an autofocus ultra-wide, verify actual near focus versus Photo;
   on unsupported hardware verify an actionable unavailable state. On rear dual and
   front TrueDepth configurations confirm the original and exported HEIC contain
   usable depth, correct orientation and center-subject blur.
2. Test Camera Control full press, hold/release in Burst, every exposed slider/picker,
   expanded UI, and no shutter under sheets, alerts, permissions or backgrounding.
   Launch the CameraCaptureIntent from the system's supported Camera quick action.
3. Record 4K and fallback video with audio on/off/denied, verify dimensions, frame rate,
   orientation, sound synchronization and the actual selected film transform. Test a
   three-minute stop, low storage, an incoming call, and app backgrounding during both
   capture and film export. Confirm originals survive every failure.
4. Compare Night against one original on a tripod and handheld, then introduce moving
   subjects. For panorama test a textured distant scene, parallax, a repeated still,
   reversed movement, low light, an extreme sweep and cancellation at every frame.
   Inspect seams, transparent edges, perspective, crop, noise and ghosting rather than
   treating a successfully encoded file as proof of quality.
5. Record spatial video in landscape on supported hardware; verify the exported file
   still contains both views and spatial metadata and plays spatially on a compatible
   viewer. Confirm the UI never labels an ordinary 2D movie as spatial.
6. Deny Photos export, retry a partially exported burst, relaunch after interruption,
   share originals, and delete only the local capture after explicit confirmation.
   Import/cancel/replace references from iCloud, rotate with the existing portrait UI,
   test VoiceOver and large text, and verify no reference appears in output.

These device gates have not been certified by the local Linux authoring environment.
Do not market this branch as stock-camera quality or complete parity without them.

## Public API references

- Apple, Camera Control integration: https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control
- Apple, capture events: https://developer.apple.com/documentation/avkit/avcaptureeventinteraction
- Apple, controls delegate: https://developer.apple.com/documentation/avfoundation/avcapturesessioncontrolsdelegate
- Apple, native spatial capture: https://developer.apple.com/videos/play/wwdc2024/10166/
- Apple, CameraCaptureIntent: https://developer.apple.com/documentation/appintents/cameracaptureintent
- Apple, Vision homographic alignment: https://developer.apple.com/documentation/vision/vnimagehomographicalignmentobservation
- Apple, depth photo capture: https://developer.apple.com/documentation/avfoundation/capturing-photos-with-depth
