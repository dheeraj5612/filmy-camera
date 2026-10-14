#!/usr/bin/env python3
"""Validate non-secret monetization source/configuration without network access."""
import json
import plistlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIGN_IN_ENTITLEMENT = "com.apple.developer.applesignin"
ACCOUNT_TYPES = {"NSPrivacyCollectedDataTypeName", "NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypeUserID"}

def xcconfig_value(name, text):
    value = None
    for line in text.splitlines():
        key, sep, rest = line.partition("=")
        if sep and key.strip() == name:
            value = rest.split("//")[0].strip()
    return value

def main():
    info = plistlib.loads((ROOT / "FilmyCamera/Info.plist").read_bytes())
    entitlements = plistlib.loads((ROOT / "FilmyCamera/FilmyCamera.entitlements").read_bytes())
    privacy = plistlib.loads((ROOT / "FilmyCamera/Resources/PrivacyInfo.xcprivacy").read_bytes())
    fixture = json.loads((ROOT / "StoreKit/Filmy.storekit").read_text())
    assert entitlements[SIGN_IN_ENTITLEMENT] == ["Default"]
    release_entitlements = plistlib.loads((ROOT / "FilmyCamera/FilmyCamera.Release.entitlements").read_bytes())
    assert SIGN_IN_ENTITLEMENT not in release_entitlements
    debug_cfg = (ROOT / "Config/Monetization.Debug.xcconfig").read_text()
    release_cfg = (ROOT / "Config/Monetization.Release.xcconfig").read_text()
    for line in release_cfg.splitlines():
        key = line.partition("=")[0].strip()
        assert not key.startswith(("FILMY_MONETIZATION_ENABLED[", "FILMY_ADS_ENABLED[", "FILMY_LEGAL_READY[")), line
    assert xcconfig_value("CODE_SIGN_ENTITLEMENTS", debug_cfg) == "FilmyCamera/FilmyCamera.entitlements"
    # Exact case: the build settings derive the SDK link from this value, and only YES/NO select a branch.
    release_flag = xcconfig_value("FILMY_MONETIZATION_ENABLED", release_cfg)
    assert release_flag in ("YES", "NO"), release_flag
    assert xcconfig_value("FILMY_MONETIZATION_ENABLED", debug_cfg) == "YES", "Debug must stay monetized"
    monetized_release = release_flag == "YES"
    expected_release_entitlements = "FilmyCamera/FilmyCamera.entitlements" if monetized_release else "FilmyCamera/FilmyCamera.Release.entitlements"
    assert xcconfig_value("CODE_SIGN_ENTITLEMENTS", release_cfg) == expected_release_entitlements
    assert "CODE_SIGN_ENTITLEMENTS" not in (ROOT / "project.yml").read_text()
    scheme = xcconfig_value("FILMY_GOOGLE_REVERSED_CLIENT_ID", release_cfg)
    assert scheme is not None and "configure-before-enabling" not in scheme
    if not monetized_release:
        assert scheme == "$(PRODUCT_BUNDLE_IDENTIFIER)"
    else:
        assert scheme.startswith("com.googleusercontent.apps.") and scheme != ""
    assert info["FilmyMonthlyProductID"] == "$(FILMY_MONTHLY_PRODUCT_ID)"
    monetized = plistlib.loads((ROOT / "Config/Info.Monetized.plist").read_bytes())
    assert monetized["GADDelayAppMeasurementInit"] is True
    assert monetized["FirebaseAnalyticsCollectionEnabled"] is False
    sdk_keys = ("FilmyAdMobBannerID", "GADApplicationIdentifier", "GADDelayAppMeasurementInit",
                "FirebaseAnalyticsCollectionEnabled", "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS",
                "CFBundleURLTypes", "SKAdNetworkItems")
    for key in sdk_keys:
        assert key not in info, f"FilmyCamera/Info.plist must not hold {key}; it belongs to Config/Info.Monetized.plist"
    assert "NSUserTrackingUsageDescription" not in info
    fields = {item["NSPrivacyCollectedDataType"] for item in privacy["NSPrivacyCollectedDataTypes"]}
    assert privacy["NSPrivacyTracking"] is False
    if monetized_release:
        # Account and advertising entries required by docs/app-store/app-privacy.md before any monetized build.
        assert ACCOUNT_TYPES <= fields, "monetized Release needs account data types in PrivacyInfo.xcprivacy"
        assert {"NSPrivacyCollectedDataTypeDeviceID", "NSPrivacyCollectedDataTypeAdvertisingData"} <= fields, "monetized Release needs advertising data types"
    else:
        assert not fields, "free Release must not declare collected data it does not collect"
    subscriptions = fixture["subscriptionGroups"][0]["subscriptions"]
    assert len(subscriptions) == 1
    subscription = subscriptions[0]
    assert subscription["productID"] == "com.dheeraj.filmycamera.pro.monthly"
    assert subscription["recurringSubscriptionPeriod"] == "P1M"
    assert subscription["introductoryOffer"]["paymentMode"] == "free"
    assert subscription["introductoryOffer"]["subscriptionPeriod"] == "P1M"
    release = (ROOT / "Config/Monetization.Release.xcconfig").read_text()
    assert xcconfig_value("FILMY_ADS_ENABLED", release) == "NO"
    assert xcconfig_value("FILMY_LEGAL_READY", release) == "NO"
    config = (ROOT / "FilmyCamera/Monetization/MonetizationConfiguration.swift").read_text()
    assert "#if !DEBUG" in config and 'contains("3940256099942544")' in config
    assert "#if DEBUG" in config
    project = (ROOT / "project.yml").read_text()
    assert "storeKitConfiguration: StoreKit/Filmy.storekit" in project
    assert "product: FirebaseAnalytics" not in project
    assert "exactVersion: 12.14.0" in project and "exactVersion: 3.0.0" in project
    assert "$(FILMY_MONETIZATION_LDFLAGS)" in project, "OTHER_LDFLAGS must derive -ObjC from the monetization flag"
    assert '"-ObjC"' not in project, "project.yml must not hard-code -ObjC"
    for mode in (["source"], ["plist", "--check"]):
        result = subprocess.run([sys.executable, str(ROOT / "scripts/monetization/sdk_gate.py"), *mode],
                                capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
    print("Monetization configuration, release defaults, privacy declarations and one-month StoreKit fixture: PASS")

if __name__ == "__main__":
    main()
