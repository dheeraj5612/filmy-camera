import Combine
@preconcurrency import GoogleMobileAds
import SwiftUI
import UIKit
@preconcurrency import UserMessagingPlatform

/// No requests or SDK startup before the App Store and privacy checks finish.
/// Banners exist only in non-camera destinations and are destroyed on upgrade.
@MainActor
final class AdvertisingStore: ObservableObject {
    static let shared = AdvertisingStore()
    @Published private(set) var isReady = false
    @Published private(set) var requiresPrivacyOptions = false
    @Published private(set) var revision = 0
    @Published var message: String?
    private var isPreparing = false
    private var didUpdateConsent = false
    private var didStartSDK = false

    func prepare() async {
        guard !MonetizationConfiguration.isAutomatedTest,
              MonetizationConfiguration.adsConfigured,
              MembershipStore.shared.mayShowAds, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        if !didUpdateConsent {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                didUpdateConsent = true
                requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                guard MembershipStore.shared.mayShowAds else { return }
                try await ConsentForm.loadAndPresentIfRequired(from: MembershipPresentation.topController)
            } catch {
                // Fail closed, even if a previous session had consent. The
                // camera remains usable and a later visit can retry.
                didUpdateConsent = false
                isReady = false
                requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                return
            }
        }
        guard MembershipStore.shared.mayShowAds, ConsentInformation.shared.canRequestAds else {
            isReady = false
            return
        }
        if !didStartSDK {
            // Keep SDK startup serialized. Do not initialize any mediation SDK.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in continuation.resume() }
            }
            didStartSDK = true
        }
        isReady = MembershipPolicy.showsAds(
            entitlementsResolved: MembershipStore.shared.entitlementsResolved,
            premium: MembershipStore.shared.isPremium,
            consentReady: ConsentInformation.shared.canRequestAds,
            configured: MonetizationConfiguration.adsConfigured
        )
    }

    func refreshPrivacyOptions() async {
        guard !MonetizationConfiguration.isAutomatedTest,
              MonetizationConfiguration.adsConfigured, !isPreparing, !didUpdateConsent else { return }
        guard MembershipStore.shared.isPremium else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            // Leave didUpdateConsent false: a future free session must still
            // present any required consent form before ad SDK initialization.
        } catch { /* No ad request is made when privacy status is unavailable. */ }
    }

    func accessChanged() {
        if !MembershipStore.shared.mayShowAds {
            isReady = false
            revision += 1
        }
    }

    func showPrivacyOptions() async {
        guard requiresPrivacyOptions, !isPreparing else { return }
        isPreparing = true
        isReady = false
        revision += 1 // Dispose any banner that was loaded under the old choices.
        defer { isPreparing = false }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: MembershipPresentation.topController)
            requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            isReady = didStartSDK && MembershipStore.shared.mayShowAds && ConsentInformation.shared.canRequestAds
        } catch { message = "Privacy options could not be opened. Please try again." }
    }
}

struct MonetizationBanner: View {
    @ObservedObject private var membership = MembershipStore.shared
    @ObservedObject private var advertising = AdvertisingStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if membership.mayShowAds && advertising.isReady && scenePhase == .active {
                VStack(spacing: 4) {
                    Text("Advertisement").font(.caption2).foregroundStyle(.secondary)
                    AdMobBannerView()
                        .id(advertising.revision)
                        .frame(width: 320, height: 50)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityIdentifier("free-tier-advertisement")
            }
        }
        .task(id: membership.access) { await advertising.prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await advertising.prepare() } }
        }
    }
}

private struct AdMobBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = MonetizationConfiguration.bannerID
        banner.rootViewController = MembershipPresentation.topController
        // Do not pass Firebase IDs, photo content, location, or targeting data.
        // UMP still determines whether non-personalized/limited ads can serve.
        if MembershipStore.shared.mayShowAds && AdvertisingStore.shared.isReady {
            let request = Request()
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            banner.load(request)
        }
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        banner.isHidden = !MembershipStore.shared.mayShowAds || !AdvertisingStore.shared.isReady
        // Never reload during a SwiftUI redraw. AdMob owns visible refreshes.
    }

    static func dismantleUIView(_ banner: BannerView, coordinator: ()) {
        banner.delegate = nil
        banner.rootViewController = nil
        banner.isHidden = true
        banner.removeFromSuperview()
    }
}
