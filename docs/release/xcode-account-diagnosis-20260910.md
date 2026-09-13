# Xcode account diagnosis — 2026-09-10

## Finding

Build 15 uploaded successfully and the app was resubmitted; App Store Connect is now **Waiting for Review**.

Xcode still logs a missing `Xcode-Token` for the obsolete Brown-domain Apple ID during build commands. This is a stale local account-cache warning, not a current upload failure.

## Evidence

- `~/Library/Preferences/com.apple.dt.Xcode.plist` retains a Brown-domain account under `DVTDeveloperAccountManagerAppleIDLists/IDE.Prod` and Brown provisioning-team entries alongside the Gmail account.
- `~/Library/Developer/Xcode/DeveloperPortal 7.3.1.db` retains active developer records for both the Gmail and Brown accounts; the Brown record is linked to two teams.
- `FilmyCamera.xcodeproj/project.pbxproj` uses the Gmail-associated team. Build 15 uploaded successfully with this configuration.
- `build/device-release-generic-build-for-testing.log` and `build/device-release-physical-rotation-window-build.log` show the Brown missing-token warning while test builds complete. The prior successful native upload log is `build/pr90-evidence/upload-build12-90_y0o91/xcode-upload.log`.

## Limits and handling

The stale Brown entry is confirmed. A recurring Gmail-session failure is not established: no current Gmail authentication failure was observed, and Keychain credential contents were intentionally not inspected. No product, credential, plist, Keychain, or Xcode-cache files were modified.

Apple documents removing an Apple ID through Xcode’s Accounts preferences: [Add your Apple ID account](https://help.apple.com/xcode/mac/current/en.lproj/devaf282080a.html). If Brown is not visible there, use an explicit user-approved Apple/Xcode account-support path; do not hand-edit the cache or reset Keychain as part of release automation.
