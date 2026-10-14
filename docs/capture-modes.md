# Capture modes workspace

The **Capture modes** entry opens a separate workspace while preserving the existing camera, recipe renderer, editor, and Roll. The app entry point, exclusive camera handoff, microphone/camera/Photos permissions, and checked-in Xcode target membership are committed. Open the checked-in project normally; the integration script is not a required manual setup step.

This is an implementation toward camera-feature parity, not a claim of complete Halide or stock iOS Camera parity. Native iOS compilation, XCTest, and physical-device acceptance remain release gates. Portable policy tests and syntax parsing are not substitutes for those gates.

## Features and limits

| Feature | Implementation | Important limit |
| --- | --- | --- |
| Burst | Hold/release or accessible tap-to-start/stop, sequential AVCapturePhotoOutput capture, speed prioritization, 40-frame cap, individually developed files | No advertised fixed frame rate or native Photos burst-group identifier |
| Macro | Autofocusing ultra-wide, verified minimum focus distance, near-focus restriction where supported | No digital-zoom substitute on fixed-focus hardware |
| Portrait/depth | Native depth-bearing HEIC, f/4 center-subject depth blur, auxiliary metadata retained when pixel geometry is unchanged | Center-subject bokeh, not adjustable refocus, Apple's Portrait Lighting, or universal depth support |
| Camera Control | AVCaptureEventInteraction shutter handling, native zoom/EV controls, mode/film pickers, focus slider where capacity permits, all presentation delegate callbacks, CameraCaptureIntent launch | Workspace integration, not a LockedCameraCapture extension; locked launch can require unlocking. Hardware control-count limits can omit lower-priority controls |
| 4K Film Video | Native 4K/30 where supported, explicitly labeled 1080p fallback, optional audio, existing FilmRenderer applied after recording, original movie retained | SDR film export, optical/unfiltered live preview, three-minute clip cap, no background-rendering guarantee |
| Filmy Night | Eight native photos, AE/AF/WB lock and restoration, translational registration, motion-aware temporal blending before the film look | At least three accepted frames, up to 2560-pixel long edge; movement and shake can fail. Not Apple's sensor-level Night pipeline |
| Panorama | Up to 12 overlapping photos, pairwise homography, accumulated perspective mapping, feathering, crop and geometry/memory guards | Experimental short left-to-right sweeps, 1536-pixel input long edge, 24 MP / 12000-pixel width budget; not cylindrical 180/360-degree stitching |
| Spatial content | Native spatial movie capture on a supported dual-wide format, stabilization/discomfort warnings, stereo metadata preserved | Spatial video only, not spatial stills; intentionally unfiltered to avoid flattening stereo |
| Siri / scene assistance | App Shortcuts open photo/Night/video/macro, general mode intent, explicit on-device Vision OCR/barcodes/image labels, confirmation before opening HTTP(S) codes | No private Apple Visual Intelligence service, general LLM, silent capture, or automatic code execution |
| Reference image | Bounded Photos Picker import, persistent onion-skin or split comparison, opacity/mirror/scale/replace/remove | Composition guide only, never burned into output. Filmy does not upload references; OS backup settings still apply |

## Workspace layout

- Top bar: **Back** (`capture-modes-back`) returns to the camera; **Captures** (`open-mode-captures`) opens the library. The navigation bar is hidden. Captures shows how many captures the library holds, including ones still processing or failed (hidden at zero, capped at 99+; VoiceOver reads "Captures" and the exact count).
- Mode chips (`capture-mode-<mode>`) sit under the viewfinder. Modes this device cannot run collapse into one line: `Not on this device: <reason>` for one mode, or `Not on this device: <titles>. About this mode lists why.` for several.
- The essentials sit above the shutter: the film picker button, then a chip row in this order: zoom (when the lens range is wider than one step), Exposure, microphone (video modes), Reference image, About this mode. Spatial video has no film, zoom or exposure control; the line under the viewfinder says it is saved as shot with no film look, and its processing status reads "Saving the spatial video as shot." Zoom and Exposure swap the chip row for an inline slider; the film button does not move.
- **Reference image** replaces the mode chips and the essentials row with a tray: choose, onion-skin or split, opacity, mirror, scale, replace, remove. Done returns to the chips. The viewfinder keeps at least 200 pt while the tray is open.
- At accessibility text sizes the page scrolls (`capture-modes-scroll`) and the shutter stays on screen.
- Left of the shutter, the last-capture slot (`capture-modes-last-capture`) shows the newest capture as a 56 pt thumbnail and opens it in Captures. While recording or capturing a sequence, the slot shows the clock or the frame count instead.
- After a shot, a card over the bottom of the viewfinder (`capture-modes-saved-card`) says "Saved in Captures" and offers View (opens that capture), Export to Photos and Close. A new shot or a mode change clears it. Once the capture is exported, the card dismisses itself after 4 s, unless VoiceOver or Switch Control is running.
- **Captures** rows show a 64 pt thumbnail (the developed file, else the first original; frame 0 for movies), the mode, the date, file counts and one Photos status in words: In Photos, Partly in Photos (an interrupted export), or Not in Photos. At accessibility sizes the thumbnail stacks above the text. Detail share rows are numbered ("Share photo 1", "Share video 1", "Share original 1"), not named by file. Rows open their detail by capture id, so the card and the last-capture slot can open Captures on one capture; a capture deleted meanwhile shows "Capture not found".

## Storage, privacy, and recovery

`Application Support/FilmyCaptures/<UUID>/` contains original encoded captures, a recipe snapshot, a capture manifest, and developed output. Originals and metadata are saved before processing. Sequences allow only one photo in flight and have hard frame limits. Night and panorama materialize accumulators between frames instead of retaining an unbounded Core Image graph.

**Captures** provides sharing, retry processing, explicit Photos export, and confirmed local deletion. Processing or authorization failure does not delete originals. Nonempty movie files found after an interrupted manifest update are recovery candidates only: the processor verifies a finalized playable video track and positive duration, and spatial recovery also requires a stereo multiview track. It does not label a 2D or unfinished movie as spatial. A file the OS had not finished writing at termination may be unrecoverable.

PhotoKit receives encoded HEIC/movie resources directly, without moving local sources. Confirmed Photos identifiers are persisted per output so ordinary retries skip completed exports. A crash between Photos committing an asset and the app persisting its receipt can still cause a duplicate on retry; check Photos after a termination. Local deletion does not delete assets already exported to Photos.

Camera and microphone stop when the app moves to the background, when the Capture Modes screen disappears, and on a camera interruption or critical thermal state. A brief inactive phase such as Control Center, a notification banner or a system alert keeps the session, a recording and processing running. A critical thermal or runtime-error stop persists until the user reopens a mode or the app returns from the background. Processing cancellation retains originals for an explicit retry. Recording does not silently restart on return. The old and new capture sessions use an acknowledged serial-queue handoff rather than a fixed delay. Handoff is blocked while the legacy view model is capturing, saving, importing, or reviewing a photo.

Microphone permission is requested only for audio-enabled video. Denial produces an explicit silent-recording label. Hardware shutter events and native controls are disabled under modal UI, permissions, and processing. Scene text and codes remain untrusted data, with no automatic external action.

## Build and validation

The integration job has committed the app/service/permission changes and all 12 app sources plus both XCTest files into the checked-in native targets. It uses the Xcode project parser on an Ubuntu runner, avoiding a dependency on the macOS build queue. It never force-pushes or modifies main, and it does not change signing credentials.

`project.yml` also discovers the source directories. The dedicated native validation job selects the latest installed Xcode, regenerates with XcodeGen, builds the app and test targets, and runs the two new test suites on an available iPhone simulator. Its actual result determines native CI status. The preexisting source uses iOS 26 APIs, requiring a compatible SDK despite the iOS 17 deployment target.

Local authoring checks actually completed:

- Foundation-only policy executable: **399 assertions passed**. Covers every sequence limit, one-in-flight behavior, cancellation, wrong/duplicate callbacks, macro eligibility, geometry budgets, unsafe URLs, filenames, export receipts, and manifest round trips.
- Swift frontend syntax parsing of all new app and test files passed. This is not SDK typechecking.
- Integration-script anchor, permission, and idempotence checks passed.
- Added **11 policy XCTest cases and 11 processing/persistence XCTest cases**, including invalid input, thumbnail/reference bounds, identity registration, stationary-panorama rejection, durable manifests, and unfinished-movie rejection. These require the native test run; adding tests does not mean they have executed successfully.

To rerun portable checks or deliberately regenerate the project:

```sh
bash scripts/test-capture-modes-policy.sh
python3 scripts/integrate_capture_modes.py
xcodegen generate
```

## Physical-device release gates

1. Verify actual close focus on an autofocus ultra-wide and the unavailable state on unsupported hardware. Verify native depth, correct orientation, exported auxiliary metadata, and center-subject blur on supported rear/TrueDepth configurations.
2. Exercise Camera Control press/hold/release, every exposed slider/picker, expanded controls, foreground CameraCaptureIntent launch, and suppression under sheets, alerts, permissions, and backgrounding.
3. Verify 4K/fallback dimensions, frame rate, orientation, film appearance, audio synchronization, silent/denied audio, three-minute stop, low storage, calls, and backgrounding during recording and export. Confirm originals survive failures.
4. Compare Night against its original on a tripod and handheld, including moving subjects. Test panorama texture, parallax, stationary frames, reverse movement, low light, excessive sweep, and cancellation. Inspect actual noise, ghosting, perspective, seams, crop, and transparent edges, not just successful encoding.
5. Verify spatial files contain both views and calibration metadata and play spatially on a compatible viewer. Verify unsupported devices and ordinary 2D files are never represented as spatial captures.
6. Exercise denied/partial Photos export, interrupted processing and relaunch, sharing, confirmed local deletion, iCloud reference import/cancel/replace, VoiceOver, large text, and the existing portrait-orientation UI. Verify references never appear in output.

These physical-device gates have not been certified in the Linux authoring environment. Do not market the branch as complete camera-quality parity before completing them.

## Public API references

- https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control
- https://developer.apple.com/documentation/avkit/avcaptureeventinteraction
- https://developer.apple.com/documentation/avfoundation/avcapturesessioncontrolsdelegate
- https://developer.apple.com/videos/play/wwdc2024/10166/
- https://developer.apple.com/documentation/appintents/cameracaptureintent
- https://developer.apple.com/documentation/vision/vnimagehomographicalignmentobservation
- https://developer.apple.com/documentation/avfoundation/capturing-photos-with-depth
- https://developer.apple.com/documentation/avfoundation/reading-multiview-3d-video-files
