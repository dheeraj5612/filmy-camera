# App Privacy answer matrix — en-US

Status: updated for version 1.0.2 (free release, `FILMY_MONETIZATION_ENABLED=NO`). Saved App Store Connect answers require separate readback; this document does not prove submission.

## Tracking

- Tracking: No
- Reason: 1.0.2 ships with monetization disabled. The free Release binary does not link or embed FirebaseAuth, GoogleSignIn, or GoogleMobileAds (with UMP) and carries none of their Info.plist keys (including `GADApplicationIdentifier`); they are built only into the monetized Debug configuration for a future opt-in membership release, and `python3 scripts/monetization/sdk_gate.py` enforces this. In the free Release `AuthenticationStore` and `AdvertisingStore` are SDK-free stubs that do nothing, so Release never calls `FirebaseApp.configure`, requests UMP consent, or calls `MobileAds.shared.start`. The `MonetizationConfiguration.isEnabled` early-return guards exist only in the monetized configuration. Filmy's own code sends user activity to no analytics SDK, cross-app identifier, or network service.
- `FilmyCamera/Resources/PrivacyInfo.xcprivacy` declares no collected data types (`NSPrivacyCollectedDataTypes` is empty), `NSPrivacyTracking` false, and no tracking domains, matching the free Release. The free Release also omits the Sign in with Apple entitlement (`FilmyCamera/FilmyCamera.Release.entitlements`) and declares no `CFBundleURLTypes`, so no Google sign-in URL scheme is registered (`FILMY_GOOGLE_REVERSED_CLIENT_ID` in `Config/Monetization.Release.xcconfig` is only the value a monetized Release must set). See "Required before any monetized build".

## Required before any monetized build

Do not ship `FILMY_MONETIZATION_ENABLED=YES` in Release until all of these are done. `scripts/monetization/validate.py` fails a monetized Release whose manifest lacks the account and advertising entries below.

1. Add to `NSPrivacyCollectedDataTypes` (each with `NSPrivacyCollectedDataTypeTracking` set per the final ad configuration):
   - `NSPrivacyCollectedDataTypeName`, `NSPrivacyCollectedDataTypeEmailAddress`, `NSPrivacyCollectedDataTypeUserID`: Firebase Auth; linked true; purpose `NSPrivacyCollectedDataTypePurposeAppFunctionality`.
   - `NSPrivacyCollectedDataTypeDeviceID`, `NSPrivacyCollectedDataTypeAdvertisingData`, `NSPrivacyCollectedDataTypeCoarseLocation`, `NSPrivacyCollectedDataTypeOtherUsageData`: AdMob; purpose `NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising`. Add `NSPrivacyCollectedDataTypeProductInteraction` and an analytics purpose only if the SDK configuration enables it.
   - If ads track users (personalized ads or IDFA): set `NSPrivacyTracking` true, list the Google ad domains the SDK contacts in `NSPrivacyTrackingDomains`, and add `NSUserTrackingUsageDescription` plus an ATT prompt. Owner must confirm the domain list from the SDK release in use; it is not recorded here.
2. Set `CODE_SIGN_ENTITLEMENTS = FilmyCamera/FilmyCamera.entitlements` and a real `FILMY_GOOGLE_REVERSED_CLIENT_ID` in `Config/Monetization.Release.xcconfig`; enable Sign in with Apple on the App ID in the developer portal and use a provisioning profile that includes it.
3. Re-answer the App Store Connect App Privacy questionnaire (Contact Info, Identifiers, Usage Data, Coarse Location as applicable) and publish before submission.

## Data linked to the user

- None.

The app processes photos and camera frames on the device for the requested camera, save, review, share, and local-Roll flows. It does not upload them to a developer server or associate them with an account. Apple Photos may download originals from iCloud or sync saved photos according to the user's system settings. System backups and user-initiated sharing are also controlled by the user; Filmy Camera does not operate a cloud photo or analytics service.

## Data not linked to the user

- None declared.

There is no telemetry, diagnostics upload, contact import, contacts/calendar access, or account creation. With When In Use location permission, new camera captures may include a recent location in the saved JPEG and Photos asset. Imported photos retain their original geotags when supplied by the picker. Location stays with the photo on the device and follows the user’s Photos sync and sharing choices; it is not sent to a developer service. The user can deny or revoke location permission in iOS Settings and continue taking photos.

## Platform access and source evidence

| Capability | User-facing purpose | Source evidence |
| --- | --- | --- |
| Camera | Live preview and capture after the user opens Camera | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CameraService.swift` |
| Photos read | Review frames saved by Filmy Camera in the in-app Roll; imported photos are selected through Apple's system picker | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Photos add-only | Save a finished frame after a camera capture or when the user saves an edited import | `FilmyCamera/Info.plist`, `FilmyCamera/Services/PhotoLibraryService.swift` |
| Location | Optional capture geotags after When In Use permission; saved with the photo, never uploaded to a developer service | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CameraService.swift`, `FilmyCamera/Services/PhotoOutputEncoder.swift` |
| Microphone | Audio recorded with capture-mode video (on by default, the user can turn off "Record microphone audio") and with Live Photos only when Live Photo audio is turned on; stored only in the saved media, never uploaded | `FilmyCamera/Info.plist`, `FilmyCamera/CaptureModes/CaptureModesModel.swift`, `FilmyCamera/CaptureModes/CaptureModesEngine.swift`, `FilmyCamera/Services/CameraService.swift` |
| Device motion | Optional horizon level uses gravity values temporarily in memory while the camera is active; motion samples are not saved or uploaded | `FilmyCamera/Info.plist`, `FilmyCamera/Services/CompositionAssistStore.swift`, `FilmyCamera/Views/CameraScreen.swift` |
| File metadata | Inspect sizes and modification dates of app-owned cache files to enforce storage budgets and prune stale entries | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/Services/PhotoLibraryService.swift`, `FilmyCamera/Services/FilmRenderer.swift` |
| Disk space | Check free storage before every capture-mode capture (photo or video) and before developing a clip; warn the user to free at least 1 GB | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/CaptureModes/CaptureMediaStore.swift`, `FilmyCamera/CaptureModes/CaptureModesEngine.swift`, `FilmyCamera/CaptureModes/CaptureImageProcessor.swift` |
| UserDefaults | Store selected recipe, recent looks list (ids only), recipe edits, and saved-frame metadata locally | `FilmyCamera/Resources/PrivacyInfo.xcprivacy`, `FilmyCamera/ViewModels/CameraViewModel.swift` |

The app uses local elapsed-time APIs that require the privacy-manifest SystemBootTime reason `35F9.1`, in addition to UserDefaults reason `CA92.1`, FileTimestamp reason `C617.1` for app-container file metadata, and DiskSpace reason `E174.1` for the free-storage check in `CaptureMediaStore`. Elapsed-time reads include `ProcessInfo.processInfo.systemUptime` (`CameraService`, `SmartRecipeStore`, `FujiShootingController`, `FujiFrameSampler`), `DispatchTime.now().uptimeNanoseconds` (`CameraService`, `SceneAutoAnalyzer`), `CLOCK_MONOTONIC_RAW` in `MembershipPolicy`, and `CACurrentMediaTime()` in `CompositionAssistStore`, which is derived from `mach_absolute_time()` and only throttles local composition preview analysis. All of them only measure elapsed time inside the app (`35F9.1`); no boot-time or timing measurement is sent off-device. The horizon on/off preference is stored locally; gravity samples are used only in memory and motion updates stop when the aid or active camera is unavailable. Re-review this matrix if networking, analytics, payments, accounts, crash reporting, or app-operated cloud synchronization is added.

## Export compliance

The current build does not implement non-exempt encryption or network services. `ITSAppUsesNonExemptEncryption` is set to `false`; re-evaluate this declaration if networking, custom cryptography, or a third-party SDK that changes the encryption assessment is added.
