# Runtime performance and hardening pass

Audit base: `3d1428ec8497ad6b3836db256cb75145828f5add` (main, September 14, 2026).

## Implemented changes

| Path | Finding | Change and bound |
| --- | --- | --- |
| Local Roll decoding | Each cache miss launched an independent detached decode. Cancellation could return the obsolete image. | `ImageDecodeQueue` admits at most two concurrent blocking decodes on an OperationQueue. Cancelled queued jobs skip decoding; cancellation resumes the caller immediately and drops an in-flight result. Resource identity and cache generation are rechecked after awaiting. |
| PhotoKit image requests | Degraded-only or stalled iCloud requests had no terminal deadline. A cancellation before registration still started native work. | Exactly-once continuation state now declines cancelled registration, cancels the native request even if its ID arrives late, and has a 30-second deadline. A degraded fallback may be displayed after timeout but is never cached as a final image. |
| Preview lifecycle | Lifecycle observers were test-only. Detached/background views could retain a camera buffer and drawable. Drawable acquisition preceded cheap eligibility checks. | Production observers discard frames/drawables on inactivity, memory warning, and window removal. No new GPU submission while inactive or detached. The one-command-buffer gate survives resource purges. Per-frame autorelease scope and no extra box on the normal main-thread delivery path. |
| Preview dimensions | The minimum 1x drawable scale defeated the pixel budget on very large point-sized displays. Nonfinite sizes were not rejected. | Shared numeric admission precedes allocations/conversions. Preview dimensions are floored, at most 1.3 million pixels and 4,096 pixels per edge; sub-1x scales are permitted. |
| Imported photos | The 40 MP limit was applied to a CI source after decode; very thin panoramas could exceed texture edge limits without exceeding the area limit. | Encoded dimensions are inspected with ImageIO caching disabled. Oversized images are downsampled before entering the film graph. Area stays at 40 MP and the longest edge at 16,384 pixels. Normal imports retain the existing CI decoding/orientation path. Review output-size/full-resolution reporting uses the same policy. |
| Capture completion | A missing AVFoundation/manual-control callback could leave the shutter busy indefinitely. | Session-queue watchdog: 15 seconds for deferred manual controls; 30 to 120 seconds for capture depending on exposure. Token-guarded cancellation rejects old timers. Timeout fails the pending capture once and uses existing bounded session recovery, never automatically repeats the shutter. |
| Cache maintenance | An eviction result identified only the asset ID, allowing an old pass to remove the index entry for a newly saved replacement. Attribute read errors were treated as missing files. | Snapshot after prior maintenance completes; apply removals only when generation and filename still match. Keep mappings on protected-data/permission/transient I/O failures. Byte arithmetic avoids addition overflow. |
| Recipe thumbnails | Unchecked floating-point to integer conversion and arbitrary dimensions could crash/allocate excessively. Disk PNGs were lazily decoded without validating dimensions. | Reject invalid sizes; bound to a 1,024-pixel edge. Cache digest and render use the same normalized dimensions. Validate disk entry type, encoded bytes, and expected dimensions before immediate ImageIO decode. Recreate an OS-purged cache directory on write. |
| Cache pressure | Reproducible renderer/Roll/swatch caches had no explicit coordinated pressure response. Disk swatches had only an entry-count policy. | Purge in-memory LUT, thumbnail, swatch, and CIContext caches on memory warning. Roll invalidation also rejects old request completions. Disk thumbnail eviction targets 32 MiB and 240 entries, with a 5 MiB per-entry cap. Eviction is best-effort on filesystem errors. |

## Preserved behavior

No film transform, recipe catalog, renderer version, JPEG quality, export metadata allowlist, capture resolution preference, release version, signing identity, or App Store settings are changed. Existing Photos originals and saved recipe metadata are never deleted by cache pressure handling. Ordinary imports below both size limits retain their original decode path. Changes to oversized imports intentionally trade maximum dimensions for bounded processing.

## Verification

New suites are registered in `scripts/testing/suites.json` and included in the generated Xcode project:

- `ImageSizePolicyTests`: dimension/budget edge cases, overflow-sized inputs, protected-file errors, stale eviction identity.
- `ImageDecodeQueueTests`: off-main execution, two-worker admission, cancellation before registration, queued cancellation, in-flight cancellation, failed decode, and 300-request completion/cancellation races.
- `RuntimeHardeningTests`: PhotoKit timeout state, lifecycle frame release, strict drawable limits, malformed thumbnail/import rejection, cache purge behavior, EXIF rotation, long-edge panorama preparation, and finite capture deadlines.

Local evidence: 18 tests run against the exact portable production Swift files passed with Swift 6.2.1 on Linux. The existing Python test-runner suite passed 74 tests. Swift parsing is a syntax check, not an iOS SDK build. Native build/test evidence is recorded in the pull request and GitHub Actions artifacts.

### Native validation commands

Use the repository-pinned XcodeGen 2.45.4 and the existing CI Xcode 16.4 compatibility lane. Regenerate the project, build test products, then run `python3 scripts/testing/run.py core` on an available iPhone simulator. The normal PR gates additionally exercise UI, Photos, and Release/device compilation.

For a focused simulator check after building, run `xcodebuild test-without-building` for `ImageSizePolicyTests`, `ImageDecodeQueueTests`, `RuntimeHardeningTests`, `PhotoLibraryMetadataTests`, `CameraViewModelRenderingTests`, `CameraServiceAvailabilityTests`, `RendererOutputBoundsTests`, `PhotoOutputEncoderTests`, and `PhotoPrintCompositorTests`.

## Device validation still required

Simulator tests do not establish camera throughput, battery savings, peak device memory, or real PhotoKit network behavior. Before release, run the existing opt-in `RendererPerformanceTests` (`FILMY_RUN_PERF=1`) on the same physical phone before/after this branch, using identical scenes and recipes. Record cold/warm launch, preview frame-time distribution, dropped-frame counters, resident memory, and energy impact. Also exercise rapid Roll scrolling, repeated recipe changes, background/foreground during capture, locked-device cache access, limited Photos revocation, offline iCloud, and repeated large panorama imports.

A blocking ImageIO call cannot be preempted once it starts; the two-worker bound and result cancellation limit its impact. A watchdog on the session queue cannot rescue an AVFoundation call that blocks that same queue indefinitely. Photo saving/sharing still uses Apple's transaction APIs and should be device-tested under storage pressure. No device-level speedup or crash-free guarantee is claimed by this pass.

## Primary API references

- [Apple: Handling Frame Drops with AVCaptureVideoDataOutput (TN2445)](https://developer.apple.com/library/archive/technotes/tn2445/_index.html)
- [Apple: MTKView releaseDrawables](https://developer.apple.com/documentation/metalkit/mtkview/releasedrawables())
- [Apple: Image and Graphics Best Practices, WWDC 2018](https://developer.apple.com/videos/play/wwdc2018/219/)
- [Apple: CGImageSourceShouldCache](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcache)
- [Apple: CIContext clearCaches](https://developer.apple.com/documentation/coreimage/cicontext/clearcaches())
