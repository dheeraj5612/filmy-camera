#!/usr/bin/env python3
"""Render G7's vector sibling to Filmy's Signal Frame mark; requires Pillow."""
import json
from pathlib import Path
from PIL import Image, ImageCms, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "G7Camera/Assets.xcassets/AppIcon.appiconset"
DOCS = ROOT / "docs/design/g7"
VARIANTS = (
    ("AppIcon-1024.png", "#090909", "#D6FFE2", None),
    ("AppIcon-dark-1024.png", "#090909", "#63FF9A", "dark"),
    ("AppIcon-tinted-1024.png", "#090909", "#F5F5F5", "tinted"),
)
# The same 32-unit construction and square terminals, with G7's green palette.
# An open G sits beside a geometric 7. Match G7Mark in shared SwiftUI code.
POLYGONS = (
    ((1, 7), (11, 7), (11, 11), (5, 11), (5, 21), (7, 21),
     (7, 18), (6, 18), (6, 14), (11, 14), (11, 25), (1, 25)),
    ((13, 7), (22, 7), (22, 11), (17, 25), (13, 25), (18, 11), (13, 11)),
    ((23, 7), (27, 7), (28.5, 12), (30, 7), (34, 7),
     (30.5, 16), (34, 25), (30, 25), (28.5, 20), (27, 25),
     (23, 25), (26.5, 16)),
)


def render():
    ASSETS.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    entries = []
    for filename, background, ink, appearance in VARIANTS:
        icon = Image.new("RGB", (4096, 4096), background)
        draw = ImageDraw.Draw(icon)
        for index, polygon in enumerate(POLYGONS):
            color = "#63FF9A" if appearance is None and index == 1 else ink
            draw.polygon([(368 + x * 96, 512 + y * 96) for x, y in polygon], fill=color)
        icon.resize((1024, 1024), Image.Resampling.LANCZOS).save(
            ASSETS / filename, icc_profile=profile, optimize=True)
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        entries.append(entry)
    (ASSETS / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (ASSETS.parent / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
    paths = "".join('<polygon fill="' + ("#63FF9A" if index == 1 else "#D6FFE2") + '" points="' + " ".join(f"{x},{y}" for x, y in polygon) + '"/>' for index, polygon in enumerate(POLYGONS))
    (DOCS / "icon-master.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><title>G7X Camera Signal Frame icon</title><path fill="#090909" d="M0 0h1024v1024H0z"/><g transform="translate(92 128) scale(24)">' + paths + '</g></svg>\n')
    (DOCS / "README.md").write_text("# G7 identity\n\nOriginal vector G 7 X monogram using Filmy's Signal Frame square terminals and 32-unit construction. G7 has a dark #090909 background, pastel mint #D6FFE2 G/X and neon green #63FF9A 7. Dark mode uses neon on black. Source: `scripts/design/render_g7_identity.py`. Run `python3 scripts/design/render_g7_identity.py` to export opaque 1024px standard, dark and tinted icons. iOS applies the corner mask. Filmy's existing icon is unchanged.\n")

if __name__ == "__main__":
    render()
