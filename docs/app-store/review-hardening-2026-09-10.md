# App Review hardening: September 10, 2026

## Scope and release status

This change set hardens the current free, local-first camera app. It is not a declaration of Apple approval or a fix for an unverified rejection reason. No StoreKit purchase, login, account, advertising, tracking, or remote analytics service is enabled. Adding account deletion, purchase restoration, ATT prompts, or subscription UI to this free release would misrepresent its behavior. Reassess those requirements when the underlying features actually ship.

Implementation and latest validation evidence: [app PR #95](https://github.com/dheeraj5612/filmy-camera/pull/95). The related [privacy-policy PR #3](https://github.com/dheeraj5612/filmycam-legal/pull/3) remains a draft and does not update the live policy until reviewed and merged. Review its support-correspondence and retention statements against actual operations before publication.

## Changes implemented

| Area | Failure prevented | Change |
| --- | --- | --- |
| Camera session | Reusing a session missing its input or outputs after lens switching or an AVFoundation error | Validate the actual graph, tear down invalid graphs, rebuild on recovery, and cap retry backoff |
| Camera permission | Showing a settings action for device restrictions or treating unavailable physical hardware like a simulator | Separate denied, restricted, simulator, and unavailable states; preserve system-picker import |
| Recovery logging | Camera failures without actionable evidence, or logs containing user content | Log only technical error codes, retry counts, and delays locally with OSLog |
| Release behavior | Shipping UI-test flags that alter permissions, onboarding, or persistence | Compile launch-hook parsing out of Release; verify the actual executable has no test-only markers |
| Photos changes | Stale thumbnails after editing or deleting a saved frame outside the app | Observe authorized library changes, invalidate caches, and include image modification revisions in request keys |
| Photos requests | An iCloud original or missing terminal callback leaves the Roll loading forever | Bound image waits to 30 seconds, cancel safely, preserve degraded fallback without caching it as final, and recheck authorization |
| Share preparation | A cancelled or delayed PhotoKit write presents a stale share sheet or leaves partial files | Bound waits to 60 seconds, complete continuations once, and clean late results; PhotoKit writeData itself remains non-cancellable |
| Local sharing | Clearing or evicting the local Roll cache breaks an active share | Give each share its own protected temporary copy |
| Local privacy | Cached frames lack complete file protection or cache-clearing failures look successful | Use protected, backup-excluded cache writes; confirm deletion and surface failures without deleting Photos originals |
| Privacy UI | Privacy information is unreachable offline | Add a scrollable in-app overview, public policy/support links, and a persistent Done action |
| Limited Photos | Automatic system limited-library notices appear independently of the app's management flow | Use the explicit management action and suppress automatic limited-access alerts |
| Required-reason APIs | Elapsed-time APIs used by the app are absent from the privacy manifest | Declare SystemBootTime reason 35F9.1 alongside the existing app-container timestamp and UserDefaults reasons |
| Submission artifacts | Source metadata looks valid but the built or exported app differs | Run the new preflight against source, the built app, the archive, and the exported IPA |

## Validation record

The first focused native run tested product commit `252b0089dff60433cfb38f0b61f98656386aca16`: 81 tests passed and one physical-device-only test was skipped on iPhone 16 Pro / iOS 18.5 / Xcode 16.4. That run also compiled the unsigned Release app and physical-device test branches with Xcode 26.3.

[Run 34510766973](https://github.com/dheeraj5612/filmy-camera/actions/runs/34510766973) tested the completed product changes at `12507bfe212a3c9ccdb84b5a912d2455c1422310`:

- 92 Python tests passed. Source preflight passed. The configured public support, privacy, and marketing URLs returned HTTP 200 with the expected content markers.
- iPhone 16 Pro / iOS 18.5: 86 passed, zero failed, one skipped. The skip is `testPhysicalAddOnlySaveCallbackHasReadablePersistentCache`, which requires hardware.
- Xcode 26.3 / iOS SDK 26.2: unsigned Release build, actual bundled-app preflight, and physical-device test compilation passed. This is not a signed archive, installation, or physical-device execution.
- iPad Pro 13-inch (M4) / iOS 18.5: 85 passed, one skipped, and the privacy UI scroll test failed. The recording showed the test flinging past its target in the shorter sheet. The test now uses smaller direction-aware drags, retains the original hittability/dismissal assertions, and attaches a screenshot.

[Run 34512048211](https://github.com/dheeraj5612/filmy-camera/actions/runs/34512048211) verifies the corrected UI test at `fa7f500c00c5890eadbe928e745025ec6d7ce888` on iPhone and iPad. Consult its result summaries and the PR's final verification comment for the outcome; do not interpret a queued or running check as a pass. Full repository CI is separate from these focused selections and is recorded on PR #95. Temporary source-transfer scripts and validation workflows are not part of the release.

Linux-side checks include Swift syntax parsing, Python tests, the tracked-credential guard, and `git diff --check`. Native build logs retain existing warnings; this report does not claim a warning-free build.

## Required physical-device acceptance

Use a signed build from this exact PR head or the final merge commit. Run on an iPhone with multiple lenses, an older supported iPhone, and a supported iPad. Record the build SHA, device, OS, scenario, outcome, and screenshot or video. Simulator policy tests do not substitute for these checks.

| Scenario | Acceptance condition |
| --- | --- |
| First launch with Camera denied | Clear explanation; system-picker import and editing remain available |
| Screen Time or MDM restrictions | Restricted copy is truthful and does not promise that ordinary settings can remove restrictions |
| Deny Photos, then allow add-only | Capture/import review remains usable; successful saves persist in Photos; cached app-created frames appear without requesting broad read access |
| Limited Photos and managed selection | No unrelated photos appear; selected app-created images refresh; changing selection does not destroy inaccessible-frame metadata |
| Edit or delete an app-created image in Photos | The foreground Roll refreshes; old thumbnail revisions do not remain visible |
| iCloud-only photo while offline | Image and share waits terminate; retry is possible; dismissing detail cancels UI work and late share results do not reopen a sheet |
| Rear/front/telephoto switching and unavailable flash | Valid capture or honest unavailable state; no permanently blank viewfinder or stale manual capabilities |
| Camera interruption and media-services reset | Recovery is bounded; no capture is issued against a partial graph; local diagnostics identify the technical failure |
| Background, lock, and thermal pressure during capture or save | No crash, unbounded spinner, or false success; Photos originals survive cache failures |
| Low storage and cache clearing | Confirm destructive local clearing; report failures; keep Photos originals and active share copies independent |
| Share cancellation and completion | The selected image is correct; temporary-file lifetime covers the share; late callbacks do not reuse dismissed UI |
| Accessibility text sizes, VoiceOver, iPad multitasking, and rotation | Important controls remain reachable with labels and usable hit targets; privacy information and Done remain available |

## App Store Connect and public-page gates

1. Read the actual App Review message in Resolution Center. A generic submission-issue email does not establish a guideline number or rejection reason. No private submission identifiers are stored in this repository.
2. Review and publish the companion policy corrections. Local image processing does not mean Apple Photos can never download or sync through iCloud, that system backups cannot contain preferences, or that uninstalling removes Photos originals. Verify support contact and retention statements.
3. Read back the actual App Store Connect name, subtitle, description, keywords, URLs, availability, pricing, contact, review notes, screenshots, and privacy answers. A repository template is not evidence of saved server-side values.
4. Complete the current age-rating questionnaire and use Apple's calculated result. Do not treat the template's expected 4+ value as a verified App Store Connect answer.
5. Use a monotonically newer build number. Confirm it against uploaded and processed builds, not only the source plist. This PR intentionally does not guess the next available number.
6. Re-capture final screenshot packs from the submitted product paths. Do not submit UI-test mode, unavailable-camera placeholders, private fixtures, or obsolete controls as product screenshots.
7. Verify rights to every brand name, recipe reference, asset, and screenshot. A disclaimer alone does not establish permission or legal clearance.
8. Produce and validate the signed distribution archive and IPA with an eligible Xcode/SDK; install through the intended distribution route. The unsigned CI app is not a submission artifact. No signing credentials, uploads, production deployments, or App Store answers were changed here.

## Repeatable preflight

```bash
python3 -m unittest discover -s scripts/testing -p 'test_*.py'
python3 scripts/release/validate-app-review.py
python3 scripts/release/validate-app-review.py --check-live-urls
python3 scripts/release/validate-app-review.py --app /path/to/FilmyCamera.app
bash scripts/release/validate-project.sh
bash scripts/release/validate-archive.sh /path/to/FilmyCamera.xcarchive
bash scripts/release/validate-ipa.sh /path/to/FilmyCamera.ipa
```

Default preflight is offline and standard-library only. Live URL checks are explicit, allowlisted, HTTPS-only, size/time bounded, and do not claim legal adequacy. Unexpected purpose strings, privacy reasons, capabilities, or embedded frameworks require a reviewed contract update rather than silently accepting new data access.

## Primary guidance checked

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): completeness, accurate metadata, privacy, intellectual property, and applicable business-model rules.
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/): App Store uploads require Xcode 26 or later with the iOS 26 SDK or later beginning April 28, 2026.
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api): app-container timestamps, app-owned UserDefaults, and elapsed-time use.
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/): declarations must match the shipping app and any service or SDK behavior.
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/): metadata limits, including UTF-8 byte limits for keywords and review notes.
