#!/usr/bin/env python3
"""Check Apple's minimum submission SDK, without signing or contacting Apple.

Policy checked September 8, 2026:
https://developer.apple.com/news/upcoming-requirements/
Since April 28, 2026, iOS uploads require Xcode 26+ and the iOS 26+ SDK.
This is a build-toolchain requirement, not the app's deployment target.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from xml.parsers.expat import ExpatError

MINIMUM_XCODE_MAJOR = 26
MINIMUM_IOS_SDK_MAJOR = 26
REQUIREMENT = "App Store uploads require Xcode 26+ and the iOS 26+ SDK (effective April 28, 2026)."


def version(value, field):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,3}(?:\.[0-9]{1,3}){0,2}", value):
        raise ValueError(f"{field} is missing or is not a numeric version")
    return tuple(int(part) for part in value.split("."))


def validate_versions(xcode, sdk):
    if version(xcode, "Xcode version")[0] < MINIMUM_XCODE_MAJOR:
        raise ValueError("The selected Xcode is too old for App Store submission")
    if version(sdk, "iOS SDK version")[0] < MINIMUM_IOS_SDK_MAJOR:
        raise ValueError("The selected iOS SDK is too old for App Store submission")
    return {"xcode": xcode, "iosSDK": sdk}


def command_output(command):
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as error:
        # Do not echo arbitrary subprocess output into CI or expose account data.
        raise ValueError(f"Unable to inspect {command[0]}; select an installed Xcode with DEVELOPER_DIR") from error
    return result.stdout.strip()


def validate_current():
    output = command_output(["xcodebuild", "-version"])
    matches = re.findall(r"^Xcode ([0-9]+(?:\.[0-9]+){0,2})$", output, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("xcodebuild did not report one unambiguous Xcode version")
    sdk = command_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"])
    return validate_versions(matches[0], sdk)


def validate_app_info(info):
    if not isinstance(info, dict):
        raise ValueError("The built app Info.plist must be a dictionary")
    if info.get("DTPlatformName") != "iphoneos":
        raise ValueError("The built app must target the physical iOS platform, not a simulator")
    sdk_name = info.get("DTSDKName")
    if not isinstance(sdk_name, str) or not sdk_name.startswith("iphoneos"):
        raise ValueError("The built app has no valid physical iOS DTSDKName")
    sdk = sdk_name[len("iphoneos"):]
    sdk_parts = version(sdk, "DTSDKName")
    encoded_xcode = info.get("DTXcode")
    if not isinstance(encoded_xcode, str) or not re.fullmatch(r"[1-9][0-9]{3,4}", encoded_xcode):
        raise ValueError("The built app has no valid DTXcode build-toolchain stamp")
    # Apple's DTXcode stamp uses the last two digits for minor/patch, e.g. 2641.
    xcode_major = str(int(encoded_xcode) // 100)
    result = validate_versions(xcode_major, sdk)
    platform_parts = version(info.get("DTPlatformVersion"), "DTPlatformVersion")
    if platform_parts + (0,) * (3 - len(platform_parts)) != sdk_parts + (0,) * (3 - len(sdk_parts)):
        raise ValueError("The built app's DTPlatformVersion and DTSDKName disagree")
    result["xcodeBuildStamp"] = encoded_xcode
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--current", action="store_true", help="Check the selected Xcode before creating an archive")
    mode.add_argument("--app-info", type=Path, help="Check the recorded SDK in a built app's Info.plist")
    args = parser.parse_args(argv)
    try:
        if args.current:
            report = validate_current()
        else:
            with args.app_info.open("rb") as source:
                report = validate_app_info(plistlib.load(source))
    except (ValueError, OSError, plistlib.InvalidFileException, ExpatError) as error:
        print(f"Release SDK check failed: {error}. {REQUIREMENT}", file=sys.stderr)
        return 1
    print("Release SDK minimum verified: " + json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
