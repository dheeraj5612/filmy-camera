# App Privacy answer matrix — en-US

Status: prepared for version 1.0.0, build 15. Saved App Store Connect answers require separate readback; this document does not prove submission.

## Tracking

- Tracking: No
- Reason: the app has no advertising SDK, analytics SDK, cross-app identifier, or network service that receives user activity.

## Data linked to the user

- None.

The app processes photos and camera frames on the device for the requested camera, save, review, share, and local-Roll flows. It does not upload them to a developer server or associate them with an account. Apple Photos may download originals from iCloud or sync saved photos according to the user's system settings. System backups and user-initiated sharing are also controlled by the user; Filmy Camera does not operate a cloud photo or analytics service.

## Data not linked to the user

- None declared.

There is no telemetry, diagnostics upload, contact import, location collection, contacts/calendar access, or account creation in the current build.

## Platform access and source evidence

| Capability | User-facing purpose | Source evidence |
| --- | --- | --- |
| Camera | Live preview and capture after the user opens Camera | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CameraService.swift` |
| Photos read | Review frames saved by Filmy Camera in the in-app Roll; imported photos are selected through Apple's system picker | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Photos add-only | Save a finished frame after a camera capture or when the user saves an edited import | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Device motion | Optional horizon level uses gravity values temporarily in memory while the camera is active; motion samples are not saved or uploaded | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CompositionAssistStore.swift`, `FilmyCamera/Views/CameraScreen.swift` |
| File metadata | Inspect sizes and modification dates of app-owned cache files to enforce storage budgets and prune stale entries | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/Services/PhotoLibraryService.swift`, `FilmyCamera/Services/FilmRenderer.swift` |
| UserDefaults | Store selected recipe, recipe edits, and saved-frame metadata locally | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/ViewModels/CameraViewModel.swift` |

The app uses local elapsed-time APIs that require the privacy-manifest SystemBootTime reason `35F9.1`, in addition to UserDefaults reason `CA92.1` and FileTimestamp reason `C617.1` for app-container file metadata. `CACurrentMediaTime()` in `CompositionAssistStore` is derived from `mach_absolute_time()` and only throttles local composition preview analysis; no boot-time or timing measurement is sent off-device. The horizon on/off preference is stored locally; gravity samples are used only in memory and motion updates stop when the aid or active camera is unavailable. Re-review this matrix if networking, analytics, payments, accounts, crash reporting, or app-operated cloud synchronization is added.

## Export compliance

The current build does not implement non-exempt encryption or network services. `ITSAppUsesNonExemptEncryption` is set to `false`; re-evaluate this declaration if networking, custom cryptography, or a third-party SDK that changes the encryption assessment is added.
