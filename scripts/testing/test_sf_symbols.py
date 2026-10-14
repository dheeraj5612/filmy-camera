"""Portable guard: no SF Symbol newer than the iOS deployment target ships.

Mark availability-guarded newer symbols with a `sf-symbol: guarded` comment on
the same line. Needs macOS CoreGlyphs data; skips elsewhere.
"""
import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLIST = Path(
    "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"
)
MARKER = "sf-symbol: guarded"
KEY_RE = re.compile(r"(?:systemName|systemImage)\s*:\s*")
LITERAL_RE = re.compile(r'"([^"\\\n]*)"')
NAME_RE = re.compile(r"^[a-z0-9]+(\.[a-z0-9]+)*$")
DOTTED_RE = re.compile(r'"([a-z0-9]+(?:\.[a-z0-9]+)+)"')
COND_RE = re.compile(r"^\s*#(if|elseif|else|endif)\b(.*)$")
G7_RE = re.compile(r"\bG7_APP\b")


def version_tuple(text):
    return tuple(int(p) for p in re.findall(r"\d+", text))


def deployment_target():
    text = (ROOT / "project.yml").read_text()
    m = re.search(r'deploymentTarget:\s*\n(?:[ \t]+.*\n)*?[ \t]+iOS:\s*"?([\d.]+)"?', text)
    if not m:
        m = re.search(r'deploymentTarget:\s*"?([\d.]+)"?', text)
    if not m:
        raise AssertionError("iOS deployment target not found in project.yml")
    return version_tuple(m.group(1))


def _wraps_whole(cond):
    """True when the first "(" closes at the last character."""
    depth = 0
    for i, ch in enumerate(cond):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i == len(cond) - 1
    return False


def _strip_parens(cond):
    cond = cond.strip()
    while cond.startswith("(") and _wraps_whole(cond):
        cond = cond[1:-1].strip()
    return cond


def decide(cond):
    """Evaluate a #if condition with G7_APP=false: False, True, or None (unknown)."""
    cond = _strip_parens(cond.split("//")[0])
    if not G7_RE.search(cond):
        return None
    if cond == "G7_APP":
        return False
    if cond.startswith("!") and _strip_parens(cond[1:]) == "G7_APP":
        return True
    if "||" not in cond and "&&" in cond:
        if any(_strip_parens(t) == "G7_APP" for t in cond.split("&&")):
            return False
    return None


def skip_mask(lines):
    """Per-line bool: True when the line is in a definitely-false G7_APP branch
    or carries the guard marker."""
    mask = []
    stack = []  # frames: {"skip": bool, "taken": bool}
    for line in lines:
        m = COND_RE.match(line)
        if m:
            kind, cond = m.group(1), m.group(2)
            if kind == "if":
                v = decide(cond)
                stack.append({"skip": v is False, "taken": v is True})
            elif kind == "elseif" and stack:
                f = stack[-1]
                if f["taken"]:
                    f["skip"] = True
                else:
                    v = decide(cond)
                    f["skip"] = v is False
                    f["taken"] = v is True
            elif kind == "else" and stack:
                f = stack[-1]
                f["skip"] = f["taken"]
            elif kind == "endif" and stack:
                stack.pop()
            mask.append(True)
            continue
        mask.append(any(f["skip"] for f in stack) or MARKER in line)
    return mask


def scan_text(text):
    """Return [(line_no, name, explicit)] for symbol-like literals."""
    lines = text.splitlines()
    mask = skip_mask(lines)
    starts = []
    pos = 0
    for line in text.splitlines(keepends=True):
        starts.append(pos)
        pos += len(line)

    def line_of(off):
        lo, hi = 0, len(starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if starts[mid] <= off:
                lo = mid
            else:
                hi = mid - 1
        return lo

    found = []  # (offset, line_no, name, explicit)
    taken = set()
    for km in KEY_RE.finditer(text):
        kline = line_of(km.start())
        seg_start = km.end()
        window = text[seg_start:seg_start + 200]
        close = window.find(")")
        if close != -1:
            window = window[:close]
        for lm in LITERAL_RE.finditer(window):
            if not NAME_RE.match(lm.group(1)):
                continue
            off = seg_start + lm.start(1)
            ln = line_of(off)
            taken.add(off)
            if mask[kline] or mask[ln]:
                continue
            found.append((off, ln + 1, lm.group(1), True))
    for dm in DOTTED_RE.finditer(text):
        off = dm.start(1)
        ln = line_of(off)
        if off in taken or mask[ln]:
            continue
        found.append((off, ln + 1, dm.group(1), False))
    found.sort()
    return [(ln, name, explicit) for _, ln, name, explicit in found]


def scan_tree(src_dir):
    out = []
    for path in sorted(Path(src_dir).rglob("*.swift")):
        for no, name, explicit in scan_text(path.read_text(errors="replace")):
            out.append((path, no, name, explicit))
    return out


def load_plist():
    try:
        with PLIST.open("rb") as fh:
            data = plistlib.load(fh)
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None
    if not isinstance(data, dict) or not all(k in data for k in ("symbols", "year_to_release")):
        return None
    return data


def newer_than_target(data, found, target):
    syms, years = data["symbols"], data["year_to_release"]
    bad = []
    for path, no, name, _ in found:
        year = syms.get(name)
        if year is None:
            continue
        ios = years.get(year, {}).get("iOS")
        if ios and version_tuple(ios) > target:
            bad.append(f"{path}:{no} {name} (iOS {ios})")
    return bad


class SFSymbolAvailabilityTests(unittest.TestCase):
    def test_scanner_handles_markers_and_g7_blocks(self):
        text = "\n".join([
            'Image(systemName: "star.fill")',
            'let a = "bolt.badge.clock"',
            'Image(systemName: "x.y") // sf-symbol: guarded',
            '#if G7_APP',
            'Image(systemName: "g7.only")',
            '#else',
            'Image(systemName: "kept.else")',
            '#endif',
            '#if !G7_APP',
            '#if DEBUG',
            'Image(systemName: "nested.kept")',
            '#endif',
            '#else',
            'Image(systemName: "g7.else")',
            '#endif',
            'Image(systemName: "after.all")',
        ])
        self.assertEqual(scan_text(text), [
            (1, "star.fill", True),
            (2, "bolt.badge.clock", False),
            (7, "kept.else", True),
            (11, "nested.kept", True),
            (16, "after.all", True),
        ])

    def test_condition_parentheses(self):
        self.assertIs(decide("(G7_APP) && (DEBUG)"), False)
        self.assertIs(decide("!(G7_APP)"), True)
        self.assertIs(decide("(G7_APP)"), False)
        self.assertIsNone(decide("(DEBUG) || (G7_APP)"))
        self.assertIsNone(decide("(A && G7_APP) || B"))

    def test_scanner_multiline_and_conditions(self):
        text = "\n".join([
            'Image(systemName:',                        # 1
            '  on ? "star" : "heart")',                 # 2
            'Image(systemName: // sf-symbol: guarded',  # 3
            '  "new.sym")',                             # 4
            '#if !G7_APP',                              # 5
            'let a = "one.kept"',                       # 6
            '#elseif DEBUG',                            # 7
            'let b = "two.skipped"',                    # 8
            '#else',                                    # 9
            'let c = "three.skipped"',                  # 10
            '#endif',                                   # 11
            '#if G7_APP',                               # 12
            'let d = "four.skipped"',                   # 13
            '#elseif DEBUG',                            # 14
            'let e = "five.kept"',                      # 15
            '#else',                                    # 16
            'let f = "six.kept"',                       # 17
            '#endif',                                   # 18
            '#if G7_APP && DEBUG',                      # 19
            'let g = "seven.skipped"',                  # 20
            '#endif',                                   # 21
            '#if DEBUG || G7_APP',                      # 22
            'let h = "eight.kept"',                     # 23
            '#endif',                                   # 24
        ])
        self.assertEqual(scan_text(text), [
            (2, "star", True),
            (2, "heart", True),
            (6, "one.kept", False),
            (15, "five.kept", False),
            (17, "six.kept", False),
            (23, "eight.kept", False),
        ])

    def test_no_symbol_newer_than_deployment_target(self):
        data = load_plist()
        if data is None:
            self.skipTest("CoreGlyphs name_availability.plist not available")
        bad = newer_than_target(data, scan_tree(ROOT / "FilmyCamera"), deployment_target())
        self.assertEqual(bad, [], "SF Symbols newer than deployment target:\n" + "\n".join(bad))

    def test_explicit_symbol_names_exist(self):
        data = load_plist()
        if data is None:
            self.skipTest("CoreGlyphs name_availability.plist not available")
        target = deployment_target()
        newest = max(
            (version_tuple(v.get("iOS", "0")) for v in data["year_to_release"].values()),
            default=(0,),
        )
        if newest < target:
            self.skipTest("local SF Symbols data older than deployment target")
        missing = [
            f"{p}:{no} {name}"
            for p, no, name, explicit in scan_tree(ROOT / "FilmyCamera")
            if explicit and name not in data["symbols"]
        ]
        self.assertEqual(missing, [], "Unknown SF Symbol names (typo, or newer than this Mac's SF Symbols data; "
            "tag availability-guarded uses with `sf-symbol: guarded`):\n" + "\n".join(missing))


if __name__ == "__main__":
    unittest.main()
