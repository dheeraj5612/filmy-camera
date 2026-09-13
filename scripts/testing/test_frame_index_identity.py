"""Portable checks for the original, reproducible Frame Index identity."""
import importlib.util
import json
from pathlib import Path
import re
import struct
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generate_identity", ROOT / "scripts/design/generate_identity.py")
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)


class FrameIndexIdentityTests(unittest.TestCase):
    def test_asset_catalog_has_opaque_srgb_1024_default_dark_and_tinted(self):
        catalog = json.loads((identity.ASSETS / "Contents.json").read_text())
        self.assertEqual(len(catalog["images"]), 3)
        variants = set()
        for item in catalog["images"]:
            variants.add(tuple(a["value"] for a in item.get("appearances", [])))
            self.assertEqual(item["idiom"], "universal")
            self.assertEqual(item["platform"], "ios")
            self.assertEqual(item["size"], "1024x1024")
            raw = (identity.ASSETS / item["filename"]).read_bytes()
            self.assertEqual(raw[:8], b"\x89PNG\r\n\x1a\n")
            chunks = {}
            offset = 8
            while offset < len(raw):
                length = struct.unpack(">I", raw[offset:offset + 4])[0]
                kind = raw[offset + 4:offset + 8]
                data = raw[offset + 8:offset + 8 + length]
                crc = struct.unpack(">I", raw[offset + 8 + length:offset + 12 + length])[0]
                self.assertEqual(crc, zlib.crc32(kind + data) & 0xFFFFFFFF)
                chunks[kind] = chunks.get(kind, b"") + data
                offset += length + 12
            width, height, depth, color, _, _, _ = struct.unpack(">IIBBBBB", chunks[b"IHDR"])
            self.assertEqual((width, height, depth, color), (1024, 1024, 8, 2), "RGB only: no premultiplied alpha or pre-rounded icon corners")
            self.assertEqual(chunks[b"sRGB"], b"\x00")
            self.assertEqual(len(zlib.decompress(chunks[b"IDAT"])), (1024 * 3 + 1) * 1024)

        self.assertEqual(variants, {(), ("dark",), ("tinted",)})

    def test_swiftui_mark_and_asset_generator_share_original_vertices(self):
        source = (ROOT / "FilmyCamera/Views/FrameIndexControls.swift").read_text()
        mark = source[source.index("struct FilmyFrameMark"):source.index("struct FilmyWordmark")]
        vertices = [(float(x), float(y)) for x, y in re.findall(r"\.init\(x: ([0-9.]+), y: ([0-9.]+)\)", mark)]
        self.assertEqual(vertices, identity.MARK)
        small = identity.icon_png(32, *identity.PALETTES["AppIcon-1024.png"])
        self.assertEqual(small, identity.icon_png(32, *identity.PALETTES["AppIcon-1024.png"]))

    def test_small_control_ink_contrast_on_neutral_surfaces(self):
        def luminance(rgb):
            channels = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
            return sum(v * w for v, w in zip(channels, (0.2126, 0.7152, 0.0722)))
        def contrast(a, b):
            hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
            return (hi + 0.05) / (lo + 0.05)
        for surface in (0.055, 0.105, 0.145, 0.205):
            background = (surface,) * 3
            for opacity in (1, 0.64, 0.56):
                ink = (0.96 * opacity + surface * (1 - opacity),) * 3
                self.assertGreaterEqual(contrast(ink, background), 4.5)
            for ink in ((0.851, 0.973, 0.322), (0.412, 0.812, 1), (1, 0.463, 0.369)):
                self.assertGreaterEqual(contrast(ink, background), 4.5)
        # Acid buttons use dark text, never white text on lime.
        self.assertGreaterEqual(contrast((0.055,) * 3, (0.851, 0.973, 0.322)), 4.5)


if __name__ == "__main__":
    unittest.main()
