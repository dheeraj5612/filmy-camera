#!/usr/bin/env python3
"""Development-only, bounded collector of public camera-setting facts.

No photographs, article prose, paywalled recipes, app databases, or LUTs are
retained. Output is a staging artifact, NOT a production catalog. Normalize,
review source settings and review distribution rights before shipping a record.
Requires beautifulsoup4. Fetches are serial, robots-aware and allowlisted.
"""
import argparse
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from pathlib import Path
from bs4 import BeautifulSoup

AGENT = "FilmyRecipeResearch/1.0 (+https://github.com/dheeraj5612/filmy-camera)"
ROOTS = {
    "fujixweekly.com": [f"https://fujixweekly.com/fujifilm-x-trans-{g}-recipes/" for g in ("v", "iv", "iii", "ii", "i")],
    "film.recipes": ["https://film.recipes/blog/film-recipes-index-a-z/"],
}
KEYS = (
    "Film Simulation", "Dynamic Range", "D Range Priority", "D-Range Priority",
    "Highlight Tone", "Highlights", "Highlight", "Shadow Tone", "Shadows", "Shadow",
    "Color Chrome Effect Blue", "Color Chrome FX Blue", "Colour Chrome FX Blue",
    "Color Chrome Blue", "Color Chrome Effect", "Colour Chrome Effect",
    "Noise Reduction", "High ISO NR", "High ISO Noise Reduction", "Sharpening", "Sharpness",
    "Clarity", "Grain Effect", "Grain Size", "White Balance Shift", "WB Shift",
    "White Balance", "WB", "Exposure Compensation", "Exposure Comp", "Exposure",
    "Mono Colour", "Mono Color", "Monochromatic Color", "Monochromatic Colour", "Monochrome Color", "Toning", "ISO", "Color", "Colour", "Col. Chr. Effect", "Col. Chr. Blue", "EV Comp.", "Grain", "B&W Adjustment",
)
PATTERN = re.compile(r"(?<!\w)(" + "|".join(re.escape(k) for k in sorted(KEYS, key=len, reverse=True)) + r")\s*:\s*", re.I)

def text(node):
    return re.sub(r"\s+", " ", node.get_text(" ", strip=True)).strip()

def setting_blocks(root):
    blocks = []
    for table in root.find_all("table"):
        settings = {}
        for row in table.find_all("tr"):
            cells = row.find_all(["td", "th"])
            if len(cells) >= 2:
                key = text(cells[0]).rstrip(":")
                settings[key] = " | ".join(text(c) for c in cells[1:])[:180]
        if len(settings) >= 5 and any(k.lower() == "film simulation" for k in settings):
            # Keep unknown table fields so normalization can quarantine them,
            # instead of silently losing camera controls.
            blocks.append(settings)
    if blocks:
        return blocks
    for node in root.find_all("p"):
        line = text(node)
        matches = list(PATTERN.finditer(line))
        if len(matches) < 5 or "white balance" not in line.lower():
            continue
        settings = {}
        prefix = line[:matches[0].start()].strip()
        if prefix and len(prefix) < 60:
            settings["Film Simulation"] = prefix
        for i, match in enumerate(matches):
            end = matches[i + 1].start() if i + 1 < len(matches) else len(line)
            settings[match.group(1)] = line[match.end():end].strip()[:180]
        blocks.append(settings)
    return blocks

class Fetcher:
    def __init__(self, delay):
        self.delay = delay
        self.robots = {}
        self.last = 0.0

    def get(self, url, robots=False):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc not in ROOTS:
            raise ValueError("URL outside source allowlist")
        if not robots:
            policy = self.robots.get(parsed.netloc)
            if policy is None:
                policy = urllib.robotparser.RobotFileParser()
                try:
                    rules = self.get(f"https://{parsed.netloc}/robots.txt", robots=True).decode()
                    policy.parse(rules.splitlines())
                except urllib.error.HTTPError as error:
                    if error.code != 404:
                        raise
                    policy.parse([])
                self.robots[parsed.netloc] = policy
            if not policy.can_fetch(AGENT, url):
                raise ValueError("robots.txt disallows URL")
        time.sleep(max(0, self.delay - (time.monotonic() - self.last)))
        self.last = time.monotonic()
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request, timeout=35) as response:
            if urllib.parse.urlsplit(response.url).netloc not in ROOTS:
                raise ValueError("Redirect outside source allowlist")
            payload = response.read(3_000_001)
            if len(payload) > 3_000_000:
                raise ValueError("Page exceeds research byte limit")
            return payload

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("public-settings-staging.json"))
    parser.add_argument("--delay", type=float, default=1.0)
    parser.add_argument("--limit", type=int, default=800)
    args = parser.parse_args()
    fetch = Fetcher(max(0.75, args.delay))
    candidates = {}
    failures = []
    for host, indexes in ROOTS.items():
        for index in indexes:
            try:
                root = BeautifulSoup(fetch.get(index), "html.parser").select_one(".entry-content")
                if root is None:
                    raise ValueError("Article content missing")
                for anchor in root.find_all("a", href=True):
                    url = urllib.parse.urljoin(index, anchor["href"]).split("#")[0].split("?")[0]
                    if urllib.parse.urlsplit(url).netloc != host or not re.search(r"/20\d{2}/\d{2}/\d{2}/", url):
                        continue
                    name = text(anchor)
                    if not name or len(name) > 100:
                        continue
                    if url not in candidates:
                        candidates[url] = {"url": url, "name": name, "indexes": []}
                    candidates[url]["indexes"].append(index)
            except Exception as error:
                failures.append({"url": index, "reason": str(error)})
    output = {"schemaVersion": 1, "records": [], "failures": failures, "candidateCount": len(candidates)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(f"Found {len(candidates)} unique public pages", flush=True)
    for number, (url, candidate) in enumerate(list(candidates.items())[:max(0, min(args.limit, 900))]):
        try:
            payload = fetch.get(url)
            soup = BeautifulSoup(payload, "html.parser")
            root = soup.select_one(".entry-content")
            if root is None:
                raise ValueError("Article content missing")
            blocks = setting_blocks(root)
            if len(blocks) != 1:
                raise ValueError(f"Requires manual review: {len(blocks)} setting blocks")
            # Do not silently approximate capture methods the app cannot implement.
            body = text(root).lower()
            if any(term in body for term in ("double-exposure", "double exposure", "full spectrum", "infrared filter")):
                raise ValueError("Requires unsupported capture method review")
            candidate.update(settings=blocks[0], sourceSHA256=hashlib.sha256(payload).hexdigest(),
                             retrievedOn=time.strftime("%Y-%m-%d", time.gmtime()))
            output["records"].append(candidate)
        except Exception as error:
            output["failures"].append({"url": url, "reason": str(error)})
        if number % 20 == 0:
            print(f"{number + 1}/{len(candidates)} pages; {len(output['records'])} candidate records", flush=True)
            args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2))
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2))
    print(f"Saved {len(output['records'])} records; {len(output['failures'])} review items", flush=True)

if __name__ == "__main__":
    main()
