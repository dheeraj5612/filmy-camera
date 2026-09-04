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
- Added a lower-cost preview cube, session-scoped grain phase shared by preview and capture, preview-before-render framing, EXIF orientation normalization, truthful output dimensions, and a downsampled review image to keep the live and saved frame contracts aligned without retaining two full-resolution decoded images.
- Added VoiceOver routes for live preview, adjustable zoom, and focus/exposure lock; added an explicit Photos-settings recovery action on failed save; and disabled picker/toast motion when Reduce Motion is enabled.
- Added a typed camera availability contract for permission, simulator, interruption, recovery, and running states so camera recovery UI no longer parses status copy.
- Hardened release automation with a display-name assertion, `.provisionprofile` support, reproducible XcodeGen output checks, successful-run XCTest artifact retention, and broader metadata/privacy change triggering.

## UI revamp — 2026-08-13

- Replaced the flat bottom navigation with a floating, material-backed pill that expands the active destination while keeping the camera view dominant.
- Added a shared ambient page background and warmer plate gradients so Camera, Roll, and Settings feel like one product surface.
- Tightened the camera header around the selected film stock, live/paused state, and preview-only status, with the recipe descriptor visible as supporting context.
- Reordered camera utilities so zoom, exposure, and focus lock remain visible first; less common controls continue in a horizontally scrollable rail with an accessibility hint.
- Increased recipe-card focus, simplified the selected `LIVE` badge, and aligned the film-stock header with the recipe rail.
- Added bounded Dynamic Type handling for decorative onboarding chrome and compact simulator fallback copy, while preserving large hit targets and existing accessibility identifiers.
- Replaced misleading continuous sliders for Color Chrome, FX Blue, and Grain Effect with discrete `Off / Weak / Strong` choices, and exposed Fujifilm-style `Small / Large` Grain Size choices while keeping scalar persistence backward-compatible.
- Added public `AUTO / DR100 / DR200 / DR400` dynamic-range choices, `D Range Priority`, named white-balance modes, and monochromatic warm/cool plus green/magenta axes. Older recipe records default these newly modeled fields to neutral values during migration.

The revamp was built and reviewed on the iPhone 17 Pro simulator. The camera screenshot is intentionally a simulator fallback state; it proves the shell and unavailable-camera hierarchy, not physical-device camera output.

## UI revamp — 2026-09-02

A third pass, modeled on how the system Camera, Halide, VSCO, and Moment lay
out an iPhone camera: the picture is a letterboxed frame on a black body,
controls live on the bands around it, and the chrome is Liquid Glass on
iOS 26 with an ultra-thin-material fallback on iOS 17 and 18.

### Camera

- The viewfinder is a 4:3 frame with rounded corners on a pure-black band
  instead of a full-bleed surface under gradient scrims. `ViewfinderLayout`
  fits the frame to the space left by the bands; on iPhone it stretches to the
  full width and accepts a slight crop, on iPad it keeps strict 4:3 with side
  bands. The saved still follows the same crop through the existing preview
  drawable contract, so the frame is still what is kept.
- Top bar, left to right: icon-only flash (amber when armed), camera switch,
  the recipe identity (`RECIPE` or `CAMERA PROFILE` eyebrow over the name, plus
  the `EDITED` tag), the status pill only while the camera is not live, and
  the tools chevron.
- Apple-style zoom presets (`0.5 · 1× · 2 · 5`) float along the bottom edge of
  the frame whenever the camera is live; the active bubble shows the exact
  factor and the bar stays VoiceOver-adjustable. The old zoom menu is gone.
- The tools strip and the G7 X quick controls float above the presets rather
  than sitting in the bottom band, so the rail and capture row never move.
  Exposure, focus lock, a grid toggle, and the lens menu live there; flash and
  camera switch moved to the top bar.
- Bottom band: the recipe rail (smaller 4:3 swatches, the name beneath, an
  accent ring on the selection) above a capture row of Roll thumbnail, a
  larger ring-and-disc shutter, and an icon-only Tune button. Captions under
  the round buttons were dropped; the accessibility labels carry the names.
- The frame blinks black for an instant on capture, and the focus reticle is
  a square with tick marks in the accent.
- Landscape keeps the frame on the left with the top bar and zoom presets
  overlaid, and stacks the recipe menu, Tune, shutter, and Roll in a side
  column. A new UI test covers that layout.
- The simulator and unavailable-camera placeholders now center inside the
  frame instead of assuming a full-screen surface.

### Shared chrome

- `viewfinderChrome`, `viewfinderCapsule`, and `ChromeShapeBackground` render
  Liquid Glass (`glassEffect`, tinted and optionally interactive) when built
  with Xcode 26 and running on iOS 26, and fall back to the previous material
  on older systems and on the Xcode 16.4 CI toolchain (`#if compiler(>=6.2)`).
- The dock is a glass pill with a warm-white selected segment; Import keeps
  the amber accent as the one coloured action. The camera tab sits on black;
  Roll and Settings keep the warm page background.

### Verification

- Built and reviewed on the iPhone 17 Pro and iPad Air 11-inch (M4) simulators
  (iOS 26.5) in Preview mode, including the G7 X quick controls and the
  accessibility-size shell. The simulator UI suite (15 tests, 2 hardware-only
  skips) and the unit suite pass.
- On the paired iPad Pro 11-inch (iOS 26.6.1): camera shell, landscape shell,
  G7 X quick controls, G7 X flash capture to review, and the tab round trip
  pass against the live camera. The landscape column was tightened after the
  first device run showed it taller than an iPhone's landscape height.

## UI revamp — 2026-09-01

A second, larger visual pass. The goal was to make the viewfinder feel like a camera again: chrome lives at the edges, nothing is boxed into stacked panels, and choosing a recipe reads like choosing a film stock.

### Visual system

- Replaced the cool blue palette with a warm film system: near-black surfaces with a faint warm cast, soft warm-white ink, one amber accent for state, mint for live, and a coral halation color reserved for warmth cues. All tokens still live in `FilmyTheme`.
- Added shared chrome primitives (`viewfinderChrome`, `ChromeShapeBackground`), button styles (`filmyPrimary`, `filmySecondary`, `pressable`), and small typographic helpers (`Eyebrow`, `FilmyTag`, `MetricLabel`, `SettingIcon`) so every screen composes the same parts.
- Standardized product vocabulary on **Recipe**. The camera no longer shows three different labels (film stock, current look, browse looks) for the same object.

### Camera

- One adaptive layout replaces the five previous chrome variants. A slim top bar holds flash, the live/preview status pill, and a tools toggle. The bottom stack holds an optional tools strip, the recipe header, the film-strip rail, and the capture row.
- The recipe rail now shows renderer-backed swatches with the recipe name beneath them and an accent ring on the selection; compact tiles keep the name inside the swatch at accessibility sizes.
- The capture row shows the last kept frame inside the Roll button, a larger tactile shutter, and Tune. The old header pill, action plate, "More" sheet, and decorative viewfinder corner brackets are gone.
- Zoom, exposure, focus lock, camera switch, and lens selection live in a horizontally scrolling tools strip that is hidden until requested, so the viewfinder opens quiet. Landscape swaps the rail for a compact recipe menu.
- The rule-of-thirds grid is drawn only while the camera is live so it never sits over the offline placeholder.

### Recipe detail, review, Roll, Settings, onboarding

- Recipe detail: a hero swatch carries the reference name, recipe name, and active/edited tags; control summary is a compact four-up strip; the primary action is a sticky bottom bar.
- Capture review: the frame is the page, with a recipe chip on the image and a Retake / Keep Frame bar beneath.
- Roll: a three-column square contact sheet that runs nearly edge to edge; the empty state previews real recipe renders instead of abstract shapes.
- Settings: grouped iOS-style rows with eyebrow section titles and footers. The introduction card was removed; every permission action, identifier, and copy path that the release checks depend on is unchanged.
- Onboarding: each page has a concrete visual built from real recipe renders (a fan of recipes, a miniature viewfinder, a kept frame settling into the Roll).

### Verification notes

- UI test copy expectations were updated for the renamed chrome (`RECIPE` header, Roll button) while every geometry and hit-target assertion was kept.
- The App Store screenshots under `docs/app-store/screenshots` predate this pass and should be recaptured on a device before the next submission.

## Deliberately deferred

- Bundled photographic recipe thumbnails: the current implementation still has no licensed neutral stills or capture sample set. The rail now uses original synthetic reference scenes rendered by the production pipeline; a photographic asset pass should add only original/licensed images and run them through the same renderer.
- Physical-device color calibration and signed release validation: simulator and hosted gates prove the render contract and UI shell, but cannot prove sensor-specific color, capture metadata, memory pressure, or Apple distribution access.

## Verification

- Simulator build succeeded for the iOS 18.5 `FilmyCamera iPhone` runtime.
- Unit/renderer tests: 43 passed on iOS 18.5 and iOS 26.5 simulator runtimes.
- UI tests: 2 passed.
- Full local simulator suite: 45 tests passed with 0 failures.
- Final simulator review confirmed the unavailable-camera state and compact offline action plate remain legible at the tested large-text setting.

## Recipe provenance and trust surface — 2026-08-12

The bounded recipe pass makes the look contract auditable without changing the
requested Fujifilm-style names. Every current `FilmRecipe` carries schema
version 3 and serialized provenance that identifies the first-party public
terminology references, the implementation as an original parametric
approximation, and the absence of Fujifilm hardware calibration. Its
disclaimer explicitly says the output is not pixel-identical and does not use
proprietary LUTs, firmware, or calibration data.

Numeric recipe controls now have one stable semantic catalog: each control
declares its unit, app-defined normalized editor range, and meaning. Validation
is read-only, so exploratory slider drafts are not silently rewritten; a
renderer may still clamp them at the image boundary. A recipe imported from
the pre-provenance JSON shape remains readable but is labeled legacy and does
not pass the complete provenance audit.

This keeps the camera experience honest: the names communicate the public
camera vocabulary the product is emulating, while the persisted record makes
clear that the rendering is an independent approximation rather than a claim
of Fujifilm output identity.
