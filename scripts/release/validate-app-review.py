#!/usr/bin/env python3
"""Validate Filmy Camera's local-first release contract, not Apple approval.

Policy reviewed September 10, 2026. These checks intentionally fail closed when
this version's permissions, data practices, or dependencies change. Review the
product and privacy disclosures before updating the contract.
https://developer.apple.com/app-store/review/guidelines/
https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
"""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from xml.parsers.expat import ExpatError
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PERMISSIONS = {
    "NSCameraUsageDescription", "NSPhotoLibraryUsageDescription",
    "NSPhotoLibraryAddUsageDescription", "NSMotionUsageDescription",
}
REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1"},
}
TEST_MARKERS = (b"-ui-testing", b"FILMY_TEST_DEFAULTS_SUITE", b"XCTestConfigurationFilePath")
LIVE_HOSTS = {"dheeraj5612.github.io", "github.com"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_plist(path):
    data = path.read_bytes()
    # plistlib otherwise silently accepts duplicate XML keys. Reject an
    # ambiguous source manifest rather than approving only its last value.
    if not data.startswith(b"bplist"):
        document = ET.fromstring(data)
        for dictionary in document.iter("dict"):
            keys = [child.text for child in dictionary if child.tag == "key"]
            require(len(keys) == len(set(keys)), f"Duplicate plist key: {path.name}")
    result = plistlib.loads(data)
    require(isinstance(result, dict), f"Expected dictionary plist: {path.name}")
    return result


def validate_manifest(manifest):
    require(set(manifest) == {"NSPrivacyTracking", "NSPrivacyTrackingDomains",
                             "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"},
            "Privacy manifest keys differ from the reviewed local-first contract")
    require(manifest.get("NSPrivacyTracking") is False, "Tracking must explicitly be false")
    require(manifest.get("NSPrivacyTrackingDomains") == [], "Tracking domains must be an empty array")
    require(manifest.get("NSPrivacyCollectedDataTypes") == [], "Collected data needs a new privacy review")
    entries = manifest.get("NSPrivacyAccessedAPITypes")
    require(isinstance(entries, list), "Required-reason API declarations must be an array")
    seen = set()
    for entry in entries:
        require(isinstance(entry, dict), "Required-reason API entry must be a dictionary")
        require(set(entry) == {"NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"},
                "Required-reason API entry has missing or unexpected keys")
        category = entry["NSPrivacyAccessedAPIType"]
        require(isinstance(category, str) and category in REASONS, "Unreviewed required-reason API category")
        require(category not in seen, "Duplicate required-reason API category")
        seen.add(category)
        reasons = entry["NSPrivacyAccessedAPITypeReasons"]
        require(isinstance(reasons, list) and all(isinstance(reason, str) for reason in reasons),
                "Required-reason codes must be strings in an array")
        require(len(reasons) == len(set(reasons)) and set(reasons) == REASONS[category],
                f"Missing or unreviewed reason code for {category}")
    require(seen == set(REASONS), "Missing required-reason API declaration")


def validate_info(info, spec=None):
    declared = {key for key in info if key.endswith("UsageDescription")}
    require(declared == PERMISSIONS, "Missing or unreviewed permission purpose string")
    for key in sorted(PERMISSIONS):
        text = info[key]
        require(isinstance(text, str) and 20 <= len(text.strip()) <= 500 and "$(" not in text,
                f"Permission purpose must be meaningful and resolved: {key}")
        if spec is not None:
            values = re.findall(r"^\s+" + re.escape(key) + r": (.+)$", spec, re.MULTILINE)
            require(values == [text], f"project.yml and Info.plist disagree: {key}")
    require(info.get("ITSAppUsesNonExemptEncryption") is False, "Export compliance requires review")
    require(info.get("NSPhotoLibraryPreventAutomaticLimitedAccessAlert") is True,
            "Limited-library access must use the explicit in-app management action")
    for key in ("NSAppTransportSecurity", "UIBackgroundModes", "LSApplicationQueriesSchemes",
                "NSBonjourServices", "CFBundleURLTypes"):
        require(key not in info, f"New platform capability requires a privacy/release review: {key}")
    if spec is not None:
        require(re.findall(r"^\s+NSPhotoLibraryPreventAutomaticLimitedAccessAlert: (.+)$", spec, re.MULTILINE) == ["true"],
                "project.yml must retain explicit limited-library alert handling")


def field(text, label):
    matches = re.findall(r"^- \*\*" + re.escape(label) + r":\*\* (.+)$", text, re.MULTILINE)
    require(len(matches) == 1, f"Missing or ambiguous metadata field: {label}")
    value = matches[0].strip()
    if value.startswith("`"):
        require(value.count("`") == 2, f"Malformed metadata field: {label}")
        value = value.split("`", 2)[1]
    require(bool(value), f"Empty metadata field: {label}")
    return value


def section(text, heading):
    matches = re.findall(r"^## " + re.escape(heading) + r"\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    require(len(matches) == 1 and bool(matches[0].strip()), f"Missing or ambiguous section: {heading}")
    return matches[0].strip()


def validate_url(url):
    parts = urlsplit(url)
    require(parts.scheme == "https" and parts.hostname in LIVE_HOSTS and not parts.username
            and not parts.password and not parts.query and not parts.fragment and parts.port in (None, 443),
            "Release URLs must use the reviewed public HTTPS hosts without credentials, queries, or fragments")
    return url


def validate_metadata(text):
    for label, limit in (("App name", 30), ("Subtitle", 30), ("Promotional text", 170)):
        require(len(field(text, label)) <= limit, f"{label} exceeds {limit} characters")
    require(len(section(text, "Description")) <= 4000, "Description exceeds 4000 characters")
    require(len(section(text, "App Review notes").encode("utf-8")) <= 4000, "App Review notes exceed 4000 bytes")
    matches = re.findall(r"^`([^`\n]+)`$", section(text, "Keywords"), re.MULTILINE)
    require(len(matches) == 1, "Expected one keyword field")
    keywords = matches[0]
    require(len(keywords.encode("utf-8")) <= 100, "Keywords exceed 100 UTF-8 bytes")
    words = keywords.split(",")
    require(all(len(word) > 2 and word == word.strip() for word in words), "Invalid or empty keyword term")
    require(len(words) == len(set(word.casefold() for word in words)), "Duplicate keywords")
    return {label: validate_url(field(text, label)) for label in ("Support URL", "Marketing URL", "Privacy policy URL")}


def validate_icon(path):
    data = path.read_bytes()
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), "App icon must be PNG")
    offset = 8
    dimensions = None
    ended = False
    while offset + 12 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        require(offset + 12 + length <= len(data), "Truncated PNG icon")
        chunk = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            require(dimensions is None and length == 13, "Invalid PNG header")
            width, height, _, color_type, _, _, _ = struct.unpack(">IIBBBBB", chunk)
            dimensions = (width, height)
            require(color_type in (0, 2, 3), "App icon contains an alpha channel")
        require(kind != b"tRNS", "App icon contains transparency")
        offset += 12 + length
        if kind == b"IEND":
            ended = True
            break
    require(ended and dimensions == (1024, 1024), "App icon must be a complete 1024x1024 PNG")


def validate_source(root):
    info = load_plist(root / "FilmyCamera/Info.plist")
    validate_info(info, (root / "project.yml").read_text())
    manifest = load_plist(root / "FilmyCamera/Resources/PrivacyInfo.xcprivacy")
    validate_manifest(manifest)
    urls = validate_metadata((root / "docs/app-store/metadata-en-US.md").read_text())
    validate_icon(root / "FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    return info, manifest, urls


def validate_built_app(app, source_info, source_manifest, root):
    info = load_plist(app / "Info.plist")
    validate_info(info)
    for key in PERMISSIONS | {"CFBundleDisplayName", "ITSAppUsesNonExemptEncryption",
                              "NSPhotoLibraryPreventAutomaticLimitedAccessAlert"}:
        require(info.get(key) == source_info.get(key), f"Built app differs from reviewed source: {key}")
    require(info.get("CFBundleIdentifier") == "com.dheeraj.filmycamera", "Wrong distribution bundle identifier")
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and executable not in ("", ".", "..")
            and Path(executable).name == executable, "Invalid app executable path")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        require(isinstance(info.get(key), str) and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", info[key]),
                f"Unresolved distribution version: {key}")
    binary = (app / executable).read_bytes()
    require(binary[:4] in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"),
            "Distribution executable is not a Mach-O binary")
    for marker in TEST_MARKERS:
        require(marker not in binary, "Test-only launch behavior found in Release binary: " + marker.decode())
    manifest = load_plist(app / "PrivacyInfo.xcprivacy")
    validate_manifest(manifest)
    require(manifest == source_manifest, "Built privacy manifest differs from reviewed source")
    # Dependencies need their own audit and manifests. This source revision has
    # no third-party SDKs; do not silently accept a new bundled framework.
    frameworks = app / "Frameworks"
    require(not frameworks.exists() or not list(frameworks.glob("*.framework")),
            "New embedded framework requires an SDK/privacy review")
    sdk_spec = importlib.util.spec_from_file_location("filmy_release_sdk", root / "scripts/release/validate-sdk.py")
    sdk = importlib.util.module_from_spec(sdk_spec)
    sdk_spec.loader.exec_module(sdk)
    return sdk.validate_app_info(info)


class ReviewedHTTPSRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def check_live_urls(urls):
    opener = build_opener(ReviewedHTTPSRedirectHandler())
    report = {}
    for label, url in urls.items():
        request = Request(validate_url(url), headers={"User-Agent": "FilmyCamera-Release-Preflight/1.0"})
        try:
            with opener.open(request, timeout=15) as response:
                validate_url(response.geturl())
                require(response.status == 200, f"{label} is not available")
                require(response.headers.get_content_type() == "text/html", f"{label} does not return HTML")
                content = response.read(1_000_001)
                require(0 < len(content) <= 1_000_000, f"{label} returned an empty or oversized page")
        except (OSError, URLError) as error:
            raise ValueError(f"{label} could not be verified; inspect its public availability") from error
        page = content.decode("utf-8", errors="replace").lower()
        require("filmy" in page, f"{label} does not identify this app")
        if label == "Support URL":
            require("mailto:" in page, "Support page must provide a working contact route")
        if label == "Privacy policy URL":
            require("privacy" in page and "photos" in page, "Privacy page is missing app-specific disclosures")
        report[label] = {"url": url, "httpStatus": 200}
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--app", type=Path, help="Inspect an unsigned Release .app or signed archive's .app")
    parser.add_argument("--check-live-urls", action="store_true", help="Also verify public release pages using bounded HTTPS GETs")
    args = parser.parse_args(argv)
    try:
        info, manifest, urls = validate_source(args.root)
        report = {"sourceContract": "passed", "builtApp": "not checked", "liveURLs": "not checked"}
        if args.app:
            report["builtApp"] = validate_built_app(args.app, info, manifest, args.root)
        if args.check_live_urls:
            report["liveURLs"] = check_live_urls(urls)
    except (ValueError, OSError, TypeError, plistlib.InvalidFileException, ExpatError, ET.ParseError) as error:
        print(f"App Review preflight failed: {error}", file=sys.stderr)
        return 1
    print("App Review preflight: " + json.dumps(report, sort_keys=True))
    print("This does not verify App Store Connect answers, device behavior, rights, signing, or Apple approval.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
