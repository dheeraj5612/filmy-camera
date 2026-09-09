# App icon source

The build 13 icon is a warm ivory compact camera with an amber iris on an opaque espresso background. The camera silhouette and amber lens remain recognizable at 32 and 60 pixels. It retains the previous icon's warm photographic identity with fewer small details.

## Current source and export

`AppIconMaster.png` is the authoritative generated raster master (1254 x 1254 RGB PNG, no alpha). Export it to the existing universal iOS AppIcon slot using macOS `sips`, from the repository root:

```sh
sips -z 1024 1024 docs/app-store/icon/AppIconMaster.png --out FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
scripts/release/validate-project.sh
```

The exported asset must be 1024 x 1024, RGB, and fully opaque. Leave the outer image square; iOS applies its own rounded mask. No Xcode asset-catalog configuration change is needed.

SHA-256:

| File | SHA-256 |
| --- | --- |
| `AppIconMaster.png` | `856df4b5b6e6f25dbf7da29c9fcf68bc85d86ba52c779e9419affef8d4ab7705` |
| `AppIcon-1024.png` | `5dcc0ba3567520045e3fa5c3422db4c5b763b06e5c0b34800bc2bcfdccbd82c4` |

## Design provenance

Created September 9, 2026 using the built-in `image_gen.imagegen` tool. The prior build 12 icon was inspected and used as a brand reference. One initial generation was followed by a targeted simplification: remove the raised camera hump, strap rings, leather texture, and extra hardware while retaining the amber iris and warm ivory camera body. Exact prompts are preserved in `prompt-initial.txt` and `prompt-refinement.txt`. The model output is not deterministically reproducible from these prompts; use the committed master for faithful exports.

The final generated source was copied without visual changes. `sips` resampling is the only change between the committed master and production export. The resulting asset was visually inspected at 1024, 60, and 32 pixels and checked for dimensions and opacity.

## Retired source

`legacy/AppIconSource-build12.svg` is an unchanged historical source for the former aperture-and-viewfinder icon. It is outside the application resources and is **not** the source of the current icon. Do not render it over the production AppIcon slot. The old production PNG remains available in Git history through build 12.

Build 12's already uploaded binary retains its original icon. This refresh first applies to build 13; changes to store processing, release selection, or publication are recorded separately.
