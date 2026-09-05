# Premium camera vision

Product direction confirmed September 5, 2026: build a camera people choose over Halide for film simulations and the G7X compact-camera look, with advanced photographic controls included in a premium monthly subscription. This is a development target, not a claim that the current app outperforms Halide or reproduces a camera sensor exactly.

The everyday flow should stay simple: open the camera, choose a look, shoot, and keep a beautiful image. Experienced photographers should be able to take control without switching apps. Monthly premium should include the full collection and shipped advanced tools; the proposed model has no separate charge for each recipe pack. Price and trial duration remain undecided. Free/trial access and watermark behavior are specified in the [monetization roadmap](monetization-roadmap.md).

## Competitive baseline

Reviewed official Lux documentation on September 5, 2026. This is a documented feature comparison, not a hands-on quality test.

| Published Halide capability | Consequence for Filmy |
| --- | --- |
| Mark III includes film Looks, configurable grain/halation, HDR output, and a RAW Photo Lab with exposure, framing, and white-balance editing | Having filters or changing a look after capture is already expected. Our advantage must come from the character, consistency, and ease of our results. |
| Manual exposure includes shutter and ISO priority; the product site describes manual focus, peaking, and a focus loupe | True manual capture and useful measurement aids belong in the premium roadmap. A filter's temperature slider is not sensor white-balance control. |
| Version 3.1 adds perspective correction, rotation/flip, compression controls, and optional RAW-only capture | Persistent editing and flexible export are substantial capabilities to build deliberately. |

Sources: [Halide Mark III, May 27, 2026](https://www.lux.camera/halide-mark-iii/), [Halide product capabilities](https://halide.cam/), [Halide 3.1, July 7, 2026](https://www.lux.camera/halide-3-1-scarlet-edition/). Availability and combinations must be checked on each supported device; these sources do not establish that every feature works in every Halide mode.

## What should make Filmy worth choosing

1. **A signature G7X result.** Develop and evaluate compact-digital color, highlight roll-off, skin rendering, texture, and the balance between a flash-lit subject and its surroundings. Keep this family grain-free by default. Separate actual flash capture from a stylistic simulation; a filter cannot create missing illumination or reproduce a larger sensor and lens.
2. **Film recipes with intent.** Organize a curated selection by photographic use and visual character. Give each a recognizable identity across skin tones, daylight, mixed light, night, and monochrome scenes. Offer restrained and expressive strengths while preserving skin detail and highlight shape. More visible effects are welcome when the photograph benefits.
3. **Control that follows the photographer.** Keep the selected look, exposure, lens, and shutter easy to reach. Reveal advanced controls on demand, keep active manual settings visible, and provide a single obvious return to Auto. The user's current choice should survive routine navigation without an unexplained hardware reset.
4. **A personal camera.** Add named shooting presets combining recipe, supported capture settings, and export preferences. Distinguish creative recipe values from device-dependent camera settings when moving between iPhone, iPad, and lenses.
5. **A useful digital negative.** Eventually retain an original with versioned edits so premium users can revisit a photograph, compare looks, and export several interpretations. Make storage use and deletion understandable. The current Roll stores flattened JPEGs; this requires new persistence, not just another editor screen.

These are areas in which to earn a preference, not verified claims that competing apps lack them.

## Staged premium scope

Stages are ordered by dependency and value. They are not dates or promises that unfinished features are available to subscribers.

| Stage | Scope | Completion gate |
| --- | --- | --- |
| A — Finish the core camera | G7X and film quality; reliable capture/import/review/save/share; responsive iPhone/iPad UI; physical lens and lifecycle validation | Clear the existing release/device gates and complete matched real-scene evaluations. |
| B — First premium candidate | Monthly StoreKit subscription, full-access introductory trial, free watermarking; full recipe collection and tuning; true ISO/shutter/manual focus/capture white balance with Auto; histogram, highlight clipping aid, focus peaking/loupe; saved shooting presets | Real controls agree with capture metadata and supported hardware. Purchase, expiry, offline use, restores, and all export paths pass acceptance. Advertise only tools actually delivered. |
| C — RAW and persistent editing | RAW/ProRAW where supported; optional original plus rendered output; versioned non-destructive edits; exposure/WB recovery, crop/straighten, before/after; format/resolution choices and clean re-export | Verify capture-mode compatibility per device/lens, retained-source durability, bounded storage, migrations, and pixel/metadata correctness. Preset rendering must use a defined RAW development path. |
| D — Extend the photographic workflow | Several looks from one retained capture, bounded batch recipe application, recipe import/export, HDR editing/export, priority exposure modes, and native quick-launch/camera controls where supported | Validate demand and prototype cost. Measure each capability on device before adding it to the paid feature list. |
| E — Research candidates | Exposure/film bracketing, multi-frame low-light or long-exposure capture, depth-assisted local edits, and compatible external-camera RAW workflows | Separate motion/alignment, ghosting, color, latency, memory, and hardware studies. Promote only experiments that improve real photographs. |

Stages B–E are proposed premium scope. Monthly billing and the film/G7X focus are confirmed; individual advanced features and their exact release grouping remain prioritization decisions. RAW, HDR, resolution, flash, and lens capabilities must follow actual hardware support. Do not expose controls that imply unsupported aperture, optical zoom, flash power, or processing choices.

The current app already has EV compensation, point focus, AE/AF lock, lens selection, live film rendering, recipe tuning, and review look comparison. Those are foundations; they do not establish full manual exposure, sensor white balance, RAW capture, or durable non-destructive editing.

## UX contract

- **Shoot:** an uncluttered viewfinder with reachable shutter, current look, lens, and exposure. Put Pro controls in a consistent expandable panel; preserve the live frame while operating it. Avoid covering faces or the focal target with purchase prompts.
- **Choose a look:** favorites and a small curated first view, previews from the same scene, and a plain-language description. Keep technical recipe details one level deeper. Compare strength and variants without losing the chosen shot.
- **Control capture:** expose Auto/Manual state explicitly. Keep manual values legible and announce changes accessibly. If a lens or format cannot support a saved setting, explain the adjustment and display the actual value used.
- **Develop:** start with look and exposure; reveal detailed film/color/framing tools when requested. Preserve an undoable edit history when durable originals are introduced. Export status must distinguish a retained source from a completed Photos save.
- **Upgrade:** show a clear monthly price and trial terms when the user requests a premium capability. Trial and paid access produce clean images. Closing a paywall must retain the photo and return to the previous task.
- **Use iPad:** take advantage of width for simultaneous image and controls, with usable portrait, landscape, and narrow multitasking layouts. Test touch targets, Dynamic Type, VoiceOver, Reduce Motion, and orientation transitions on device.

## What counts as better

Feature count alone does not establish superiority. Record app version, source commit, device/lens/OS, capture mode, lighting, settings, and export format with each comparison.

| Area | Evidence and proposed acceptance |
| --- | --- |
| Photographic preference | Run blind, randomized comparisons on matched scenes against current Halide and flag7x. Include a specified real G7X model and Fuji camera/recipe as aesthetic references, with framing and capture differences recorded. Cover varied skin tones, direct flash, backlighting, foliage, skies, mixed light, low light, and fine texture. Report preference by scene category and uncertainty; do not hide failures behind an overall average. |
| Consistent looks | Compare capture, import, review, and exported pixels on retained reference files. Account explicitly for preview resolution, raw development, subject detection, flash, and color space. Check for clipped channels, excessive skin smoothing, halos, and unstable grain. |
| Usability | Ask new and experienced photographers to choose a look, capture, alter a setting, compare, save, and restore Auto without coaching. Proposed first gate: at least 90% complete each core task unassisted in a study with at least 12 participants. Record errors, time, and device layout; this is a study target, not a current result. |
| Responsiveness and battery | Measure cold first usable frame, warm return, control-to-preview delay, capture-to-review, export time, peak memory, and thermals on the oldest supported test device and representative iPhones. Report p50/p95 and sustained preview timing for a ten-minute session. Maintain the 30 fps preview target; isolated renderer timings cannot establish it. New Pro tools need a before/after baseline and investigation of material regressions. |
| Reliability | Exercise permission denial/recovery, capture interruption, lens switching, background/lock, low storage, Photos errors and retry, limited/add-only access, and repeated capture cycles. Require no lost captured frame or false successful-save state in the acceptance run. |
| Subscription value | Demonstrate useful recurring improvements to recipes, control, workflow, and device compatibility. Keep previously exported images accessible and deliver purchased capabilities across supported devices. Use support feedback and Apple-provided commerce reporting before adding paid analytics infrastructure. |

Record measured wins narrowly: for example, a preference for a particular G7X portrait treatment or a faster specific workflow. A broad “best camera app” claim remains an aspiration until comparative evidence supports its scope.

## Engineering and cost constraints

Keep capture, rendering, editing, and image storage on device. Use one bounded rendering pipeline and reusable GPU resources; run optional analysis on reduced frames at a measured cadence and suspend it when hidden. RAW/original retention needs quotas and explicit cleanup semantics so an upgrade does not create unbounded storage growth. Entitlements must not block camera startup or add per-frame work.

Build one advanced capability at a time with meaningful policy, hardware, image-quality, and end-to-end tests. Continue the existing CI separation: inexpensive portable checks first, relevant app tests for application changes, and device/performance suites for the changes that require them. Documentation planning does not need an app build.

This roadmap does not change build 8 or resolve the outstanding release authentication, device-scene, iPhone lens, and sustained-performance evidence in the [release checklist](release-checklist.md).
