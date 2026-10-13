# Monetized release: owner review required

This is the proposed replacement for free-build metadata, not evidence of an App Store Connect update. Do not reuse the earlier "every feature free" or "no data collected" answers when submitting this branch.

## Description draft

Filmy Camera combines a camera-first viewfinder with expressive film looks and G7 X-inspired compact-camera color. Shoot full-quality photos with three starter looks and a daily allowance of 10 photos, then keep, view and share your saved images.

Filmy Pro unlocks unlimited photos, the full film library, recipe editing, manual camera controls, advanced shooting tools, photo imports and print finishes. Pro removes ads, including throughout an active free trial. Features depend on camera hardware where applicable.

Eligible customers can start a one-month free trial through the App Store. After the trial, Filmy Pro automatically renews monthly at the price displayed in the app unless canceled. Manage or cancel in Apple Account subscription settings. Free users may see ads in Roll and Settings, never over the camera shutter. Sign in with Apple or Google is optional; no account is required for guest photography or App Store purchases.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: use the reviewed, published policy URL configured in the build.

## Review notes draft

Free capture includes G7 X Compact, Provia Standard and Acros Monochrome, up to 10 captured photos per day on this device. Filmy Pro uses a monthly auto-renewable StoreKit subscription with an eligible one-month introductory free trial. Open Settings > Account & Filmy Pro or Go Pro to see current App Store pricing, restore purchases and manage subscriptions. No Filmy account is required to purchase or restore.

Sign in with Apple and Google are in Settings > Account & Filmy Pro. Signed-in users can delete their account in-app after provider reauthentication. Deleting an account does not remove photos or cancel the separately managed Apple subscription; the confirmation says so.

Capture must be reviewed on a physical device. Existing saved photos and already prepared save retries remain accessible after subscription expiry. Free-tier ads use AdMob with UMP consent; paid and trial access removes the banner. Confirm production provider/product configuration and legal URLs before submitting these notes.

## Privacy answers to review with the actual SDK report

| Data / behavior | Candidate behavior | Review action |
| --- | --- | --- |
| Photos and camera frames | Processed on device; not sent to Firebase/AdMob by this code | Preserve accurate local-processing explanation |
| Name, email, provider/Firebase user ID | Optional account authentication and management; linked to user; no ad targeting by app | Declare collected for app functionality; explain retention/deletion |
| Advertising / device and usage data | AdMob SDK can collect identifiers, IP-derived approximate location, ad interactions and diagnostics, even for non-personalized ads | Inspect SDK privacy report and Google's current disclosures; declare applicable collection and purposes |
| Purchase/entitlement data | Processed with Apple StoreKit; not copied into a Firebase entitlement backend | Review Apple's App Store privacy-question scope for purchases and providers |
| Tracking | App requests non-personalized ads, does not request ATT or pass IDFA / user IDs to ads | Verify actual publisher/SDK settings; do not infer "no tracking" solely from `npa=1`; add ATT before any future tracking configuration |
| Consent and privacy options | UMP, before ad requests; privacy choices exposed when required | Publish applicable AdMob messages and test them |
| Quota | Device-local Keychain, no quota server | Explain daily budget and device-local nature |

No Firebase Analytics or Crashlytics dependency is added. Core/Auth and Google's sign-in/ads SDKs still have their own data behavior. The app privacy manifest now declares account fields; third-party manifests must be included in Xcode's aggregate review.

The owner must publish an updated policy covering these services, purposes, retention, deletion and contact routes. The implementation does not modify the separate legal-site repository. Also review app age rating, advertising declarations, child-audience policy and developer app-ads.txt setup. Only then enable `FILMY_LEGAL_READY` and live ads in the ignored Release configuration.
