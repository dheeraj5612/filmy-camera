#!/usr/bin/env python3
"""Keep the ad and sign-in SDKs out of free builds, and prove it.

  sdk_gate.py source                                      every SDK import sits inside #if FILMY_MONETIZATION_SDKS
  sdk_gate.py app [--expect auto|free|monetized] <app>    scan a built FilmyCamera.app
  sdk_gate.py plist --write|--check                       Config/Info.Monetized.plist == FilmyCamera/Info.plist + the 7 monetized keys

`app` exits 0 with one PASS line when the built bundle matches the expectation, 1 with every residue listed.
`auto` reads FilmyMonetizationEnabled from the built Info.plist.
Python 3 standard library only.
"""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from xml.parsers.expat import ExpatError

ROOT = Path(__file__).resolve().parents[2]
CONDITION = "FILMY_MONETIZATION_SDKS"
# Swift module families the SDK-backed files import, matched by prefix (submodules and sibling products such as
# FirebaseAuthInterop included). The prefix match is intentionally strict: a false positive (a non-SDK module
# whose name starts with one of these, e.g. AppAuthorizationKit) is acceptable, a miss is not. The app has no
# module of its own with any of these names.
SDK_MODULE_FAMILIES = ("Firebase", "GoogleSignIn", "GoogleMobileAds", "UserMessagingPlatform",
                       "GoogleUserMessagingPlatform", "AppAuth", "GTMAppAuth", "GTMSessionFetcher",
                       "GoogleUtilities", "GoogleAppMeasurement", "FBLPromises", "AppCheck", "RecaptchaInterop",
                       "Promises", "GoogleDataTransport", "GoogleAdsOnDeviceConversion", "nanopb")
# Any mix of attributes (with optional arguments) and access levels, an optional import kind, then the module.
IMPORT_SDK = re.compile(
    r"^\s*(?:(?:@\w+(?:\([^)]*\))?|public|internal|package|private|fileprivate)\s+)*import\s+"
    r"(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?(?:" + "|".join(SDK_MODULE_FAMILIES) + r")\w*")
# Keys that only the SDKs read. Monetized builds carry all six. Free builds carry none, and also not the
# banner unit slot (FilmyAdMobBannerID), whose only reader sits behind the SDK-backed branch.
SDK_PLIST_KEYS = (
    "GADApplicationIdentifier", "GADDelayAppMeasurementInit", "FirebaseAnalyticsCollectionEnabled",
    "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS", "SKAdNetworkItems", "CFBundleURLTypes",
)
FREE_ABSENT_KEYS = SDK_PLIST_KEYS + ("FilmyAdMobBannerID",)
# Keys that must read exactly NO in a free build.
FREE_NO_KEYS = ("FilmyMonetizationEnabled", "FilmyAdsEnabled")
FREE_PLIST = ROOT / "FilmyCamera" / "Info.plist"
MONETIZED_PLIST = ROOT / "Config" / "Info.Monetized.plist"
# The 7 keys the monetized plist adds to the generated free plist.
MONETIZED_EXTRA = {
    "FilmyAdMobBannerID": "$(FILMY_ADMOB_BANNER_ID)",
    "GADApplicationIdentifier": "$(FILMY_ADMOB_APP_ID)",
    "GADDelayAppMeasurementInit": True,
    "FirebaseAnalyticsCollectionEnabled": False,
    "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS": False,
    "CFBundleURLTypes": [{"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": ["$(FILMY_GOOGLE_REVERSED_CLIENT_ID)"]}],
    "SKAdNetworkItems": [{"SKAdNetworkIdentifier": "cstr6suwn9.skadnetwork"}],
}

# SDK symbol and class prefixes plus SDK-only strings, grouped by SDK. Objective-C class names and Swift
# module names survive symbol stripping in the executable's string tables. Why each token is safe: none is a
# substring of a name or string the app defines (AdvertisingStore, MonetizationBanner, AuthenticationStore,
# its own settings and copy). The app's own types never start with FIR, GID, GAD, UMP, GUL, GTM, OID or FBL
# followed by the rest of the token, and the app names no module called Firebase*, GoogleSignIn*,
# GoogleMobileAds or UserMessagingPlatform.
SDK_FAMILIES = {
    # FIRApp, FIRAuth, FIROptions: Firebase class prefix FIR + class name; FirebaseCore/FirebaseAuth: module names.
    "firebase": (b"FIRApp", b"FIRAuth", b"FIROptions", b"FirebaseCore", b"FirebaseAuth"),
    # GIDSignIn, GIDConfiguration: Google Sign-In class prefix GID + class name; GoogleSignInSwift: module name.
    "google-sign-in": (b"GIDSignIn", b"GIDConfiguration", b"GoogleSignInSwift"),
    # GADMobileAds, GADBannerView, GADRequest: AdMob prefix GAD + class name; GoogleMobileAds: module name.
    "google-mobile-ads": (b"GADMobileAds", b"GADBannerView", b"GADRequest", b"GoogleMobileAds"),
    # UMPConsentInformation, UMPConsentForm: UMP prefix + class name; UserMessagingPlatform: module name.
    "user-messaging-platform": (b"UMPConsentInformation", b"UMPConsentForm", b"UserMessagingPlatform"),
    # Shared Google utility pods that only the SDKs pull in: GULAppDelegateSwizzler and GULLogger (GoogleUtilities),
    # GTMSessionFetcher (GTMSessionFetcher), OIDAuthState (AppAuth), FBLPromise (PromisesObjC).
    "google-utilities": (b"GULAppDelegateSwizzler", b"GULLogger", b"GTMSessionFetcher", b"OIDAuthState",
                         b"FBLPromise"),
}
SDK_TOKENS = re.compile(b"|".join(re.escape(token) for tokens in SDK_FAMILIES.values() for token in tokens))
# Frameworks a monetized build embeds.
SDK_FRAMEWORKS = ("GoogleMobileAds", "UserMessagingPlatform")
# Families a monetized build must show. The utility family is not required: it is a transitive detail.
MONETIZED_FAMILIES = ("firebase", "google-sign-in", "google-mobile-ads", "user-messaging-platform")


def source_problems():
    problems = []
    importing = IMPORT_SDK
    for path in sorted(ROOT.glob("FilmyCamera*/**/*.swift")):
        stack = []  # one entry per open #if: True while inside the SDK branch
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            text = line.strip()
            if text.startswith("#if"):
                stack.append(text.split("//")[0].split() == ["#if", CONDITION])
            elif text.startswith("#else") or text.startswith("#elseif"):
                if stack:
                    stack[-1] = False
            elif text.startswith("#endif"):
                if stack:
                    stack.pop()
            elif importing.match(line) and not any(stack):
                problems.append(f"{path.relative_to(ROOT)}:{number}: SDK import outside #if {CONDITION}")
    return problems


def expected_monetized_plist():
    expected = plistlib.loads(FREE_PLIST.read_bytes())
    expected.update(MONETIZED_EXTRA)
    return expected


def plists_equal(left, right):
    """Type-strict: plistlib dicts compare integer 1 equal to boolean True, the serialized bytes do not."""
    return plistlib.dumps(left, sort_keys=True) == plistlib.dumps(right, sort_keys=True)


def unresolved_settings(value, path="Info.plist"):
    """Yield the path of every string in a plist value that still holds a $( build setting."""
    if isinstance(value, str):
        if "$(" in value:
            yield path
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from unresolved_settings(item, f"{path}[{key}]")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from unresolved_settings(item, f"{path}[{index}]")


def plist_problems():
    problems = []
    free = plistlib.loads(FREE_PLIST.read_bytes())
    problems += [f"{FREE_PLIST.relative_to(ROOT)} must not hold {key}" for key in MONETIZED_EXTRA if key in free]
    if not MONETIZED_PLIST.exists():
        problems.append(f"{MONETIZED_PLIST.relative_to(ROOT)} is missing (run: sdk_gate.py plist --write)")
    elif not plists_equal(plistlib.loads(MONETIZED_PLIST.read_bytes()), expected_monetized_plist()):
        problems.append(f"{MONETIZED_PLIST.relative_to(ROOT)} differs from {FREE_PLIST.relative_to(ROOT)} plus the "
                        "monetized keys (run: sdk_gate.py plist --write)")
    return problems


def linked_sdk_frameworks(images):
    """Names in SDK_FRAMEWORKS that some image links dynamically (an `otool -L` load command <name>.framework/<name>)."""
    linked = set()
    for image in images:
        listing = subprocess.run(["otool", "-L", str(image)], check=True, capture_output=True, text=True).stdout
        linked.update(name for name in SDK_FRAMEWORKS if re.search(rf"{name}\.framework/{name}\b", listing))
    return linked


def app_scan(app):
    """Return (residue items, tokens found per family, executable path, Info.plist dict, dynamically linked SDK frameworks)."""
    found = []
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if not isinstance(info, dict):
        raise ValueError("Info.plist is not a dictionary")
    executable = app / info["CFBundleExecutable"]
    found += [f"Info.plist key {key}" for key in FREE_ABSENT_KEYS if key in info]
    found += [f"Info.plist key {key} is not exactly NO" for key in FREE_NO_KEYS if info.get(key) != "NO"]
    found += [f"resource bundle {path.name}" for path in sorted(app.rglob("*.bundle"))]
    # The free app embeds no framework, extension or loose dylib. Debug builds legitimately hold
    # <name>.debug.dylib and the Xcode previews stub __preview.dylib beside the launcher.
    # Only these two names, and only directly in the app root, are allowed. The same names deeper are residue.
    allowed = {path for path in app.glob("*.dylib") if path.name.endswith(".debug.dylib") or path.name == "__preview.dylib"}
    found += [f"embedded {path.relative_to(app)}" for path in sorted(app.rglob("*.framework"))]
    found += [f"embedded {path.relative_to(app)}" for path in sorted(app.rglob("*.appex"))]
    found += [f"embedded {path.relative_to(app)}" for path in sorted(app.rglob("*.dylib")) if path not in allowed]
    found += [f"privacy manifest {path.relative_to(app)}" for path in sorted(app.rglob("PrivacyInfo.xcprivacy"))
              if path != app / "PrivacyInfo.xcprivacy"]
    found += [f"file {path.relative_to(app)}" for path in sorted(app.rglob("GoogleService-Info.plist"))]
    # Debug builds keep the code in <name>.debug.dylib beside a thin launcher; scan every allowed dylib too.
    images = [executable] + sorted(allowed)
    tokens = {match for image in images for match in SDK_TOKENS.findall(image.read_bytes())}
    families = {name: sorted(t.decode() for t in tokens if t in values) for name, values in SDK_FAMILIES.items()}
    found += [f"executable string {token}" for token in sorted(t.decode() for t in tokens)]
    load = "".join(subprocess.run(["otool", "-l", str(image)], check=True, capture_output=True, text=True).stdout
                   for image in images)
    if "__objc_nlclslist" in load:
        found.append("executable section __objc_nlclslist (+load classes)")
    return found, families, executable, info, linked_sdk_frameworks(images)


def check_app(app, expect):
    try:
        found, families, executable, info, linked = app_scan(app)
        size = executable.stat().st_size
    except (OSError, KeyError, TypeError, ValueError, ExpatError, subprocess.CalledProcessError) as error:
        reason = f"missing key {error}" if isinstance(error, KeyError) else str(error)
        print(f"sdk-gate: FAIL cannot read {app}: {type(error).__name__}: {reason}")
        return 1
    if expect == "auto":
        expect = "monetized" if info.get("FilmyMonetizationEnabled") == "YES" else "free"
    if expect == "free":
        if found:
            print("sdk-free: FAIL", len(found), "residue item(s)")
            print("\n".join("  " + item for item in found))
            return 1
        print(f"sdk-free: PASS {app.name} executable={size} bytes, 0 SDK residue items")
        return 0
    missing = [f"executable strings of {name}" for name in MONETIZED_FAMILIES if not families[name]]
    missing += [f"Info.plist key {key}" for key in SDK_PLIST_KEYS if key not in info]
    # Required only when an image links the framework dynamically; a static link leaves no directory behind.
    missing += [f"Frameworks/{name}.framework" for name in SDK_FRAMEWORKS
                if name in linked and not (app / "Frameworks" / f"{name}.framework").is_dir()]
    missing += [f"{path} holds an unresolved build setting" for path in unresolved_settings(info)]
    if missing:
        print("sdk-linked: FAIL missing")
        print("\n".join("  " + item for item in missing))
        return 1
    print(f"sdk-linked: PASS {app.name} executable={size} bytes, SDK families present: "
          + ", ".join(name for name in MONETIZED_FAMILIES))
    return 0


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_subparsers(dest="mode", required=True)
    modes.add_parser("source")
    app = modes.add_parser("app")
    app.add_argument("--expect", choices=("auto", "free", "monetized"), default="auto")
    app.add_argument("app", type=Path)
    plist = modes.add_parser("plist")
    action = plist.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.mode == "plist":
        if args.write:
            MONETIZED_PLIST.write_bytes(plistlib.dumps(expected_monetized_plist(), sort_keys=True))
        problems = plist_problems()
        if problems:
            print("\n".join(problems))
            print(f"plist: FAIL {len(problems)} problem(s)")
            return 1
        print("plist: PASS")
        return 0
    if args.mode == "source":
        problems = source_problems()
        if problems:
            print("\n".join(problems))
            print(f"source: FAIL {len(problems)} SDK import(s) outside #if {CONDITION}")
            return 1
        print("source: PASS")
        return 0
    return check_app(args.app, args.expect)


if __name__ == "__main__":
    sys.exit(main())
