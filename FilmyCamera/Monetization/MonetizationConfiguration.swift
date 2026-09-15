import Foundation

// Public client identifiers only. Never ship provider private keys or service
// accounts. Prices and introductory offers come from StoreKit, not these files.
enum MonetizationConfiguration {
    static func value(_ key: String) -> String {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("$(") ? "" : value
    }

    static var monthlyProductID: String {
        let configured = value("FilmyMonthlyProductID")
        return configured.isEmpty ? "com.dheeraj.filmycamera.pro.monthly" : configured
    }

    static var privacyURL: URL? { secureURL("FilmyPrivacyPolicyURL") }
    static var termsURL: URL? { secureURL("FilmyTermsURL") }
    static var legalLinksConfigured: Bool {
        value("FilmyLegalReady").uppercased() == "YES" && privacyURL != nil && termsURL != nil
    }
    static var bannerID: String { value("FilmyAdMobBannerID") }
    static var adsConfigured: Bool {
        guard legalLinksConfigured, value("FilmyAdsEnabled").uppercased() == "YES",
              value("GADApplicationIdentifier").hasPrefix("ca-app-pub-"),
              bannerID.hasPrefix("ca-app-pub-") else { return false }
        #if !DEBUG
        // Shipping Google's test publisher IDs must never enable release ads.
        guard !value("GADApplicationIdentifier").contains("3940256099942544"),
              !bannerID.contains("3940256099942544") else { return false }
        #endif
        return true
    }

    private static func secureURL(_ key: String) -> URL? {
        guard let url = URL(string: value(key)), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    static var isAutomatedTest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-testing") })
        #else
        return false
        #endif
    }
}
