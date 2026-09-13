#!/usr/bin/env python3
"""Build original Filmy Frame Index assets using only the Python standard library.

No font, stock icon, network resource or generated photograph is embedded.
Outputs are opaque sRGB PNGs; iOS applies the final app-icon mask itself.
The concave F vertices match FilmyFrameMark in FrameIndexControls.swift.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset"
IDENTITY = ROOT / "docs/design/frame-index"
MARK = [(0.18, 0.14), (0.86, 0.14), (0.86, 0.34), (0.40, 0.34),
        (0.40, 0.45), (0.73, 0.45), (0.73, 0.65), (0.40, 0.65),
        (0.40, 0.84), (0.18, 0.94)]
PALETTES = {
    "AppIcon-1024.png": ((217, 248, 82), (14, 14, 14), (255, 118, 94)),
    "AppIcon-dark-1024.png": ((14, 14, 14), (217, 248, 82), (255, 118, 94)),
    "AppIcon-tinted-1024.png": ((22, 22, 22), (235, 235, 235), (170, 170, 170)),
}
# These are original geometric strokes, not glyphs extracted from a font.
WORDMARK = "M18 59V21Q18 6 36 9M6 29H34M53 29V59M76 9V59M99 59V29M99 37C106 20 124 23 124 39V59M124 37C132 20 150 23 150 39V59M171 29L184 57M198 29L183 65Q179 77 170 77"


def chunk(kind: bytes, content: bytes) -> bytes:
    return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content) & 0xFFFFFFFF)


def scan_intervals(polygon: list[tuple[float, float]], y: float) -> list[tuple[float, float]]:
    intersections = []
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if min(a[1], b[1]) <= y < max(a[1], b[1]):
            intersections.append(a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1]))
    intersections.sort()
    return list(zip(intersections[0::2], intersections[1::2]))


def icon_png(size: int, background: tuple[int, ...], foreground: tuple[int, ...], index: tuple[int, ...]) -> bytes:
    if size <= 0 or size > 4096:
        raise ValueError("Icon size must be between 1 and 4096")
    # The mark occupies a 740/1024 square. Its diagonal terminal is an index
    # cut, not a lens or aperture. Keep plenty of safe space for system masks.
    f = [((140 + x * 740) * size / 1024, (90 + y * 740) * size / 1024) for x, y in MARK]
    swatch = [(x * size / 1024, y * size / 1024) for x, y in [(754, 740), (842, 740), (842, 828), (754, 828)]]
    layers = [(f, foreground), (swatch, index)]
    raw = bytearray()
    samples = 4
    for y in range(size):
        row = bytearray(bytes(background) * size)
        for polygon, color in layers:
            coverage: dict[int, float] = {}
            for sub_y in range(samples):
                for left, right in scan_intervals(polygon, y + (sub_y + 0.5) / samples):
                    for x in range(max(0, math.floor(left)), min(size, math.ceil(right))):
                        coverage[x] = coverage.get(x, 0) + max(0, min(x + 1, right) - max(x, left)) / samples
            for x, amount in coverage.items():
                for channel in range(3):
                    old = row[3 * x + channel]
                    row[3 * x + channel] = round(old * (1 - amount) + color[channel] * amount)
        raw.append(0)  # PNG filter None — deterministic across platforms.
        raw.extend(row)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # RGB, deliberately no alpha.
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"sRGB", b"\x00") + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def build() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    IDENTITY.mkdir(parents=True, exist_ok=True)
    for filename, palette in PALETTES.items():
        (ASSETS / filename).write_bytes(icon_png(1024, *palette))
    images = []
    for filename, appearance in [("AppIcon-1024.png", None), ("AppIcon-dark-1024.png", "dark"), ("AppIcon-tinted-1024.png", "tinted")]:
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)
    (ASSETS / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    points = " ".join(f"{x * 100:g},{y * 100:g}" for x, y in MARK)
    (IDENTITY / "mark.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><title>Filmy Frame Index mark</title><polygon fill="#D9F852" points="{points}"/></svg>\n')
    (IDENTITY / "wordmark.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 208 86"><title>Filmy original wordmark</title><path d="{WORDMARK}" fill="none" stroke="#F5F5F5" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="53" cy="11" r="4.5" fill="#F5F5F5"/></svg>\n')
    icon_points = " ".join(f"{140 + x * 740:g},{90 + y * 740:g}" for x, y in MARK)
    (IDENTITY / "app-icon.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><title>Filmy Frame Index app icon</title><rect width="1024" height="1024" fill="#D9F852"/><polygon fill="#0E0E0E" points="{icon_points}"/><rect x="754" y="740" width="88" height="88" fill="#FF765E"/></svg>\n')
    print(f"Generated 3 opaque 1024px app icons and 3 original SVG masters in {ROOT}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    build()
