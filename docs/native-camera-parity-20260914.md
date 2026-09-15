# Native Camera interaction and feature inventory — 2026-09-14

## Research

Apple's [iPhone Camera guide](https://support.apple.com/guide/iphone/set-up-your-shot-iph3dc593597/26/ios/26) describes tapping a subject, then dragging the exposure control up/down, plus AE/AF locking. This is an established interaction, not exclusive to the latest OS. Implementation uses public exposure-compensation APIs already supported by this app.

Reviewed indexed descriptions of YouTube tutorials [HowTech: Focus Control](https://www.youtube.com/watch?v=vRPe2nBL9WY) and [iPhone Photography Course: Focus & Exposure](https://www.youtube.com/watch?v=DESywd-JqA4). Descriptions corroborate sun-slider direction and exposure adjustment with focus locking. Direct YouTube fetch failed; video playback was not reviewed. Apple's documentation is the implementation authority.

## Implemented interaction

Tap to focus; while the focus feedback is visible, drag vertically anywhere on the preview. Up increases exposure; down decreases it. The sun badge shows the service's applied EV. Feedback remains during adjustment and for five seconds afterwards. Each drag takes a fixed starting bias; one stop requires one quarter of the preview height (minimum 100 points). Hardware clamping/quantization stays in CameraService. Manual exposure/applying controls, disabled camera interaction and pinching block exposure adjustment. Horizontal look swipes and vertical exposure drags lock their initial deliberate axis; diagonal motion waits for intent. VoiceOver has Brighten/Darken actions. The existing AE/AF button remains the lock interaction.

This adjusts sensor exposure compensation, not display brightness. It shares the existing exposure setting; it does not add Apple's separate per-shot and persistent compensation layers.

## Feature roadmap

| Area | Current source / remaining work |
| --- | --- |
| Photo basics | Existing focus, AE/AF button, zoom, camera switching, timer, flash controls, composition guides, gallery; new vertical exposure gesture. Physical-device acceptance pending. |
| Creative/manual controls | Film looks, manual sensor controls, histogram, zebras, focus peaking and level are existing app capabilities. |
| Lock interaction | Native-style touch-and-hold AE/AF lock is a remaining interaction gap; current app exposes a button. |
| Motion capture | CameraService uses video frames for preview and photo output for stills. Video recording, slow motion, time lapse and Live Photos need separate capture/export pipelines and acceptance. |
| Computational modes | Portrait/depth, Night, panorama, spatial capture and Apple-specific image processing need individual API/hardware feasibility checks. No parity claim. |
| OS/hardware integration | Existing capture-event support, new supported-hardware lens-smudge advisory and AirPods setup guidance. Camera Control adjustments and lock-screen launch need separate capability review. |

A feature superset is the product direction, not the current verified state. Prioritize gesture/device acceptance, then capture modes; evaluate hardware-dependent features individually instead of promising identical Apple processing.

## Verification

Full-app Swift 6 typecheck passed with Xcode26.6 / iOS26.5 SDK: `.ci/focus-exposure-20260914/typecheck/run-wz9bwxem/result.json` (exit0,28.163s). The existing Xcode build-description hang still blocks portrait iPhone UI and physical iPadOS27 acceptance; no installation or visual pass claimed. Gesture policy tests cover intent thresholds, direction, viewport scaling, invalid geometry and invalid bias; host test evidence is recorded in agent notes.
