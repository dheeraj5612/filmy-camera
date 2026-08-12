# Filmy Camera design pass — 2026-08-12

## North star

Filmy Camera should feel like a quiet digital rangefinder: the viewfinder stays primary, choosing a recipe feels like choosing a film stock, and deeper controls appear only when the photographer asks for them.

The analog character comes from tone, color, grain, and halation. The interface does not need fake film borders or decorative chrome to communicate that character.

## Research inputs

- [Apple Camera Control HIG](https://developer.apple.com/design/human-interface-guidelines/camera-control) — keep custom camera controls out of system camera-control overlay areas.
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) — preserve clear hierarchy, accessible hit regions, and restraint with materials.
- [Apple Behind the Design: Halide Mark II](https://developer.apple.com/news/?id=x6bv1a36) — excitement without intimidation, consistent gestures, and a small active-state color language.
- [Halide](https://halide.cam/?v=1.0.22) — tactile camera-inspired controls, minimal viewfinder chrome, and intentional grain/halation processes.
- [Moment Pro Camera II](https://www.momentprocamera.com/) and [Moment manual](https://www.momentprocamera.com/manual) — progressive disclosure through action plates, lens bars, exposure, profiles, and looks.
- [Dazz Cam on the App Store](https://apps.apple.com/us/app/dazz-cam-vintage-camera/id1422471180) — a low-friction, one-tap camera workflow organized around distinct camera/film formats.
- [Fujifilm X-T5 image-quality controls](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/) — public vocabulary used for Tone, Color, Dynamic Range, Color Chrome, grain, and finish groupings.

## Implemented in this pass

- Reframed the camera action plate around `Roll`, `Tune`, and `Look` instead of a generic details/info pair.
- Made focus feedback interaction-only so a reticle does not sit permanently over the viewfinder.
- Added a compact simulator/offline action plate so the unavailable-camera explanation remains readable and capture is not presented as available.
- Grouped recipe controls into `Tone`, `Color`, `Texture`, and `Finish`; Tone and Color open first, while deeper texture and finish controls stay available through disclosure.
- Added semantic slider values and larger control rows for VoiceOver and motor accessibility.
- Centralized camera hit-target, typography, control radius, and action-plate tokens in `FilmyTheme`.
- Reframed Gallery as `Roll`, moved to a two-column contact-sheet feel, and preserved each asset’s aspect ratio.
- Added recipe/date provenance plus share, delete, and destructive-confirmation actions to the Gallery detail flow.
- Tied camera start/stop to the active tab and scene phase, with a recoverable interruption state instead of frozen capture controls.
- Corrected tap-to-focus for the preview's aspect-fill crop and aligned camera connections with portrait/landscape layouts.
- Made the viewfinder crop a shared camera-frame contract so the saved still keeps the same composition as the live preview.
- Made capture fail closed when the selected look cannot be materialized instead of silently falling back to the unfiltered image.
- Reframed capture confirmation around `Keep Frame` and added a recipe metadata chip.
- Corrected simulator Settings permission states so denied camera access is not shown as `READY`.
- Updated UI tests to cover the new `Roll` and `Tune` language.
- Replaced recipe-rail gradient placeholders with deterministic synthetic scenes rendered through the real FilmRenderer, and made preview/photo/export share one canonical color cube.
- Made the Core Image working/output color space explicit sRGB and normalized grain/halation scale across output resolutions.
- Added selectable original Acros neutral/yellow/red/green filter starting points so every exposed monochrome filter mode is reachable from the recipe rail.
- Added a lower-cost preview cube, capture-derived grain phase, preview-before-render framing, EXIF orientation normalization, truthful output dimensions, and a downsampled review image to keep the live and saved frame contracts aligned without retaining two full-resolution decoded images.
- Added VoiceOver routes for live preview, adjustable zoom, and focus/exposure lock; added an explicit Photos-settings recovery action on failed save; and disabled picker/toast motion when Reduce Motion is enabled.
- Added a typed camera availability contract for permission, simulator, interruption, recovery, and running states so camera recovery UI no longer parses status copy.
- Hardened release automation with a display-name assertion, `.provisionprofile` support, reproducible XcodeGen output checks, successful-run XCTest artifact retention, and broader metadata/privacy change triggering.

## Deliberately deferred

- Bundled photographic recipe thumbnails: the current implementation still has no licensed neutral stills or capture sample set. The rail now uses original synthetic reference scenes rendered by the production pipeline; a photographic asset pass should add only original/licensed images and run them through the same renderer.
- Physical-device color calibration and signed release validation: simulator and hosted gates prove the render contract and UI shell, but cannot prove sensor-specific color, capture metadata, memory pressure, or Apple distribution access.

## Verification

- Simulator build succeeded for the iOS 18.5 `FilmyCamera iPhone` runtime.
- Unit/renderer tests: 28 passed.
- UI tests: 2 passed.
- Full simulator suite: 30 tests passed with 0 failures.
- Final simulator review confirmed the unavailable-camera state and compact offline action plate remain legible.
