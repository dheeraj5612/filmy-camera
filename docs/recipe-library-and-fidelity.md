# Recipe library and fidelity audit

## Delivered catalog

The catalog contains **743 selectable looks in 19 packs**: **595 source-linked public camera recipes**, **20 Camera Foundations**, and **128 preserved original Filmy looks**. Public-source research considered 655 unique recipe pages; 60 were quarantined because settings or required capture methods could not be interpreted safely. The 595 accepted recipes comprise **319 Film Recipes** entries and **276 Fuji X Weekly** entries. There are 594 distinct normalized control sets; one pair of separately published recipes shares the same primary camera settings. Both retain their source identity. Camera foundations and authored Filmy looks are counted separately, not represented as discovered Internet recipes.

The sources include Kodak, Fujifilm, Ilford, Agfa, cinema, slide, instant, negative, and monochrome *recipe interpretations*. These names do not establish calibrated spectral emulation of the named physical film stock. The app includes no proprietary Fujifilm LUTs, firmware, source photographs, or copied article prose.

## User experience

Camera popup > **Packs** opens **Your quick menu**. The two-level structure avoids putting hundreds of switches on the camera screen. Pack rows display enabled/total counts and a Mixed state. Opening a pack exposes individual recipe switches. Search automatically switches to recipe results and supports names, stock names, public film mode, publisher, source index scope, and source URL.

**Actions** provides Enable all, Hide all, Only my favorites, enable/hide current results, and Restore original quick menu. Bulk changes have one-level Undo. The full catalog remains available through Browse all and capture review. Recipe details show an app-owned sample before/after, published settings, source links and creator-credit navigation, and limitations. The camera's Active popup and Favorites subset honor membership. A compact active search appears when the popup has sufficient vertical room; the full library provides search on smaller layouts.

Membership is independent of favorites, edited recipe data, and current capture selection. Hiding the selected recipe leaves capture unchanged, and an explicit next/previous gesture can move from that hidden anchor into the enabled list. All-hidden is valid and displays recovery controls rather than silently re-enabling a look. Original looks start enabled, and newly introduced packs start hidden. No arbitrary 300- or 500-item truncation exists.

The versioned preference envelope preserves unknown IDs for future catalog compatibility, bounds decoded input, and stores only individual deviations from pack defaults. An explicit pack action clears that pack's exceptions, so Disable pack actually disables every member. Restoring menu defaults does not reset edits or favorites. Catalog IDs use normalized source identity plus a source-URL hash, not array position or retrieval date.

## Source audit and reproducibility

Sources were retrieved on **September 15, 2026 UTC** (September 14 in New York) through public HTML indexes and individual recipe pages. Every shipping source record includes its exact URL, published recipe name, publisher, source-index scope where available, retrieval date, SHA-256 of the retrieved page, retained camera-setting fields, normalized units, and mapping version. The page hash is provenance, not a claim that the website cannot change.

Developer tools:

```sh
python3 -m pip install beautifulsoup4==4.13.4
python3 scripts/recipes/collect_public_settings.py --output /tmp/public-settings-staging.json
python3 scripts/recipes/normalize_catalog.py /tmp/public-settings-staging.json
python3 -m unittest discover -s scripts/recipes -p 'test_*.py' -v
```

Collection is bounded, serial, robots-aware, and restricted to public allowlisted publishers. App-only/paywalled recipes are not collected. Unknown settings, contradictory values, unmapped legacy toning, unsupported custom white balance, ambiguous generation alternatives, infrared conversion, and double exposures require review instead of being guessed. The collector preserves unknown table fields for the normalizer to reject. The checked-in JSON is the runtime dependency; launching the app never scrapes or contacts a publisher. An integrity lock ties the shipping catalog to its reviewed staging data. Re-collection may produce a different catalog and must receive explicit review and a new integrity lock.

Source settings are factual controls. Article copyright, creator attribution, recipe naming, and any commercial redistribution terms still deserve product/legal review before distribution. Publisher links are not a blanket rights grant. Original creator credit remains accessible through the exact recipe page rather than falsely crediting every recipe to a publisher's owner.

## Audit of all 128 existing looks

`original-recipe-audit.csv` inventories every original ID and its base, origin label, and additional finishing controls. The original catalog includes 92 authored creative designs, 17 public-mode-inspired looks, 11 official-recipe-inspired looks, seven community-recipe-inspired looks, and one Canon-inspired compact look. None carries measured hardware calibration.

The audit found **94** original looks with a nonzero exposure adjustment, **96** with halation, **126** with vignette, **114** with grain, and **94** with an additional blue-response adjustment. These are authored creative choices, not necessarily errors, but make those presets unsuitable as neutral camera-mode references. Their IDs and numeric controls are preserved to avoid breaking saved edits or changing the meaning of an old recipe. Shared renderer corrections do change affected rendered pixels, and renderer metadata is therefore bumped from v19 to **v20**.

The new Camera Foundations separate neutral camera controls from creative finishing. The 595 sourced adaptations do not silently inherit arbitrary exposure, halation, vignette, or a second blue treatment. Original-look detail sheets clearly distinguish authored controls from traced camera settings.

## Rendering corrections

| Area | Audited change | Evidence / limitation |
|---|---|---|
| Classic Negative | Replace the prior amber highlight bias with a restrained magenta component; retain cyan/green shadows; gate tint by chroma so a neutral endpoint is not arbitrarily colored. | Fujifilm describes cyan/green in shadows and magenta in highlights. Magnitudes remain original estimates, not measured camera calibration. |
| REALA ACE | Separate its tone signature from Provia and replace fixed saturation suppression with a saturation-dependent response that gently supports low-chroma color and restrains strong chroma. | Manufacturer intent, not an extracted proprietary curve. |
| MONOCHROME filters | Add Yellow, Red, and Green variants, distinct from the ACROS names, completing all 20 public modes in neutral foundations. | Uses documented filter intent and original channel-weight approximations. |
| Source monochromatic color | Preserve WC and MG source axes, including half-step tone settings; invert MG only at the camera-unit import boundary because camera +MG is green while the existing Filmy editor's positive axis is magenta. | Golden Emerald Mono fixture and decoded-pixel directional regression test. Existing saved editor values are not inverted. |
| Public recipe fields | Retain abbreviated Color Chrome, FX Blue, exposure advice, and Mono Colour fields; quarantine ambiguous alternatives. | Every shipping control record is reproducible from its retained source-setting fields. |
| Capture vs rendering | Source ISO and exposure-compensation advice remain visible but are not applied as a second exposure to already exposed phone pixels. | Sensor headroom, analog gain, lens response and metering cannot be reconstructed from a processed image. |

Public references:

- [Fujifilm X-T5 image-quality controls](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/)
- [Fujifilm Classic Negative description](https://www.fujifilm-x.com/global/products/film-simulation/classic-neg/)
- [Fujifilm REALA ACE description](https://www.fujifilm-x.com/global/products/film-simulation/reala-ace/)
- [Fuji X Weekly Kodachrome 64](https://fujixweekly.com/2020/05/27/my-fujifilm-x100v-kodachrome-64-film-simulation-recipe/)
- [Film Recipes Kodak Gold II](https://film.recipes/2026/07/19/kodak-gold-ii-classic-kodak-film-recipe/)
- [Film Recipes Emerald Mono](https://film.recipes/2022/08/01/emerald-mono-a-toned-mono-for-nature/)

## Accuracy boundary and next calibration gate

These are **source-traced, independently rendered approximations**, not pixel-identical Fujifilm camera output. ACROS and MONOCHROME still share aspects of the parametric monochrome curve and channel-weight model; proprietary ISO-dependent grain/noise and exact sensor spectral response are not reproduced. White balance operates after the phone's own processing. Dynamic Range modes reshape available tones but cannot recover clipped highlights. Kelvin uses an explicit daylight-relative approximation. Camera-generation differences and alternate settings remain in the source record; the phone is not described as an X-Trans sensor.

A genuine camera-match acceptance gate needs owned matched captures: a color target and neutral ramps, natural skin/foliage/sky, daylight/tungsten/mixed/low-light scenes, locked exposure/WB and documented camera/lens/firmware/ISO, and RAW plus in-camera JPEG for each mode. Fit the mapping on training scenes and assess held-out scenes using perceptual color error, neutral-axis error, tone/headroom, skin-hue stability, and texture/grain across print scales. Store reference license/consent, capture metadata and profile version with results. No numerical Delta E, matched-camera calibration, or device frame-rate claim has been made in this change because that evidence was not collected.

## Verification

Portable tests validate retained source facts, normalization, stable identity, duplicate handling, malformed settings, bounds, monochrome axes, and the catalog hash. Foundation-only Swift execution additionally verifies all 743 actual model instances, every editor control's bounds, Codable round trips, source completeness, pack partitioning and all/none/mixed membership. These checks do not compile the iOS UI or exercise Core Image.

The mandatory macOS catalog workflow now runs **167 XCTest cases**, including new model/persistence and directional-control cases. Two catalog cases loop across all 595 sourced recipes and all 20 foundations; together with the original 128 cases they exercise every look on an app-owned daylight image, synthetic color chart and low-light fixture, with preview/photo processing, encoded JPEG export and provenance/privacy checks. Per-recipe contact sheets are retained as CI artifacts. The iPhone/iPad UI evidence workflow adds pack management, all/none/undo, persistence, individual search switches, source details and actual simulator screenshots. Workflow definitions are not evidence of success; inspect the PR's result bundles and screenshots before claiming a passed iOS validation or merging.
