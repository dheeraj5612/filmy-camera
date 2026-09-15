# Pro capture and persistent originals

This change extends the existing photo pipeline. It does not claim blanket parity
with Halide, the system Camera app, or every camera on iOS 27.

## Feature contract

| Request | Implemented behavior | Boundary |
| --- | --- | --- |
| Variable aperture | Runtime format min/max discovery, continuous optical f-number control, public iOS 27 `setExposureModeCustom(lensAperture:duration:iso:completionHandler:)`, validated exposure combinations | Requires an iOS 27 SDK build, iOS 27 and a supported variable-aperture lens. Older builds/lenses show a read-only f-number. Selecting aperture holds shutter/ISO; priority modes retain aperture. Returning to auto releases all exposure locks. Physical hardware acceptance remains required. |
| 12 / 24 / 48 MP | Capability-gated exact sensor-dimension requests, actual output dimensions in the project, no upscaling | 24 MP is an explicitly labeled downsample from a 48 MP request, **not** Apple's deferred 24 MP fusion. RAW Bayer, custom exposure and Live Photos request 12 MP. Cropping and device processing can lower final resolution. Native 12.2 / 48.8 MP sizes are not needlessly resampled. |
| Shutter / ISO priority | Fix one parameter and adjust the other with the device exposure meter, damped 250 ms feedback, deadband, bounds and limit indication | App-managed custom exposure, not a native AVFoundation priority mode. Available only on a supporting lens. Stops on auto/manual override, AE/AF lock, session stop and reset. |
| Focus loupe | 2x / 4x live preview crop around the selected point or tracked subject | Does not change optical zoom or capture pixels. Preview-resolution aid, not a sensor-resolution still magnifier. |
| Subject focus tracking | Vision object tracking seeded by a tap, or largest detected face; confidence/loss gating and AF-only movement | No subject identification, face recognition, cross-occlusion reacquisition or guaranteed sports-camera performance. Manual focus and AE/AF lock take precedence. |
| ProRAW / Bayer DNG | Public-format negotiation, paired processed + RAW callbacks, exact DNG byte retention and export | Bayer requires native device zoom 1 and quality `.speed`. Unsupported formats are not offered. Film editing uses the processed companion, not a full RAW-development engine. |
| HEIF / P3 | Actual HEVC HEIF with Display P3 ICC profile and matching EXIF color-space declaration | JPEG remains the compatible sRGB default. Wide-gamut encoding is not itself HDR. |
| Persistent non-destructive photos | Original byte hashes, full recipe/settings snapshot, versioned rendition manifests, relaunch/reopen/edit/revert, thumbnails and confirmed deletion | New camera captures only. Existing Photos items cannot retroactively recover discarded originals. Stored in Application Support, not an evictable cache. |
| HDR | Preserve source HDR highlight headroom through an extended, half-float render context; generate a new gain map for the edited SDR/HDR pair | iOS 18+ HEIF only. SDR sources remain SDR, and instant-print composition is SDR. This is not a new multi-frame exposure-fusion capture algorithm or a guarantee that every capture contains HDR. |
| Live Photos | Actual capture movie callback, byte-preserved still/movie pairing, Photos export and in-app `PHLivePhotoView` playback | **Silent original Live Photo**, deliberately without microphone permission. The Filmy still is separately edited/exported. No falsely paired filtered still or promise of film-filtered motion. RAW / manual exposure combinations are disabled. |

## SDK selection

XcodeGen enables `FILMY_IOS27_CAMERA_APIS` for `iphoneos27*` and
`iphonesimulator27*` SDKs only. Build with Xcode 27 to include optical control.
The same sources still compile against Xcode 16.4 / 26.3 without pretending those
older SDKs offer aperture control. Future SDK major versions must extend these
explicit build conditions after their API contracts are reviewed.

## Entry points

Camera tools -> manual controls -> Capture format / Exposure priority / Focus aids.
Roll -> **Filmy originals · edit again** -> project -> choose recipe, codec and
finish -> **Save edit**. Revert restores the capture-time recipe, not a mutated
original. The editor displays the saved rendition until changes are committed.

RAW/Live capture saves an unmodified original asset in Photos plus the separate
Filmy-rendered still. Ordinary captures retain their original locally and export
the Filmy still. Original DNG files can also be shared directly from the project.

## Durability, concurrency and failure behavior

- Capture callbacks are correlated by unique capture ID and aggregated until the
  terminal `didFinishCaptureFor` callback. Processed, RAW and movie callbacks may
  arrive in different orders. Partial RAW/Live captures are not reported complete.
- The temporary movie has explicit ownership; canceled/late callbacks are cleaned
  up and successful movies remain alive until copied to the persistent project.
- Originals are written before development. A staged project is atomically renamed
  only after all originals and the initial manifest have been written.
- SHA-256 checks catch changed or corrupt retained resources. Filename validation
  prevents a manifest from addressing files outside its project.
- Each edit writes a new rendition and thumbnail before atomically advancing the
  manifest. Optimistic revision checks reject stale edits after suspension.
  Original files are never overwritten by an edit or a revert.
- Failed persistence/export is surfaced for retry. If both rendering and initial
  persistence fail, source bytes are kept in memory with explicit Retry / Discard.
  A process termination or device failure can still lose memory-only bytes.
- A crash before staged-directory commit may leave an incomplete hidden staging
  directory; it is excluded from the roll, not automatically promoted or deleted.
- Photos denial does not delete the local project. Original export records the
  Photos identifier for ordinary retries. A crash after Photos commits but before
  that identifier is saved can still create a duplicate on retry.
- Originals preserve camera metadata, including any location metadata present in
  the source. Filmy output uses the existing metadata allowlist. Sharing originals
  shares their metadata. Projects can consume substantial device storage, may be
  included in device backups, and are removed when the app is deleted. There is no
  hidden quota eviction, cloud synchronization or automatic deletion of originals.

## Validation

New suites: `ProCapturePolicyTests`, `FilmyPhotoStoreTests`, `ProPhotoEncoderTests`.
They cover the capability combination matrix, callback ordering/partial captures,
priority convergence/limits, tracking-coordinate geometry, byte retention across
relaunch and edits, stale revisions, malformed manifests, movie ownership,
metadata/P3 encoding and genuine gain-map output from a synthetic HDR source.
Registered with `scripts/testing/suites.json` so standard lanes discover them.

Run the existing repository test harness as well as the focused suites. Regenerate
the committed Xcode project with the repository's pinned XcodeGen 2.45.4 whenever
source files change. Swift parsing alone is not an Apple SDK build or a device test.

### Physical-device acceptance required before release

Test a non-Pro phone, a ProRAW/48 MP phone, all rear lenses and the front camera.
Check custom exposure on supported physical lenses, scene brightness steps, and
lens changes while capturing. Compare requested versus resolved dimensions, DNG
opening and byte hashes, Photos denied/limited/add-only states, low storage,
interruption/backgrounding, repeated saves and relaunch/revert. Capture, export
and play a silent Live Photo in both Filmy and Photos. Verify P3 metadata and HDR
headroom on an HDR display, with SDR and print fallbacks. Test tracking on moving
subjects, occlusion, camera rotation, mirroring, zoom and manual-focus overrides.

## Public API references

- [Apple: Implement high resolution photo capture](https://developer.apple.com/videos/play/wwdc2026/304/)
- [AVCaptureDevice.lensAperture](https://developer.apple.com/documentation/avfoundation/avcapturedevice/lensaperture)
- [Capturing photos in RAW and Apple ProRAW formats](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats)
- [AVCapturePhotoCaptureDelegate](https://developer.apple.com/documentation/avfoundation/avcapturephotocapturedelegate)
- [CIImageRepresentationOption.hdrImage](https://developer.apple.com/documentation/coreimage/ciimagerepresentationoption/hdrimage)

- [iOS 27 custom exposure support queries](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/supportsexposuremodecustom(lensaperture:duration:iso:))
- [iOS 27 optical aperture custom exposure](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(lensaperture:duration:iso:completionhandler:))
- [Minimum optical aperture](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/minlensaperture)
