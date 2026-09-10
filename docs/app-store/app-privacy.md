# App Privacy answer matrix: en-US

Status: reviewed against the September 10, 2026 App Review hardening changes for the free, local-first launch. Saved App Store Connect answers require separate readback against the exact submitted build; this document does not prove submission or approval.

## Tracking

- Tracking: No
- Reason: the app has no advertising SDK, analytics SDK, cross-app identifier, or network service that receives user activity.

## Data linked to the user

- None.

The app processes photos and camera frames on the device for camera, save, review, share, and local-roll flows. It does not upload them to a developer server or associate them with an account. Apple Photos may download originals from iCloud or sync saved photos according to the user's system settings. System backups and user-initiated sharing are also controlled by the user. These platform behaviors do not mean Filmy Camera operates a cloud photo or analytics service.

## Data not linked to the user

- None declared.

There is no app-operated telemetry or diagnostics upload, contact import, location collection, contacts/calendar access, or account creation in the current build. Camera recovery uses local OSLog diagnostics containing error codes and retry state, not photos, photo identifiers, filenames, device identifiers, or user-entered text. Apple-provided device diagnostics remain governed by system settings.

## Platform access and source evidence

| Capability | User-facing purpose | Source evidence |
| --- | --- | --- |
| Camera | Live preview and capture after the user opens Camera | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CameraService.swift` |
| Photos read | Review frames saved by Filmy Camera in the in-app Roll | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Photos add-only | Save a finished frame after the user taps Save to Photos | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Device motion | Optional horizon level uses gravity values temporarily in memory while the camera is active; motion samples are not saved or uploaded | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CompositionAssistStore.swift`, `FilmyCamera/Views/CameraScreen.swift` |
| File metadata | Inspect sizes and modification dates of app-owned cache files to enforce storage budgets and prune stale entries | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/Services/PhotoLibraryService.swift`, `FilmyCamera/Services/FilmRenderer.swift` |
| Elapsed-time APIs | In-app preview timing, focus ordering, and composition-aid throttling; no boot-time or timing measurements sent off-device | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/Services/CameraService.swift`, `FilmyCamera/Services/CompositionAssistStore.swift`, `FilmyCamera/Views/FilteredCameraPreview.swift` |
| UserDefaults | Store selected recipe, recipe edits, and saved-frame metadata locally | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/ViewModels/CameraViewModel.swift` |

The privacy manifest declares no collected data, no tracking, an empty tracking-domain list, UserDefaults reason `CA92.1`, FileTimestamp reason `C617.1` for app-container file metadata, and SystemBootTime reason `35F9.1` for in-app elapsed-time measurements. `CACurrentMediaTime()` is derived from `mach_absolute_time()`, and Dispatch uptime values use the same clock; these APIs must not be repurposed for fingerprinting or off-device reporting. The horizon on/off preference is stored locally; gravity samples are used only in memory and motion updates stop when the aid or active camera is unavailable. Re-review this matrix if networking, analytics, payments, accounts, crash reporting, or app-operated cloud synchronization is added. The local frame and share caches are excluded from backup, and frame writes request complete file protection. Clearing that cache or uninstalling the app does not delete saved Photos originals. The Settings privacy overview is available offline, with a separate link to the public policy.

## Export compliance

The current build does not implement non-exempt encryption or network services. `ITSAppUsesNonExemptEncryption` is set to `false`; re-evaluate this declaration if networking, custom cryptography, or a third-party SDK that changes the encryption assessment is added.

## Verification and policy sources

Run `python3 scripts/release/validate-app-review.py` for the source contract and use `--app` with the actual Release app bundle for its permissions, manifest, SDK, and test-hook checks. Public-page availability is separately opt-in with `--check-live-urls`. Neither command reads or changes the App Store Connect privacy questionnaire.

- [Apple required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Apple CACurrentMediaTime documentation](https://developer.apple.com/documentation/quartzcore/cacurrentmediatime())
- [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
