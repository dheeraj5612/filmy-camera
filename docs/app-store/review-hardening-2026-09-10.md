# App Review hardening: September 10, 2026

## Scope and release status

This change set hardens the current free, local-first camera app. It is not a declaration of Apple approval or a fix for an unverified rejection reason. No StoreKit purchase, login, account, advertising, tracking, or remote analytics service is enabled. Adding account deletion, purchase restoration, ATT prompts, or subscription UI to this free release would misrepresent its behavior. Reassess those requirements when the underlying features actually ship.

The base is main at `f9c15224e1a81fa6740c2953cae8992355b94ede`. The separate portrait/automatic-save/gallery-paging work in PR #94 is not included. This branch preserves explicit capture review and Save to Photos, and existing iPad and landscape support. Reconcile permission strings, metadata, screenshots, and hardware acceptance again if that independent work merges first.

## Implemented safeguards

| Area | Behavior and regression protection |
| --- | --- |
| Camera graph recovery | Validate active input and both capture outputs. Rebuild incomplete graphs on resume or after a failed input rollback. Mark runtime errors as requiring a graph rebuild, then recover with bounded backoff. Cancel stale pending captures and reset observers/capabilities during teardown. |
| Camera permissions | Recheck authorization when reopening an already configured session. Separate denied access from Screen Time/managed-device restriction. Physical hardware failure is not mislabeled as a simulator. Import remains independent of camera access. |
| Photos ownership and revocation | Observe authorized library changes, invalidate stale thumbnails, include edit revision in request identity, and recheck permission around asynchronous reads. The Roll remains scoped to saved app-owned identifiers, not every photo in an album with a matching name. |
| Image waits | Bound PhotoKit image waits to 30 seconds, with a degraded preview when available, and reject late results from entering the cache. Cancellation resumes the waiting caller exactly once. |
| Sharing waits | Bound Photos resource preparation to 60 seconds, abandon the waiting UI on cancellation, and clean up late writes. PhotoKit's `writeData` operation itself is not cancellable; this is explicitly not a guarantee that an in-progress platform download stops immediately. Cached shares receive a separate temporary file so clearing the Roll cache cannot invalidate an active share. |
| Local privacy | Use complete protection on cached frame writes, keep caches excluded from backup, preserve Photos originals during cache clearing, and report deletion failures instead of claiming success. |
| User disclosures | Add a bundled offline privacy overview, preserve public privacy/support links, explain system Photos/iCloud behavior, distinguish import from optional library reading, and explain that uninstalling or clearing cache does not remove Photos originals. |
| Release isolation | Compile test launch flags and custom test-defaults handling only into Debug. Inspect the actual Release binary for those markers. Test behavior is not an App Review bypass or reviewer-specific experience. |
| Manifest | Require explicit no-tracking/no-collection declarations and three reviewed API categories: UserDefaults `CA92.1`, app-container FileTimestamp `C617.1`, and elapsed-time SystemBootTime `35F9.1`. |
| Submission preflight | Validate purpose strings against XcodeGen, exact privacy schema/reason codes, opaque 1024px icon, metadata lengths including UTF-8 byte limits, HTTPS URLs, built SDK, distribution binary, and unexpected embedded SDKs. Run against source, Release app, signed archive, and exported IPA. Public-link checks are separately opt-in. |

The preflight is intentionally strict for this release's reviewed contract. When dependencies, permissions, data practices, or signing architecture change, review the product first and update the contract with tests. It is not a general substitute for Apple's server-side validation, a vulnerability scanner, or a legal assessment.

## Evidence already obtained

The initial product patch at `252b0089dff60433cfb38f0b61f98656386aca16` passed the focused [native validation run](https://github.com/dheeraj5612/filmy-camera/actions/runs/34508723986):

- Xcode 16.4 / iOS 18.5 / owned iPhone 16 Pro simulator: 81 passed, 0 failed, 1 skipped. The skipped test requires physical-device add-only Photos integration; it was not counted as a pass.
- Xcode 26.3: unsigned physical-iOS Release build, SDK checks, privacy-manifest bundling, test-launch-marker exclusion, and physical-device test compilation passed.
- Pinned XcodeGen regeneration matched the committed project and Info.plist. The existing 66 Python tests and test-inventory validation passed.

Those initial results predate the later sharing and portable-preflight changes. Use the final PR checks and their recorded source SHA for final-code evidence; do not describe this initial run as a full-suite or final-head pass. Physical camera behavior has not been verified by simulator execution or device-test compilation.

## Required device acceptance before submission

Use the release configuration on an explicitly authorized physical iPhone and iPad. Record device model, OS, source SHA, build number, pass/fail, and repro evidence without private photos.

| Scenario | Required observation | Current status |
| --- | --- | --- |
| Fresh launch, camera denied/restricted, Photos denied/add-only/limited | No crash or forced permission loop; import still works; denied save retains review; restriction copy does not promise an impossible Settings fix. | Physical verification required |
| Capture, timer cancellation, front/back, available lenses, manual controls, flash | Real image saved with the selected recipe; no stuck shutter, blank capture, or wrong orientation. Unsupported hardware controls remain unavailable. | Physical verification required |
| Background, interruption, rapid tab switching, incoming call, media-services reset | Session recovers or gives an actionable bounded failure; no duplicate capture callbacks or stale success. | Physical verification required |
| iCloud original unavailable, slow download, cancellation, library edit/deletion | Spinner terminates; late results do not overwrite newer content or re-open a dismissed sheet; retry works. | Physical verification required |
| Low storage, thermal pressure, memory warning, large/corrupt import | Failure retains recoverable work where possible, makes no false save claim, and permits recovery without repeated allocations. | Physical verification required |
| iPad multitasking, rotations, small iPhone, large text, VoiceOver | Core camera/import/save/share/privacy actions remain reachable, labeled, and dismissible; no clipped permission explanation. | Physical verification required |
| Lock device during local-cache save/share | Protected-file failures are handled without exposing unprotected photo data or claiming a completed save. | Physical verification required |
| App installation on minimum supported OS and current shipping OS | Availability gates and framework behavior work on devices; compilation alone is not runtime coverage. | Physical verification required |

## App Store Connect and public-page gates

The repository cannot establish that a saved App Store Connect form matches its markdown. Verify the exact current reviewer message in Resolution Center, address that specific issue, and provide only observed repro/fix/test information in any response. Do not claim that a generic submission notification identifies the rejected guideline.

Before resubmitting, read back the app name, privacy answers, camera/photo purpose strings, current age-rating questionnaire, review contact, export-compliance answers, agreements, availability, and applicable EU trader information. Use App Store Connect's calculated age rating rather than treating the expected `4+` in planning metadata as proof. Allocate a unique increasing build number and use screenshots from the exact release behavior; no test UI or unavailable-camera placeholder should represent a live camera feature.

Public support must load without login and provide a monitored contact route. The public privacy page must distinguish app-local processing from Apple iCloud Photos, system backups, user sharing, and data voluntarily included in support email. It must explain that uninstalling the app does not delete Photos originals. The in-app overview does not silently replace or publish the externally hosted policy. HTTP success establishes availability, not legal sufficiency or delivery of support email.

Retain provenance and appropriate rights for the app icon, bundled example image, screenshots, recipe descriptions, and any third-party names or marks. The renderer's non-affiliation statement is not a license. Original rendering parameters do not automatically authorize brand-heavy listing metadata. Ownership and regional legal requirements remain an owner review gate.

## Commands

```sh
python3 -m unittest discover -s scripts/testing -p 'test_*.py'
python3 scripts/testing/run.py inventory
python3 scripts/release/validate-app-review.py
python3 scripts/release/validate-app-review.py --app /path/to/FilmyCamera.app
python3 scripts/release/validate-app-review.py --check-live-urls
```

The first two validation modes do not make network requests. The optional URL mode requests only the reviewed public HTTPS pages with bounded timeouts, response-size limits, and redirect-host restrictions. It never authenticates to Apple, fetches account secrets, or submits an app.

## Apple sources reviewed

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), including completeness, accurate metadata, public APIs, privacy, and intellectual property.
- [Common App Review issues](https://developer.apple.com/app-store/review/), including crashes, missing content, and broken support/privacy links.
- [Current submission requirements](https://developer.apple.com/news/upcoming-requirements/): Xcode 26 and platform SDK 26 minimums since April 28, 2026; updated age-rating questionnaire.
- [App Store Connect platform-version fields](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information): field lengths and review information.
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
- [CACurrentMediaTime](https://developer.apple.com/documentation/quartzcore/cacurrentmediatime()), which derives elapsed time from `mach_absolute_time()`.
