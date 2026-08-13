# App Privacy answer matrix — en-US

Status: reviewed against the current source tree. Enter the answers in App Store Connect after the app record exists; this file is not a substitute for the account-owner submission.

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
| UserDefaults | Store selected recipe, recipe edits, and saved-frame metadata locally | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/ViewModels/CameraViewModel.swift` |

The privacy manifest declares no collected data, no tracking, and UserDefaults reason `CA92.1`. Re-review this matrix if networking, analytics, payments, accounts, crash reporting, or cloud backup is added.

## Export compliance

The current build does not implement non-exempt encryption or network services. `ITSAppUsesNonExemptEncryption` is set to `false`; re-evaluate this declaration if networking, custom cryptography, or a third-party SDK that changes the encryption assessment is added.
