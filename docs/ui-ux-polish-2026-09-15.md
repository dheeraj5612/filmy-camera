# UI/UX refinement pass

Baseline: `3d1428ec8497ad6b3836db256cb75145828f5add`.

## Intent

Refine the existing Signal Frame identity rather than introduce another redesign. Keep photographs neutral and prominent, make state changes easier to understand, and make secondary screens usable at the largest Dynamic Type sizes. Preserve portrait orientation, automatic camera saves, explicit import review, native gallery paging, rendering fidelity, and permission boundaries.

## Implemented changes

| Surface | Previous friction | Refinement |
| --- | --- | --- |
| Zoom | Bubbles and targets changed size on selection; some were only 32 points | Stable 48-point phone / 64-point iPad targets, an outlined active factor, narrow-width scrolling, and VoiceOver preset actions |
| Zoom limits | A narrow hardware range could fall back to an unavailable 1x | Valid ranges only offer supported presets, falling back to the actual minimum |
| Shared buttons | Reduce Motion removed animation but still applied the scale transform | One tested policy removes press transforms when motion is reduced, keeps disabled/resting geometry fixed, and uses restrained feedback otherwise |
| Primary actions | Long labels could outgrow a fixed button height | Wrapping text, vertical padding, and a minimum rather than fixed height |
| Page hierarchy | Headings and trailing counts competed horizontally at accessibility sizes | Headings and metadata stack vertically; small labels use semantic fonts |
| Settings rows | Badges and switches squeezed explanatory text | Accessories sit below text at accessibility sizes and retain their intrinsic width at ordinary sizes |
| Permission badges | Color alone carried much of the distinction | Explicit check/warning symbols with accessible state text |
| Camera permission | An authorized but paused camera could appear disabled | A refreshed authorization snapshot controls permission presentation independently of session activity |
| Flash settings | A segmented picker was cramped at accessibility sizes | The same values and availability policy use a menu at large sizes |
| Cache storage | A constant `250 MB` looked like measured usage | Truthful `On device` / `Empty` status instead of an invented usage reading |
| Cache clearing | A single tap immediately removed local fallback copies | Confirmation explains Photos preservation and possible Roll disappearance; cancel retains the cache |
| Onboarding | Narrow horizontal choices and comparison captions became crowded | Larger standard thumbnails, full-width accessibility choices, stable selection-mark space, explicit starting-look guidance, and a reflowing compare control |
| Import progress | A fixed modal card could strand Cancel below the viewport | Scrollable modal, a full-width cancel action, keyboard/VoiceOver escape, initial VoiceOver focus, and accurate cancellation copy |
| Recipe swatches | Cache hits still waited for the editor debounce; failures could spin indefinitely | Cache-first retrieval, explicit failure state, and recipe identity checks that prevent displaying obsolete thumbnails |
| Toasts and empty states | Small fixed text, capped error copy, and generic permission hints | Semantic wrapping text, bounded reading width, and caller-owned action hints |

No rendering algorithm, sample photograph, cache budget, save pipeline, import ownership/cancellation rule, gallery paging implementation, or orientation configuration was changed. Cache clearing still delegates to the existing service and does not delete Photos originals. Swatch rendering retains its serial actor, 150 ms uncached debounce, cancellation checks, and 48-item / 12 MB cache limits.

## Automated validation

Run the portable checks with:

```sh
python3 scripts/validate-ui-polish.py
```

The script parses the seven modified Swift files and compiles/runs the actual eight new interaction-policy XCTest methods against the production policy. Tests cover Reduce Motion, disabled/resting controls, normal press feedback, invalid scales, standard/narrow/invalid zoom ranges, and 160 valid hardware-range combinations. It is not a SwiftUI mock or a substitute for an iOS build.

The new `FilmyControlInteractionTests` class is classified as `unit` in `scripts/testing/suites.json`, so the existing core CI lane discovers it. Tests are added inside an already registered test source; the generated Xcode project remains unchanged.

Existing native UI tests are extended without changing their method counts:

- `SignalFrameUITests.testCameraPrimaryControlsRemainReachableAtLargestAccessibilityText` also checks Settings storage, return navigation, full-width onboarding choices, original/look comparison, and selected-look handoff. It retains screenshots of these states.
- `NormalRollManagementTests` now exercises cancel followed by confirmed cache clearing before its existing Photos-preservation and denied-access recovery assertions. This suite remains restricted to the disposable seeded simulator.

The portable checks passed locally. Native iOS compilation, simulator UI execution, physical-device checks, and visual screenshot review require Xcode and are not claimed as completed by the portable result. Keep the PR as a draft until those native gates are reviewed.

## Native acceptance checklist

| Configuration / flow | Verify before merge |
| --- | --- |
| Compact iPhone and iPad portrait | Zoom targets do not resize or shift on selection; narrow tool rows scroll without moving the viewfinder |
| Largest Dynamic Type | Settings badges do not squeeze copy; flash menu, cache action, onboarding choices, comparison, and return/continue actions remain reachable |
| Reduce Motion / Increase Contrast / Reduce Transparency | Press feedback does not scale with Reduce Motion; card/chrome boundaries remain distinct; images stay unaffected |
| VoiceOver | Zoom is adjustable and exposes preset actions; permission and lock state are clear; import receives initial focus without repeatedly stealing it from Cancel |
| Camera authorized, then paused | Settings continues to report permission as allowed; session status remains separate |
| Slow iCloud import and cancellation | Cancel stays reachable, no fake percentage appears, stale provider completions cannot overwrite a newer import, and no photo is silently saved |
| Cache with full, limited, and denied Photos access | Cancel preserves copies; confirmation removes only local copies; Photos originals and ownership remain intact |
| Rapid look edits and drawer reopening | Cached previews return without an artificial debounce; uncached edits remain debounced; old recipe pixels never label a new selection |
| Physical capture and gallery | Portrait-only capture remains live after automatic save; imported photos still require explicit save; native paging, pinch zoom, and exported pixels are unchanged |

This pass does not represent an App Store submission or release approval. No production branch merge, version bump, permission broadening, or dependency addition is included.
