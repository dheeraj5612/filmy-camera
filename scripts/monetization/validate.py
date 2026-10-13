#!/usr/bin/env python3
"""Validate non-secret monetization source/configuration without network access."""
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIGN_IN_ENTITLEMENT = "com.apple.developer.applesignin"
ACCOUNT_TYPES = {"NSPrivacyCollectedDataTypeName", "NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypeUserID"}

def xcconfig_value(name, text):
    value = None
    for line in text.splitlines():
        key, sep, rest = line.partition("=")
        if sep and key.strip() == name:
            value = rest.strip()
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
    assert xcconfig_value("CODE_SIGN_ENTITLEMENTS", debug_cfg) == "FilmyCamera/FilmyCamera.entitlements"
    monetized_release = xcconfig_value("FILMY_MONETIZATION_ENABLED", release_cfg) == "YES"
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
    assert info["GADDelayAppMeasurementInit"] is True
    assert info["FirebaseAnalyticsCollectionEnabled"] is False
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
    assert "FILMY_ADS_ENABLED = NO" in release
    assert "FILMY_LEGAL_READY = NO" in release
    config = (ROOT / "FilmyCamera/Monetization/MonetizationConfiguration.swift").read_text()
    assert "#if !DEBUG" in config and 'contains("3940256099942544")' in config
    assert "#if DEBUG" in config
    project = (ROOT / "project.yml").read_text()
    assert "storeKitConfiguration: StoreKit/Filmy.storekit" in project
    assert "product: FirebaseAnalytics" not in project
    assert "exactVersion: 12.14.0" in project and "exactVersion: 3.0.0" in project
    print("Monetization configuration, release defaults, privacy declarations and one-month StoreKit fixture: PASS")

if __name__ == "__main__":
    main()
