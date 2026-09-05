# Monetization roadmap

Status: future product direction recorded September 5, 2026. This is a plan, not implemented behavior. Build 8 has no paywall, subscription trial, or export watermark.

## Confirmed direction

Most features will require a premium monthly subscription. A free trial will let people experience the premium app, and images exported by the free version will carry a watermark. Camera quality, speed, and an uncluttered shooting experience remain product priorities. The September 5 follow-up confirms monthly billing and a premium tier combining film/G7X tools with advanced camera capabilities; see the [premium camera vision](premium-camera-vision.md) for the staged scope and quality targets.

## Proposed experience

The following allocation is a starting proposal, not a finalized price or feature catalog.

| Access | Proposed features | New image exports |
| --- | --- | --- |
| Free | A useful camera, one signature G7 X Compact look and a small starter film selection, basic import/review, and access to existing Roll images | Full-quality image with a small Filmy watermark |
| Active trial | All features included in the paid tier, including premium looks and tuning | No watermark |
| Premium monthly | Full film/G7X collection, advanced recipe tuning, and advanced capture/editing tools as they ship | No watermark |

Free should demonstrate the signature look well enough to earn an upgrade. Avoid adding a second quality penalty such as deliberately poor resolution or degraded color. Keep already-saved images accessible after a trial or subscription ends.

Offer an upgrade when someone selects a premium tool or asks for a clean export. Keep the shutter and review free of recurring purchase interruptions. Show a dismissible purchase sheet with a clear route back to free use, restore purchases, and subscription management where applicable. Preserve the pending photo when a purchase is cancelled, delayed, or fails.

Use a restrained, readable Filmy mark and show its actual placement in review before export. Explain that free exports include it before the first save. A trial should begin through an explicit redemption flow, not silently on first launch.

## Commercial decisions still open

- Monthly billing is confirmed. Price and trial duration remain open. Annual or lifetime alternatives are not part of the confirmed model.
- Exact free recipe/tool allocation, watermark design, and whether early users receive grandfathered access.
- Whether upgrading can create a clean version of an earlier free export. The current app retains a source only during review and stores flattened JPEGs in the Roll. Removing a baked-in watermark later requires a retained clean source; do not promise this until a storage and re-export design exists.
- The release cadence for continuing feature/content improvements. Apple requires ongoing value for auto-renewable subscriptions, and access must work across the customer's supported devices. [App Review Guidelines, 3.1.2](https://developer.apple.com/app-store/review/guidelines/#subscriptions)

Use an App Store introductory free trial for the monthly subscription. Apple allows only one introductory offer redemption per subscription group; eligibility comes from Apple, not an installation timer. Display the actual duration, monthly renewal price, and automatic renewal terms before redemption. [Apple introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions), [subscription purchase guidance](https://developer.apple.com/app-store/subscriptions/)

## Implementation plan for the monetized release

1. **Centralize access policy.** Introduce an injectable StoreKit 2 entitlement service and a single capability catalog used by recipe selection, tuning, and export. Consume verified transactions and updates, support restore, and model loading, purchase pending, active trial/paid, expiry, refund/revocation, and applicable billing grace states. A network error alone must not revoke a previously verified, still-valid entitlement. Cancellation of renewal keeps access until the verified period ends.
2. **Keep commerce off the camera path.** Load products and refresh access asynchronously. Read a local access snapshot in controls and export; never call StoreKit per preview frame. Propose on-device image processing and Apple-managed purchases without a mandatory image server, additional sign-in, advertising SDK, or paid entitlement service. Add hosted services only for a demonstrated requirement.
3. **Apply export policy once.** Compose the watermark after the selected look, final crop, and orientation, before final JPEG encoding. The current Save path can reuse an already-rendered JPEG, so enforce policy for both cached and newly rendered output; a change only inside the renderer would miss that path. Use image-relative sizing and inset so portrait, landscape, front-camera, and imported images are consistent. Integrate this with the existing export render where practical to avoid another full-size decode/encode. Keep originals unchanged.
4. **Make save and share agree.** Every new export path must use the same policy and bytes, including Photos, local cache, and any direct review sharing. Share existing completed Roll files as saved: previously clean paid or pre-monetization exports stay clean, and existing free exports stay watermarked. Original comparison and preview caches must never supply an unintended clean free export.
5. **Preserve retry semantics.** Resolve feature access and freeze export policy when the user confirms export. Cache the completed output and policy together; a failed Photos write retries those exact bytes without another watermark. If the user upgrades while still in review, offer an explicit clean re-render from the retained source. A look change or new export resolves access again. Trial expiry must preserve the current photo and explain available save options rather than silently discarding edits.
6. **Activate only in a tested release.** Implement first with local StoreKit configuration, then sandbox/TestFlight. Configure real products and trial offers after commercial decisions are made. Update store descriptions, screenshots, terms, privacy disclosures as applicable, and review notes together with the monetized binary. Existing build and release records must continue describing their actual free behavior.

These are proposed engineering contracts. Product identifiers, paid feature mappings, and migration behavior still need to be finalized before enabling them.

## Acceptance coverage to add with implementation

| Layer | Required evidence |
| --- | --- |
| Unit | Capability decisions for every access state; verified versus unverified purchases; trial eligibility; cancellation versus expiry; refund and grace rules; export policy and retry identity |
| Rendering | Watermark legibility and bounds across orientation/crop/front camera/import sizes; paid/trial pixels remain unchanged by watermark logic; no double mark or extra lossy encode on retry; source and provenance preserved |
| Integration | Shared policy across capture/import/Photos/cache/share; cached output invalidation after a new look or explicit clean re-export; preserved photo after failed or pending purchase/save |
| StoreKit and UI | Eligible and ineligible trial; purchase success/cancel/pending/failure; restore after reinstall and on a second supported device; offline launch; renewal, expiration and revocation; accessible/localized terms; dismissible paywall and intact review |
| Device E2E | Free capture and import save visibly watermarked images in Photos and Roll; eligible trial and paid saves are clean; share matches saved bytes; downgrade keeps existing files; iPhone and iPad layouts |
| Performance | Compare export latency, peak memory, launch, and preview frame pacing with the same device scenes before and after commerce changes; verify no entitlement work occurs per frame |

Keep deterministic policy/rendering tests in the normal suite. Run StoreKit integration and device acceptance when their inputs change or for a release; this documentation change alone does not warrant rebuilding the app.
