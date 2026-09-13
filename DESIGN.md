# Filmy — Frame Index

A camera, not a camera-themed dashboard. The photograph is the one large plane; controls live at its edge. This pass starts from **04228ed7754d677ba99db495ecd9b3753db096e2** (13 September 2026), including the recent capture-recovery, gallery-paging, Photos-permission and native-halation fixes. No signing, entitlements, release version, camera session, output encoder or photo-library service is changed.

## Three directions

| Direction | Composition and identity | Decision |
| --- | --- | --- |
| **Contact Press** | Warm paper, large editorial type, vermilion index, generous print-like margins; a vertical contact sheet below the photo. | Distinct but too editorial for immediate shooting. Warm surrounds can bias color judgments; margins consume a small phone. |
| **Frame Index** | Graphite, a cut F and compact custom wordmark, acid selection indexes, fine rules and unboxed image rows. A compact thumb belt surrounds a neutral image plane. | **Chosen.** Strong small-scale identity without competing with photographed colors; direct controls fit the existing capture architecture. |
| **Night Meter** | Deep black, amber instrument marks, a large arc dial and condensed exposure readout; near-monochrome pro-tool character. | Strong direct manipulation, but too mechanical and dependent on hidden gestures. Keep a linear exposure drag with explicit step/reset alternatives, not the arc. |

`docs/design/frame-index/directions.svg` records the layout studies. They are concepts, **not simulator screenshots**. The accepted native layouts are tested separately.

## References, reviewed 13 September 2026

Three relevant references and one contrast:

- **[Halide](https://halide.cam/):** let the frame dominate and distinguish camera state from processing choices. Transfer: neutral surround, quiet inactive chrome and a comparison mode that cannot silently select the capture recipe.
- **[Obscura](https://obscura.app/obscura/index.html):** direct manipulation within thumb reach. Transfer: horizontal EV movement with equally capable step/reset controls; do not copy its dial, icon, or control arrangement.
- **[Darkroom](https://darkroom.co/)** and its [render-engine explanation](https://darkroom.co/blog/2025-12-09-render-engine): keep editing attached to the image. Transfer: one aligned original/look plane and predictable return to the finished photo, not two unrelated thumbnail cards.
- **Contrasting: [Readymag](https://readymag.com/).** Transfer typographic hierarchy and deliberate asymmetry to the brand, not its freeform web composition to camera navigation. No floating marketing panels over the photograph.

Also reviewed publisher pages/screenshots for [Kino](https://www.shotwithkino.com/), [Leica LUX](https://leica-camera.com/en-US/photography/leica-apps/leica-lux), [VSCO Capture](https://www.vsco.co/capture), [Linear](https://linear.app/), [Raycast](https://www.raycast.com/), [Stripe](https://stripe.com/), [Suno](https://suno.com/), and the user's [Print Margin](https://f60cdf7b.3d-print-job-costing.pages.dev/). Print Margin's restrained index marks and strong outcome hierarchy are useful; its forms and cards are not camera navigation. Public [Command Gate](https://www.commandgate.ai/) was verified from the repository's canonical URL; [Scarcity Trade](https://scarcitytrade.com/) was verified before opening. Neither site's purple/navy palette or desktop layout is copied.

These were publisher-page reviews, not hands-on tests of competing apps. A read-only isolated browser captured the public sites at their verified URLs; Raycast's browser body timed out, so its web-search/page text was the available reference. No third-party logo, font, screenshot or photograph is shipped in Filmy.

Apple guidance checked: [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons), and [Reduce Motion evaluation](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria/). The implementation retains the iOS 17 deployment target, native sheets/pickers, portrait app contract, and existing intentionally dark photo workspace.

## Native design system

**Type.** System San Francisco at semantic Dynamic Type sizes; bold headings, regular body, monospaced exposure values. The small geometric wordmark is drawn as paths, not a shipped font. No content text uses the wordmark. No camera-wide accessibility-size cap.

**Space and shape.** 4-point spacing base; 8/12/16/20 for grouping; 44-point minimum controls, 48–64 where thumb operation or sheet scaling requires it. Photos have a 4-point viewfinder corner, not a decorative card. Utility controls use 8–10-point corners; native presentation surfaces keep their system shape. A real Instant Print border is never rounded or cropped by presentation.

**Color.** Graphite `#0E0E0E`, neutral elevated surfaces, acid `#D9F852` for the active look and shutter index, ember `#FF765E` for favorites and identity punctuation, cyan `#69CFFF` for exposure. Color is redundant with a check, value or selected trait. Dark ink, not white, sits on acid buttons. Preview pixels are never tinted by UI decoration. Default/dark/tinted opaque 1024px icons share the original cut-F geometry.

**Icons.** SF Symbols describe native actions; the hand-authored F/wordmark identify Filmy. Essential unfamiliar actions retain short labels (Tune, Original, Roll, Flip) and full VoiceOver labels/values. Stable identifiers expose operations to UI automation without depending on coordinates.

**Motion and haptics.** Short transitions only; no animated background or per-frame SwiftUI publication. Reduce Motion removes control press scaling and shutter blink. Existing user-controlled semantic haptics remain authoritative; EV feedback happens at a quantized change, not every dragged pixel.

## Core journey

**Capture.** Flash remains immediate; import and settings remain visible. Flip moves to the shutter row, Tune is one tap, and tools move to the lower image edge. The new Original control only bypasses film in the GPU preview. It does not replace the selected recipe, change exposure, install another frame callback, or touch capture/export. Changing look/lens/position or leaving the camera clears comparison. The simulator shows an explicitly labeled sample and never enables a fake shutter.

**Focus/exposure.** Preserve normalized focus coordinates, crop/mirror/orientation transforms and settling. A focus-lock action remains available after the visual reticle fades. EV supports a relative, quantized drag plus separate ±1/3 EV and reset buttons and VoiceOver adjustments. CameraService still clamps hardware limits.

**Looks.** Keep the quick, grouped drawer and the 128-look catalog's real renderer-backed sample previews; make Tune direct. The full library becomes an unboxed image-led index, with favorites separate from selection. Search, favorites and custom recipe persistence are preserved.

**Import/edit.** One aligned split comparison when source and result have matching photo geometry. Instant Print or mismatched aspect ratios use the whole original instead: a split must not imply that a border is source content. Save still writes the selected treatment as a new copy. Cancel asks before discarding an unsaved edit and can return to the unchanged edit.

**Roll/save/share.** Preserve native UIKit paging, pinch zoom, asset identity, Photos-limited access, share completion handling, deferred write callbacks and pending-capture retry. Failed capture bytes cannot be replaced by a new shot; discard now requires confirmation. No new microphone permission: the product is a still-photo camera.

**First use.** One optional sample-and-look decision, a visible automatic-save explanation and a contextual privacy sheet replace the three-page tour. Permission prompts stay at their existing point of use. No claims about unsupported hardware, resolution, pricing or AI.

## Verification

See [the validation record](docs/design/frame-index/VALIDATION.md) for exact commits, commands, real simulator evidence, critique/refinement cycles and remaining physical-device gates. Source-level and renderer tests do not substitute for device latency, hardware focus or camera permission testing.
