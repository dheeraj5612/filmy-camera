#!/usr/bin/env python3
"""Render the original Signal Frame icon. Development-only: requires Pillow.

The application has no new dependency. Geometry mirrors FilmyMark in SwiftUI.
Outputs are opaque sRGB, full-bleed square PNGs; iOS owns the corner mask.
"""
from __future__ import annotations

import json
from pathlib import Path
from PIL import Image, ImageCms, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset"
DOCUMENTS = ROOT / "docs/design/signal-frame"
POLYGONS = (
    ((4, 3), (28, 3), (28, 9), (10, 9), (10, 29), (4, 29)),
    ((14, 13), (28, 13), (28, 19), (20, 19), (20, 25), (14, 25)),
)
VARIANTS = (
    ("AppIcon-1024.png", "#FF7854", "#090909", None),
    ("AppIcon-dark-1024.png", "#090909", "#FF7854", "dark"),
    ("AppIcon-tinted-1024.png", "#090909", "#F5F5F5", "tinted"),
)


def render() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    DOCUMENTS.mkdir(parents=True, exist_ok=True)
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    images = []
    for filename, background, ink, appearance in VARIANTS:
        image = Image.new("RGB", (4096, 4096), background)
        draw = ImageDraw.Draw(image)
        # 32-unit construction on a centered 768px field. Its asymmetrical
        # inner frame forms an F without borrowing a lens/aperture pictogram.
        for polygon in POLYGONS:
            draw.polygon([(512 + x * 96, 512 + y * 96) for x, y in polygon], fill=ink)
        image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
        image.save(ASSETS / filename, icc_profile=profile, optimize=True)
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)
    (ASSETS / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    paths = "".join('<polygon points="' + " ".join(f"{x},{y}" for x, y in p) + '"/>' for p in POLYGONS)
    (DOCUMENTS / "mark.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="#FF7854"><title>Filmy Signal Frame — original F monogram</title>' + paths + '</svg>\n')
    (DOCUMENTS / "icon-master.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><title>FilmyCam Signal Frame icon master</title><path fill="#FF7854" d="M0 0h1024v1024H0z"/><g transform="translate(128 128) scale(24)" fill="#090909">' + paths + '</g></svg>\n')


if __name__ == "__main__":
    render()
