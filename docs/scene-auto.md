# Scene Auto

Scene Auto is an **explicit, session-only opt-in**, not a new launch default.
Open **AUTO OFF** in the camera's status row and choose **Enable Scene Auto**.
Use **Hold Current Settings** to stop adaptation, **Resume Scene Auto** to
re-meter, or **Turn Scene Auto Off** to restore the previous sensor controls.
A direct focus tap releases Hold and owns the focus target for at least six
seconds. The existing AE/AF-lock action becomes an Auto Hold toggle while enabled.

## What it adjusts

| Area | Behavior |
| --- | --- |
| Exposure | Uses native sensor metering feedback. Custom exposure trades ISO against shutter while preserving brightness, then corrects sustained exposure errors. |
| Motion and zoom | Targets shutter limits of 1/250 for motion, 1/125 for faces, and 1/60 ordinarily. Quiet low-light scenes can use 1/30; zoom raises the handheld floor. These are bounded policies, not guaranteed settings at hardware limits. |
| Scene evidence | Six heuristic profiles: balanced, portrait, motion, low light, backlit, high contrast. Low-light classification uses metered EV, not just a dark preview. |
| White balance | Lets native WB settle, then locks supported hardware. Reacquires after sustained neutral-pixel color evidence and an eight-second cooldown. No gray-world correction of every frame. |
| Focus | Uses on-device Vision face rectangles and one-shot AF; significant target changes or a settled reframe can refocus, with spatial deadbands and cooldowns. This is not identity or depth tracking. |
| Development | A temporary copy of the chosen recipe adjusts highlight/shadow tone, noise reduction, and sharpness. Preview and shutter use the same development function; the captured copy is stored with the photo. |
| Low-light boost | Enables the system's automatic low-light boost only where supported. The previous setting is restored on exit. |

Film stock, palette, grain, recipe exposure/WB styling, crop, lens choice, zoom,
output format, and resolution remain user choices. Scene Auto does not invent
variable-aperture control, RAW highlight recovery, computational HDR, or night
stacking. It keeps flash **off without saving a new flash preference** and
restores the previous flash request on exit. A user flash or manual sensor
change exits Scene Auto before applying the requested control.

Unsupported custom-exposure lenses remain on native AE with restrained bias
changes and show **Auto Limited**. There is no automatic physical-lens switch.
Native hardware metering or stabilization can still change the image. The
software cannot promise zero optical movement, zero clipping, or perfect
classification on every device.

## Anti-hunting contract

- At most one background thumbnail/face analysis is in flight. Frames are
  dropped rather than queued. Analysis is bounded to 160 pixels on the long
  side at most 2.5 times per second; face detection runs at most about once
  every 1.2 seconds. Serious thermal pressure/Low Power Mode slows analysis;
  critical pressure skips it, and serious pressure omits face detection.
- Initial/re-entry warmup is 1.2 seconds. Small exposure fluctuations within
  0.16 EV do not produce correction commands; larger errors require sustained
  evidence. Per-update corrections are bounded, with a maximum of 0.45 EV/s
  for ordinary corrections or 1 EV/s for large errors. Hardware-quantized
  changes below 0.08 stops are not repeatedly submitted.
- Scene changes require at least 1.2 seconds of consistent evidence and a
  three-second cooldown, with separate entry and exit thresholds. One-frame
  face or highlight changes do not directly command hardware.
- Focus changes require spatial movement/reframing, 0.8 seconds of dwell,
  and a 2.5-second cooldown. User taps have a six-second grace period.
- Finishing changes move no faster than 0.025 normalized units per second.
  Highlight/shadow adjustments are capped at -0.16/-0.12; additional noise
  reduction at +0.16 and sharpness reduction at -0.10. Negative Fuji shadow
  tone lifts shadows. Film identity and persistent recipe overrides are not
  mutated.
- Generation tokens discard stale analysis after Hold, zoom, visibility or
  capture changes. Frames over 1.5 seconds old, nonfinite inputs, and invalid
  sensor bounds cannot drive control. A long gap rewarms without catching up.
- Viewfinder visibility and capture are independent gates. Countdowns,
  imports, editing/setup sheets, and capture suspend analysis. Capture
  snapshots the effective recipe before asynchronous rendering. A stopped
  camera/background teardown restores the original controls and disables Auto.

All analysis remains on-device. No additional permission, model download,
account, API key, network service, or photo upload is involved.

## Validation

Run portable controller/statistics tests with:

```sh
bash scripts/testing/test-scene-auto-core.sh
```

The same `SceneAutoPolicyTests` run in the app's XCTest target. Native
`SceneAutoIntegrationTests` cover default-off behavior, exact neutral recipe
identity, non-destructive bounded finishing, shutter snapshot isolation, and
front/rear focus coordinate conversion. Both classes are routed into `unit`
in `scripts/testing/suites.json`. Project membership is generated from
`project.yml`; regenerate with the repository's pinned XcodeGen.

### Required physical-device acceptance

Test a custom-exposure physical lens and a limited virtual/front lens. Hold a
static scene for 30 seconds, introduce a brief bright object, then move between
indoor/window/backlit scenes, neutral and strongly colored light, still/moving
subjects, and a two-face composition. Verify native AE/WB/AF reports, no
repeating lens breathing, bounded changes, and understandable Limited status.
Check focus taps and Hold; zoom/front-back/lens changes; countdown and capture;
settings/import/gallery/background interruptions; Low Power Mode and thermal
pressure. Compare the developed preview and saved frame, then turn Auto off
and verify the original ISO/shutter/WB/focus/EV/flash controls and recipe edits.

Simulator and pure-policy tests do not establish real sensor response,
optical focus stability, frame rate, power use, or photographic image quality.
