# G7X camera experience

## Product direction — 2026-09-14

G7X Camera is a dedicated compact-camera shooting experience with the single G7X rendering profile. Filmy keeps its existing G7X filter and multi-look interface. Both products compile the same camera, rendering, editing and library code; G7X-specific views compose that engine rather than copy it. Shared fixes reach both products when each app is built and released.

The visual reference is the PowerShot G7 X Mark II: rear control dial, Q/SET quick settings, exposure compensation, zoom lever and information display. Source: [Canon's camera user guide](https://gdlp01.c-wss.com/gds/8/0300022708/01/psg7x-mk2-cu-en.pdf). The app uses original G 7 X artwork, typography and green accents.

## First implementation scope

- Dark camera-body control deck with a clear shutter and distinct Q/SET quick settings access.
- Exposure compensation ticks and W/T zoom controls wired to the shared camera service.
- Information display cycling between a clear composition view and shooting assists, including the existing histogram.
- Quick access to supported flash, timer, aspect and manual camera settings.

Show real device state. Hardware ranges and availability come from CameraService. Do not present simulated adjustable aperture, a 24–100mm optical lens, fabricated battery/card capacity, or unsupported Av/Tv modes as functioning camera controls. Use zoom multipliers for phone cameras. Any manual lens-switch requirements remain visible.

## Identity and architecture

Neon green #63FF9A; pastel green #D6FFE2; body #090909. Keep useful contrast and accessible hit targets rather than reproducing small physical-camera labels at their original size. Dedicated G7X views own the presentation; AppConfiguration owns product identity and recipe availability. Capture lifecycle, permissions, rendering and photo persistence stay shared.

## Acceptance

Build both targets. Verify portrait iPhone controls fit and remain operable, Q/SET opens and closes, display mode changes, no alternate-look selection is reachable, and Filmy retains its look selection. Hardware-only zoom, exposure and flash behavior requires a physical device; simulator UI evidence cannot establish it.

## Release status

User requested no submission. The App Store record is a draft; no binary has been uploaded or submitted. Distinct UI is not a guarantee of review acceptance. Revisit screenshots, metadata, privacy/support coverage and device acceptance before any later release.
