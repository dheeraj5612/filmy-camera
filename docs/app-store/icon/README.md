# App icon source — Frame Index (unreleased design branch)

The active app asset catalog uses an original **cut-F index mark**, acid ground and ember punctuation. It is not a camera silhouette, stock aperture symbol or a modified third-party logo. The same normalized F vertices are used by the SwiftUI brand.

## Authoritative sources

- `scripts/design/generate_identity.py`: deterministic, standard-library-only RGB PNG generator.
- `docs/design/frame-index/app-icon.svg`: editable vector master.
- `docs/design/frame-index/mark.svg` and `wordmark.svg`: original path artwork, with no bundled font.
- `FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset`: opaque 1024px default, dark and tinted iOS variants. iOS applies the outer mask; the source is not pre-rounded.

From the repository root:

```sh
python3 scripts/design/generate_identity.py
python3 -m unittest discover -s scripts/testing -p 'test_frame_index_identity.py' -v
# On macOS, validate with the normal project build and existing release check.
scripts/release/validate-project.sh
```

Changing these source assets does not upload a binary, alter signing or publish an App Store release. Verification and small-size proofs are recorded in `docs/design/frame-index/VALIDATION.md`.

## Historical assets — do not export over the current icon

`AppIconMaster.png`, `prompt-initial.txt`, and `prompt-refinement.txt` are retained unchanged as the build 13 raster icon's provenance. That warm camera/amber-iris image is **retired, not the source of the current asset catalog**. `legacy/AppIconSource-build12.svg` is also historical. Previous shipped binaries retain their own assets; no claim is made that this design has been submitted or released.
