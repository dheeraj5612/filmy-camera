# Manual camera controls — build 9 acceptance

Build 9 adds a Pro sheet with manual ISO/shutter, sensor white balance, focus, physical lens selection, and Reset to Auto. Applied state comes from the active camera. Slider gestures commit when released; no per-frame polling was added. Manual exposure uses speed-prioritized capture with flash off, while Auto retains quality-prioritized capture and the remembered flash choice. Monthly subscriptions, trials and watermarks remain future work.

## Evidence and outstanding checks

Local Xcode 26.6 / iOS 18.5 simulator validation passed 188 unit/integration, 19 UI, and 3 normal Photos E2E tests before the final flash-restoration and UI-entry fixes. The eight new unit tests cover numeric bounds, invalid inputs, gain safety, exact frame/exposure durations, capture priority and capabilities. Twenty portable test-runner checks and build-9 release preflight pass. The final source must retain its own build-input digest and results; earlier results are not evidence for subsequent fixes.

An initial iPad Pro 11-inch (2nd generation), iPadOS 26.6.1 hardware run captured the requested 1/125 and 1/60 shutter durations exactly in JPEG EXIF. Sensor checks passed within tolerance for requested ISO 36 and 72, but EXIF reported 32 and 64: a constant −0.170 EV offset with the correct 2× response. This failed the original 10% ISO tolerance. The cause is not established; neither metadata nor the original result was rewritten. White-balance gains, manual focus, session reuse and returning from front-camera Auto to rear-camera Auto passed their assertions. The final flash-preference assertion failed and exposed stale availability handling, which was fixed after source review.

The hardware test now isolates ISO and shutter with three canonical requests (ISO 100/200 at 1/125, then ISO 200 at 1/60, clamped to device bounds), records requested/sensor/EXIF settings, and retains strict sensor, shutter and relative-response assertions. This controlled retest and the physical Pro-sheet flow are pending: the iPad relocked before Xcode could launch them. The Mac is also locked, preventing interactive Computer Use review. The earlier physical UI run failed to reach the Pro button from the collapsed tool rail; the test now follows the visible Show Camera Controls flow. That fix still needs device validation.

Local evidence stays under `build/manual-controls-20260905/`, including the original `physical-smoke.xcresult`, its metadata/image attachments, compiled-device logs, and simulator result bundles. Hardware images remain local.

## Subsequent verification

The committed implementation at `63e1019` passed a fresh local run of all 188 core tests and the Pro-sheet simulator flow in portrait and landscape, with zero failures or skips. Its signed device build was installed on the iPad and read back as version 1.0.0 (9); launching was denied by the lock screen. Build-input digest: `4ba0f2b76291fef3844b9022740866ce55935e51757a594c61f7c6cdbdd78a0e`.

One intermediate simulator run crashed with SIGSEGV during the existing all-recipes pixel-consistency test. No symbolized stack established a cause. The fresh complete core run passed that test and all others. Failed results remain local and strict pixel assertions are unchanged; a simulator/Core Image fault is a hypothesis, not a confirmed diagnosis.

Final accessibility inspection also found the shutter's generic disabled label referred to Preview mode while real manual settings were applying. The call now supplies the actual applying-settings label and hint. The Pro button also announces pending settings, and the physical-lens hint now follows actual capability requirements. Full hosted validation is required for these final corrections. The App Store Connect browser session has expired and shows sign-in; no build-9 upload or submission was attempted.

## Release status

This is an implementation candidate, not a public release or proof of comparative image quality. Cross-device manual capture, physical Pro-sheet portrait/landscape review, a lit G7X/Fuji comparison, and sustained thermal/performance acceptance remain required. Public support, privacy, terms and primary legal-site navigation returned HTTP 200 on September 5; the App Store URL for app ID 6801404866 returned HTTP 404. Build 9 has not been uploaded or submitted.
