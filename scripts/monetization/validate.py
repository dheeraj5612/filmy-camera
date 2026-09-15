#!/usr/bin/env python3
"""Validate non-secret monetization source/configuration without network access."""
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def main():
    info = plistlib.loads((ROOT / "FilmyCamera/Info.plist").read_bytes())
    entitlements = plistlib.loads((ROOT / "FilmyCamera/FilmyCamera.entitlements").read_bytes())
    privacy = plistlib.loads((ROOT / "FilmyCamera/Resources/PrivacyInfo.xcprivacy").read_bytes())
    fixture = json.loads((ROOT / "StoreKit/Filmy.storekit").read_text())
    assert entitlements["com.apple.developer.applesignin"] == ["Default"]
    assert info["FilmyMonthlyProductID"] == "$(FILMY_MONTHLY_PRODUCT_ID)"
    assert info["GADDelayAppMeasurementInit"] is True
    assert info["FirebaseAnalyticsCollectionEnabled"] is False
    assert "NSUserTrackingUsageDescription" not in info
    fields = {item["NSPrivacyCollectedDataType"] for item in privacy["NSPrivacyCollectedDataTypes"]}
    assert {"NSPrivacyCollectedDataTypeName", "NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypeUserID"} <= fields
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
