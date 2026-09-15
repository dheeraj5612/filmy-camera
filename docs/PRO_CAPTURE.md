# Pro capture and persistent originals

## Find the controls

Open **Pro** from the camera utility rail. Capture format, requested resolution, output color, HDR, Live Photo, exposure programs, aperture and focus aids are grouped above the existing manual controls. Unsupported hardware options are disabled with explanations. A lens change does not silently rewrite a user's RAW or resolution preference.

Open **Roll > Filmy originals · edit again** to compare the original, preview another recipe, save an immutable version, restore settings from history, update the linked Photos asset, export a separate copy, or share the original DNG. Captures continue to save automatically; the new editor is not a mandatory post-shutter step.

## Feature matrix

| Requested feature | Implementation and boundary |
| --- | --- |
| Variable aperture | Public iOS 27 release-SDK custom exposure API, format-level support checks, actual aperture readback. Requires a supported lens and a build with the release APIs. Fixed-aperture lenses expose read-only f-number. No simulated aperture blur or model-name allowlist. |
| 12 / 24 / 48 MP | Requests supported sensor dimensions. 24 MP is downsampled from a 48 MP capture; it is not Apple's deferred 24 MP fusion. The original is retained at capture resolution. Aspect-ratio cropping and scene-dependent camera behavior can reduce delivered pixels. No upscaling. |
| Shutter and ISO Priority | Native custom exposure tuples fix the selected parameter and leave the other automatic. iOS 27 release SDK, runtime availability and per-format tuple support are all required. Older builds retain full Manual. Manual and priority captures currently require 12 MP so speed prioritization can honor exposure settings. |
| Focus loupe | Opt-in 4x unfiltered preview crop around the selected point, clamped to source bounds. It assists focusing but is not a full-resolution sensor readout. |
| Subject tracking | Tap-to-select native continuous AF tracking when available. Otherwise on-device Vision tracks the tapped detection or patch and updates focus. Confidence loss requires a new tap rather than jumping to another person. Manual focus and AE/AF lock stop tracking. |
| ProRAW / DNG | Capability-checked RAW plus processed companion capture. Both resources are assembled before capture completion and retained unchanged. DNG sharing is available. Filmy development currently uses the processed companion, not a RAW demosaic editor. |
| HEIF / wide color | Explicit HEIF or JPEG encoding with selected sRGB / Display P3 output profile. Device wide-color capture is enabled where supported. Exported metadata reflects the encoded profile. |
| Persistent, nondestructive photos | Atomic Application Support documents, immutable original resources, full recipe settings per revision, retained renditions, optimistic edit conflict checks, and reversible PhotoKit adjustment data. Independent of the purgeable Roll cache and Photos permission. |
| HDR | Half-float rendering, captured HDR/SDR highlight-headroom reconstruction after the film transform, and 10-bit PQ HEIF export. Does not fabricate HDR from SDR or copy a stale gain map onto newly graded pixels. This is not a reproduction of Apple's proprietary multi-frame Smart HDR. Editing thumbnails/previews remain SDR. |
| Live Photos | Complete still + movie collection, optional microphone permission, original pairing retention, and PhotoKit editing of both still and video frames with the film look. Currently 12 MP, SDR, Photo finish, and no RAW. Filtered playback is in Photos; the original can also play in Filmy. |

## Data and failure behavior

Documents live under `Library/Application Support/FilmyPhotos/<UUID>/`. Resources include `original.jpg` or `original.heic`, optional `original.dng` / `original.mov`, an atomic `document.json`, versioned renditions and regenerable thumbnails. File protection is enabled. Original metadata is preserved; sharing originals may share their original location metadata. Newly developed output uses the existing metadata allowlist.

A complete capture is copied to a staging directory before that directory is atomically published. An export or render failure leaves the durable original available. If retaining the original fails because storage is full, Filmy keeps that capture in memory for a shutter-tap retry and explicitly asks the user to keep the app open. This is not protection against force quit or device loss before a successful disk write.

New still exports use add-only Photos access when possible. Editing existing assets and Live Photo editing require read/write access. A created Photos original is linked before a later edit failure is reported, so retry targets the same asset. Foreign Photos edits are not silently overwritten. Explicitly exporting a new copy preserves that other app's work.

Deleting a Filmy document requires confirmation and leaves its Photos exports alone. Deleting the app deletes the private document store. This feature is not a cloud backup, and old flattened Roll exports cannot recover originals that were never retained.

## SDK builds

Deployment remains iOS 17. Xcode 16.4 / 26.x build the compatibility path. `FILMY_IOS27_SDK` enables the new public controls only in iOS 27 SDK builds, and every call is additionally runtime-gated.

**Xcode 27 beta 6 does not contain the later release camera declarations.** A beta-only validation run must pass `FILMY_SDK_CONDITIONS=` to compile the compatibility path and must not be reported as validating aperture or native priority. Use the iOS 27 release SDK for those controls. The checked-in project is generated from `project.yml`; regenerate with `xcodegen generate` after adding sources.

Typical focused validation:

```sh
xcodegen generate
xcodebuild -project FilmyCamera.xcodeproj -scheme FilmyCamera \
  -destination 'platform=iOS Simulator,id=<AVAILABLE_SIMULATOR_UUID>' \
  -only-testing:FilmyCameraTests/ProCaptureTests \
  -only-testing:FilmyCameraTests/CameraManualControlsTests \
  -only-testing:FilmyCameraTests/PhotoOutputEncoderTests \
  CODE_SIGNING_ALLOWED=NO test
python3 -m unittest discover -s scripts/testing -p 'test_*.py'
```

`ProCaptureTests` covers resolution policy, all format combinations, preference decoding, capture assembly, focus coordinates/loupe bounds, tracking selection, atomic resource retention, immutable versions/conflicts, P3 output, captured highlight headroom and HEIF bit depth. A simulator without a HEIF encoder explicitly skips the encoder case; that is not a device pass.

## Physical-device release checklist

Do not claim Halide or stock Camera parity solely from simulator compilation.

1. On an iOS 27 release-SDK build and a variable-aperture lens, verify every supported aperture, applied f-number, shutter/ISO priority in changing light, unsupported tuples, frame-duration behavior, and 12 MP capture metadata. Repeat on a fixed-aperture lens and older OS to verify unavailable states.
2. Capture 12 / 24 / 48 MP on supported rear lenses and on front/tele/ultrawide lenses. Inspect decoded dimensions and orientation, verify the 24 MP derivation label, and verify explicit rejection of unsupported RAW/resolution combinations.
3. Capture Bayer RAW and ProRAW. Open DNGs in an independent RAW reader, verify processed companions, force-quit/relaunch after a completed capture, clear the Roll cache, and confirm original bytes survive multiple edits.
4. Photograph a wide-gamut target and a bright-window HDR scene. Inspect HEIF bit depth / ICC profile, compare SDR and HDR on an EDR display, and confirm SDR-only source data does not gain artificial highlight brightness. Check thermal and memory behavior at 48 MP.
5. Capture moving subjects as Live Photos, with audio off/on and microphone denied. Check original and edited pairing, motion/audio, orientation, still/movie look consistency, Photos revert-to-original, and repeated export without unintended duplicates.
6. Exercise tracking at all four edges, mirrored front camera, lens switches, rotation, lost/occluded subjects, manual focus, AE/AF lock, interruptions and recovery. Verify the loupe and tracking do not stall preview delivery.
7. Exercise Photos denied, add-only, limited and full authorization; missing linked assets; third-party Photos edits; storage exhaustion during original/revision/export writes; backgrounding; cancellation; and explicit original deletion. Record real device / OS / SDK / source SHA with results.

## Primary API references

- [Custom exposure with aperture](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(lensaperture:duration:iso:completionhandler:))
- [Exposure support per capture format](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/supportsexposuremodecustom(lensaperture:duration:iso:))
- [Implement high-resolution photo capture, WWDC26](https://developer.apple.com/videos/play/wwdc2026/304/)
- [Capture photos in RAW and Apple ProRAW formats](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats)
- [PHLivePhotoEditingContext](https://developer.apple.com/documentation/photos/phlivephotoeditingcontext)
- [HEIF 10-bit representation](https://developer.apple.com/documentation/coreimage/cicontext/heif10representation(of:colorspace:options:))
