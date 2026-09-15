# Filmy Pro, accounts, and ads

Implemented for the September 15, 2026 monetized candidate. Earlier release records describe their actual free builds and are not changed retroactively. This branch does not activate products, publish legal pages, or change App Store Connect / Firebase / AdMob accounts.

## Access model

| Capability | Free | Apple-confirmed trial / paid Pro |
| --- | --- | --- |
| Full-quality camera photos | 10 per calendar day | Unlimited |
| G7 X Compact, Provia Standard, Acros Monochrome | Included | Included |
| Other film recipes and recipe customization | Locked | Included |
| Manual exposure, white balance, focus and manual lens controls | Locked | Included, hardware permitting |
| Timer, custom framing and advanced composition aids | Locked | Included |
| Import and edit existing photos, print finishes | Locked | Included |
| Previously saved photos, sharing and save retries | Always accessible | Always accessible |
| Ads | Banner in Roll / Settings after consent | No banners or new ad requests |
| Sign-in | Optional Apple or Google | Optional Apple or Google |

The current request supersedes the older watermark proposal: this implementation does **not** add watermarks or degrade free image quality. The camera viewfinder and shutter never contain an ad. A trial is not started on installation or sign-in. The customer explicitly confirms Apple's purchase sheet.

## Billing and trial setup (owner required)

1. In App Store Connect, create a single **auto-renewable, one-month** product in the **Filmy Pro** subscription group. Default identifier: `com.dheeraj.filmycamera.pro.monthly`. Choose the real monthly price, territories and availability. No production price is hardcoded in the app.
2. Add an introductory offer with payment mode **Free Trial**, duration **1 month**. Eligibility is queried from StoreKit and restricted by Apple's subscription-group rules. The paywall only advertises a one-month trial when StoreKit returns exactly that eligible offer. Ineligible customers see the current localized monthly price, not a promised second trial.
3. Complete paid-app agreements, tax/banking, product localization and review screenshot, and submit the subscription with the monetized app version. Enable Billing Grace Period in App Store Connect if desired; verified grace expiration is honored, while billing retry without grace does not grant access.
4. Publish the new privacy policy and update App Store privacy answers, description, age-rating/advertising answers and review notes. Existing hosted free-build disclosures are **not** sufficient for this candidate. Review `docs/app-store/monetized-release.md`.
5. Set `FILMY_LEGAL_READY = YES` in the ignored `Config/Monetization.Local.Release.xcconfig` only after the disclosures are live and reviewed. The default Release configuration deliberately disables purchases and ads pending that approval. Set the real product identifier there if it differs.

StoreKit handles payment authorization, recurring charges, trial conversion, renewal and cancellation. This implementation uses native App Store in-app purchase, not Apple Pay, Google Pay or an external card checkout for digital features. The account used by StoreKit is the customer's Apple Account; signing into Filmy with Google does not create a Google billing relationship. Restore is available to guests. There is no dependency on Firebase for purchases.

Only verified, recognized, non-revoked, non-upgraded transactions with an active expiration or verified grace period unlock access. The app observes transaction updates, refreshes on foreground/significant clock changes and schedules an expiration refresh while open. Canceling auto-renewal retains access until the paid/trial period ends. Pending approval, canceled purchases and failed/unverified purchases do not unlock Pro. Product loading and entitlement reconciliation are coalesced separately. There is no boolean in UserDefaults that unlocks a production trial.

## Apple and Google sign-in (owner required)

1. Create/select a Firebase project and register iOS bundle `com.dheeraj.filmycamera`. Enable **Apple** and **Google** in Firebase Authentication. Firebase validates provider credentials; the app does not trust decoded JWT claims locally.
2. Download the matching **GoogleService-Info.plist** into `FilmyCamera/GoogleService-Info.plist` (ignored by Git). Run XcodeGen after adding it so the file enters the app's resources. This is client configuration, not a server private key.
3. Copy its `REVERSED_CLIENT_ID` into `FILMY_GOOGLE_REVERSED_CLIENT_ID` in the appropriate ignored local xcconfig. The app validates the callback registration before invoking Google Sign-In. Supply a separate matching Firebase app when changing the bundle identifier.
4. Enable **Sign in with Apple** for the App ID and regenerate the distribution provisioning profile. The entitlement is included in the project. Configure Apple's provider identifiers, callback and private signing key in Firebase/Apple's consoles as required by Firebase's Apple setup guide. Never bundle a `.p8`, service account, OAuth client secret or administrative credential.
5. Run physical-device sign-in, cancel, revoked-credential, sign-out, and delete-account checks with real configured provider accounts. Native Apple sign-in uses a cryptographic nonce and state. Google uses its official SDK and branded SwiftUI button.

No account is required to take free photos, buy/restore Pro, or access existing photos. Account creation/deletion is real Firebase Authentication state, not a local profile. In-app deletion reauthenticates, revokes Apple authorization (or disconnects Google), and deletes the Firebase user. It does not delete Apple Photos or silently cancel an App Store subscription. The confirmation explains the separate Manage Subscription action. Signing out or changing provider neither resets quota nor grants/removes Apple-owned subscription access. There is no cloud photo sync or account-based cross-platform entitlement backend in this implementation.

## AdMob setup (owner required)

1. Register Filmy's iOS app in AdMob; create a **banner** ad unit. Add the real app ID and banner ID to the ignored Release xcconfig using `FILMY_ADMOB_APP_ID`, `FILMY_ADMOB_BANNER_ID`, and `FILMY_ADS_ENABLED = YES`.
2. In AdMob Privacy & messaging, publish the applicable consent and privacy-option messages. UMP updates consent before ads, presents required forms, and checks `canRequestAds`. No hand-rolled UserDefaults consent boolean is trusted. Configure appropriate age/content treatment for the actual audience and review the network's publisher policies.
3. Complete AdMob app verification and publisher payment setup, link the correct store listing, and publish AdMob's supplied app-ads.txt entry on the declared developer domain. Follow AdMob's current inventory / SKAdNetwork guidance for any additional demand partners. The project includes Google's SKAdNetwork identifier and **no mediation partners**.
4. Test with the dedicated Google test IDs in Debug. Never click live inventory or put real ad units into automated tests. Release rejects Google's sample publisher IDs even when `FILMY_ADS_ENABLED` is accidentally enabled.

Ads are requested as non-personalized (`npa=1`). No Firebase user ID, email, photo, camera frame, GPS location or custom audience is passed into an ad request. There is no Firebase Analytics product linked and no app-owned ATT/IDFA access. Non-personalized advertising still involves SDK data collection and may require consent; do not describe it as "no data collected." Review Google's SDK privacy manifest and the Xcode aggregate report. Adding tracking or mediation later requires a fresh privacy/ATT review.

Ad initialization is delayed until access resolves to free and the user visits an ad-supported destination. After an upgrade, the banner is hidden/destroyed and no replacement request is issued. An SDK already initialized while free is not falsely claimed to be unloadable; removing the visible banner stops its visible refresh lifecycle. Previously collected SDK data is governed by the published privacy policy.

## Quota semantics and limits

A slot is persisted in Keychain **before** asynchronous capture starts. Camera failure or render failure refunds that slot once. A successfully rendered photo counts once even when Photos permission/storage makes saving fail: retry saves the retained bytes and never charges again. Discarding a successfully captured photo does not refund it. A crash during capture conservatively keeps the reserved charge.

The day is the calendar day in the device time zone pinned on first quota use. A forward midnight resets the allowance; rolling the clock backward or changing time zones cannot manufacture another budget. DST uses the calendar, not a fixed 24-hour window. UI shows the remaining budget. The Keychain record is device-local, excluded from migration to a new device, and independent of sign-in and local image-cache clearing.

This is **not server-authoritative anti-abuse**. It is a per-device allowance, not a global per-person allowance. Device erasure, client modification and deliberate clock fast-forward cannot be defeated by a purely offline client. Strong per-account/cross-device limits require a trusted backend and usually App Attest. Keychain storage errors fail closed for new free captures rather than silently resetting the count. Already rendered and saved images remain available.

## Development and validation

Dependencies are pinned for the repository's Xcode 16.4 lane: Firebase 12.0.0 (Core/Auth only), Google Sign-In 9.0.0, Google Mobile Ads 12.14.0, UMP 3.0.0. The app's iOS 17 minimum is unchanged. The mobile ads package needs UMP below 4.0; do not downgrade it to the original 12.0.0 package, whose upper bound excludes UMP 3.

`xcodegen generate` rebuilds the checked-in project from `project.yml`. Use the **FilmyCameraStoreKit** scheme to run the UI with `StoreKit/Filmy.storekit`. Its **$4.99 is a local test price only**, not a business decision or live price. The normal FilmyCamera scheme does not activate a local StoreKit configuration. The fixture is included in the test bundle, not shipped as app purchase state.

```sh
python3 scripts/monetization/validate.py
bash scripts/monetization/test-policy.sh
xcodegen generate
xcodebuild -project FilmyCamera.xcodeproj -scheme FilmyCamera \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
  -parallel-testing-enabled NO \
  -only-testing:FilmyCameraTests/MembershipPolicyTests \
  -only-testing:FilmyCameraTests/MembershipStoreTests \
  -only-testing:FilmyCameraTests/MembershipStoreKitTests \
  -only-testing:FilmyCameraUITests/MonetizationUITests \
  CODE_SIGNING_ALLOWED=NO test
```

Hosted unit/UI tests use isolated in-memory quota and no live auth/ads. Existing camera tests default to a Debug-only Pro fixture so they continue testing the camera rather than a paywall. `-ui-testing-monetization-free` explicitly exercises the free UI. These launch arguments do not grant access in Release. StoreKit integration tests explicitly opt out of the fixture and exercise StoreKit Test transactions, including trial eligibility, purchase, restore, renewal, refund, expiry, failure and pending approval.

Before release, also validate real-device Apple/Google sign-in/deletion, Google consent (EEA/non-EEA and revoked choices), banner no-fill/offline behavior, trial-to-paid updates while viewing an ad, Apple sandbox restores across devices/reinstall, offline entitlement launch, billing grace/retry, localization, Dynamic Type/VoiceOver, and no change to saved-photo access after expiry. CI alone cannot validate publisher credentials, ad revenue, or App Store approval.

## Primary documentation

- Apple subscriptions: https://developer.apple.com/app-store/subscriptions/
- Apple introductory offers: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions
- Firebase Apple sign-in and deletion: https://firebase.google.com/docs/auth/ios/apple
- Firebase Google sign-in: https://firebase.google.com/docs/auth/ios/google-signin
- AdMob setup: https://developers.google.com/admob/ios/quick-start
- AdMob privacy/UMP: https://developers.google.com/admob/ios/privacy
- AdMob serving modes: https://developers.google.com/admob/ios/privacy/ad-serving-modes
