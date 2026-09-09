# App Privacy answer matrix — en-US

Status: prepared for version 1.0.0, build 12 and reviewed against validated source e73c5ee. Saved App Store Connect answers require separate readback; this document does not prove submission.

## Tracking

- Tracking: No
- Reason: the app has no advertising SDK, analytics SDK, cross-app identifier, or network service that receives user activity.

## Data linked to the user

- None.

Photos and camera frames remain on the device and are used only for the requested camera, save, review, share, and local-roll flows. The app does not upload them or associate them with an account.

## Data not linked to the user

- None declared.

There is no telemetry, diagnostics upload, contact import, location collection, contacts/calendar access, or account creation in the current build.

## Platform access and source evidence

| Capability | User-facing purpose | Source evidence |
| --- | --- | --- |
| Camera | Live preview and capture after the user opens Camera | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CameraService.swift` |
| Photos read | Review frames saved by Filmy Camera in the in-app Roll | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Photos add-only | Save a finished frame after the user taps Save to Photos | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Device motion | Optional horizon level uses gravity values temporarily in memory while the camera is active; motion samples are not saved or uploaded | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CompositionAssistStore.swift`, `FilmyCamera/Views/CameraScreen.swift` |
| File metadata | Inspect sizes of files in the app-owned local frame cache to enforce its storage budget | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| UserDefaults | Store selected recipe, recipe edits, and saved-frame metadata locally | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/ViewModels/CameraViewModel.swift` |

The privacy manifest declares no collected data, no tracking, UserDefaults reason `CA92.1`, and FileTimestamp reason `C617.1` for app-container file metadata. The horizon on/off preference is stored locally; gravity samples are used only in memory and motion updates stop when the aid or active camera is unavailable. Re-review this matrix if networking, analytics, payments, accounts, crash reporting, or cloud backup is added.

## Export compliance

The current build does not implement non-exempt encryption or network services. `ITSAppUsesNonExemptEncryption` is set to `false`; re-evaluate this declaration if networking, custom cryptography, or a third-party SDK that changes the encryption assessment is added.
