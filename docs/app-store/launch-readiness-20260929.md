# App Store launch readiness and organic discovery

Audit date: 2026-09-29  
Scope: Filmy Camera 1.0.2 free release (`FILMY_MONETIZATION_ENABLED=NO`)

## Current listing decision

Keep the copy in [metadata-en-US.md](metadata-en-US.md) for the first release candidate:

- Name: `Filmy Camera: Film Filters`
- Subtitle: `Retro Photos & Manual Controls`
- Keywords: `analog,vintage,grain,recipes,editor,instant,monochrome,cinema,digital,white balance,focus,exposure`

The metadata validator reports 26/30 name characters, 30/30 subtitle characters, 156/170 promotional-text characters, and 98/100 keyword characters. The current source/tests resolve the catalog to 758 looks across 19 packs: 595 sourced records plus 163 built-in looks, grouped into 10 sourced packs, 7 original creative packs, one camera-foundations pack, and Filmy Essentials. The keyword field is within Apple’s 100-character limit and avoids duplicate name/subtitle/category terms, competitor names, and unsupported camera trademarks. The description leads with editable looks, grain, manual controls, and no account or watermark, which matches the free configuration documented in the privacy and monetization records.

Apple’s current guidance says that name, subtitle, screenshots, and keywords contribute to search relevance; keywords are limited to 100 characters; promotional text does not affect search ranking; and the first one to three screenshots can appear in search results. Source: [Creating Your Product Page](https://developer.apple.com/app-store/product-page/) and [App Store search](https://developer.apple.com/app-store/search/).

Do not add more generic terms just to fill the remaining two keyword characters. There is no measured search-volume or ranking evidence in this repository, so organic-download expectations remain a hypothesis. Revisit the field only after App Store Connect reports impressions, product-page views, first-time downloads, and conversion by storefront/source.

## Release blockers and owners

| Area | Evidence | Gate |
| --- | --- | --- |
| Binary and signing | `docs/release-checklist.md` requires a fresh device archive, archive/IPA validation, and a signed export. | Upload only the validated archive; an upload is not a submission or public release. |
| Screenshots | `metadata-en-US.md` still marks the five-image iPhone 6.5-inch and iPad 13-inch packs as pending. `docs/exhaustive-qa-coverage-20260909.md` records incomplete physical acceptance for histogram, preview gestures, timer, flash, and related camera matrices. | Capture current-build production media, verify every image against the shipped build, and complete the required device acceptance before submission. |
| Privacy and legal | Support and privacy URLs currently return HTTP 200 and redirect to `https://dheeraj5612.com/filmycam-legal/...`. The App Store privacy matrix says saved App Store Connect answers still need readback. | Read back the portal answers and confirm the published policy describes the exact free binary. Do not enable the monetized configuration without the separate legal and SDK review. |
| App review | The review notes in `metadata-en-US.md` describe the current free flow, but physical camera and iPad presentation still require verification. | Test camera permission, Photos save, import, Roll, and iPad full-screen presentation on supported physical devices. |
| Claims | The listing includes 758 looks, 19 packs, 40 MP import, metadata behavior, and supported manual controls. | Recount/verify these claims against the final catalog and binary before submission; remove any claim that differs in the release archive. |

The legal URLs were checked on 2026-09-29 and returned HTTP 200. This check does not prove that the text matches the final binary or that App Store Connect has the same URLs saved.

## Organic launch measurement

Before release, record the App Store Connect date range, storefronts, version, and the baseline values for impressions, product-page views, first-time downloads, total downloads, and product-page conversion. After release, use the same date range length and storefront set for the first comparison. Annotate changes to screenshots, name/subtitle/keywords, version, pricing, featuring, and external coverage so a later lift is not attributed to ASO without evidence.

Use a single public landing link with campaign parameters for owned channels, and keep those parameters out of the App Store keyword field. Ask early users for honest feedback in the normal product flow; do not buy installs, gate reviews, exchange reviews, or use artificial traffic. Treat rank as a diagnostic observation by storefront and query, not as a promised outcome.

## Screenshot and page order

The planned order remains:

1. G7 X Compact import review with a finished photo.
2. Muted Color edit of the same source.
3. Fine Monochrome with Instant Print border.
4. Populated Roll.
5. Saved photo detail.

Use real product screens and one clear benefit per image. Apple recommends screenshots captured from the app UI and says the first one to three should communicate the app’s essence. Do not use a camera-unavailable placeholder, simulated camera preview, private fixture, or unverified result.

## Release status

This audit did not submit metadata, upload a build, change App Store Connect, or alter source/build settings. The local metadata validation passed. The release remains blocked until the binary, current screenshots, physical acceptance, and App Store Connect privacy/readback checks are complete.
