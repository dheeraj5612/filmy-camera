# Performance pass — build 8

This pass removes duplicate CPU, GPU, image decoding, and persistence work. The film transforms, 32-cube resolution, 1.3 MP viewfinder budget, JPEG output, framing, and 40 MP import safety budget are unchanged.

| Path | Change |
| --- | --- |
| Startup | Warm the selected recipe with its persisted custom controls; resolve the warmup recipe off the main thread. |
| Live camera | Submit one preview command buffer at a time and redraw the newest frame after completion. Drop pending frames on pause. Skip invisible preview bookkeeping. |
| Camera controls | Avoid repeated exposure configuration locks during capability refresh and equal-value SwiftUI publications. Preserve FIFO zoom/capture ordering. |
| Look drawer | Serialize swatch rendering on a utility-priority actor. Cancelled SwiftUI requests skip work before rendering; temporary render objects are released after each swatch. |
| Capture/import | Reuse one synchronized face detector and one geometric subject mask per still. Propagate import cancellation to the render task and check between expensive stages. |
| Save | Return after the Photos commit and local-cache attempt; optional album organization continues afterward. Fallback JPEG encoding runs off the main actor. |
| Roll | Reuse decoded thumbnails with an 80-entry/48 MiB cache budget. Full-size detail images bypass the cache. Memoize the decoded local index and sorted gallery; avoid a duplicate directory scan. |
| Reliability | Revision/permission-aware thumbnail keys, cache-generation checks, and final-success-only Photos caching preserve retries and invalidation. Detail retries cancel when the view leaves. |

## Validation

- Local iOS 18.5 simulator regression: 176 unit tests, 10 opt-in/hardware skips, no failures; four selected camera, recipe, navigation, and lifecycle UI tests passed.
- Cache policy tests cover nonfinite/oversized requests, asset revisions, degraded fallback versus final success, and cancellation. Import cancellation/retry and customized startup warmup are covered.
- The opt-in performance harness now includes the actual production drawable budget, nine full-resolution 12 MP imports, and fresh versus reused face detection. Run with `TEST_RUNNER_FILMY_RUN_PERF=1` and `-only-testing:FilmyCameraTests/RendererPerformanceTests`.
- Final cache tests and import/detector benchmarks passed in `build/performance-20260904/benchmarks-and-cache.xcresult` (local, ignored). The subsequent preview stress test in that batch exited with signal 11 and no usable stack. Both an isolated rerun and the full three-benchmark rerun passed without an app change. The benchmark now drains temporary objects after every completed render, checks command-buffer completion, and logs each case. The original failure is retained as an unresolved diagnostic, not assigned to a proven cause.
- Project and App Store metadata/media preflights passed. Required hosted checks are tracked on the pull request.

## Measurements and limits

The physical iPhone 16 Pro baseline used the Apple A18 Pro GPU. G7 X took 9.8 ms at 834×1112 and 16.7 ms at 1206×1610 in the existing warmed synchronous renderer benchmark. These sizes are not the production drawable budget. The phone locked before the final comparison; final on-device frame pacing, battery use, capture/save latency, and peak memory remain unmeasured.

The iOS 18.5 simulator completed nine 12 MP imports without changing their full-resolution status or 4:3 framing. G7 X import-to-review samples were 881, 405, and 378 ms. Fresh/reused face-detector medians were 10.34/9.37 ms on that simulator. These are development-machine observations, not iPhone speedup claims.

A proposed opaque-input shortcut was rejected after two recipes differed on iOS 18.5, despite passing a physical iPhone comparison. The shipped alpha-preserving pipeline remains intact. One-buffer live-preview pacing still requires an unlocked-device acceptance pass; offline renderer timings do not establish that result.

Detector reuse follows [Apple’s CIDetector guidance](https://developer.apple.com/documentation/coreimage/cidetector). No arbitrary image-quality reductions were introduced.
