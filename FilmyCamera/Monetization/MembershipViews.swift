import AuthenticationServices
import StoreKit
import GoogleSignInSwift
import SwiftUI
import UIKit

@MainActor
enum MembershipPresentation {
    static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    static var topController: UIViewController? {
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        return top(from: root)
    }

    private static func top(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController, !presented.isBeingDismissed { return top(from: presented) }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return top(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController { return top(from: selected) }
        return controller
    }

    private static weak var paywall: UIViewController?

    static func showPaywall(feature: PremiumFeature? = nil) {
        #if DEBUG
        // Hosted unit tests exercise the policy without presenting UI over
        // unrelated test cases. The UI-test app has no XCTest host variable.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #endif
        guard MonetizationConfiguration.isEnabled, paywall == nil, let presenter = topController, !presenter.isBeingDismissed else { return }
        // Present from the topmost sheet, not a competing root SwiftUI sheet.
        // A recipe editor can therefore explain its lock without disappearing.
        let host = UIHostingController(rootView: MembershipPaywall(feature: feature))
        host.modalPresentationStyle = .pageSheet
        host.view.backgroundColor = .systemBackground
        host.sheetPresentationController?.prefersGrabberVisible = true
        host.sheetPresentationController?.detents = [.large()]
        paywall = host
        presenter.present(host, animated: true)
    }

    static func dismissPaywall() {
        paywall?.dismiss(animated: true)
        paywall = nil
    }

    static func manageSubscription() async {
        guard let scene else { return }
        do { try await AppStore.showManageSubscriptions(in: scene) }
        catch { MembershipStore.shared.notice = "Subscriptions could not be opened. Manage them in your Apple Account settings." }
        await MembershipStore.shared.refresh()
    }
}

struct MembershipPaywall: View {
    let feature: PremiumFeature?
    @ObservedObject private var membership = MembershipStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FILMY PRO").font(.caption.weight(.bold)).tracking(3).foregroundStyle(FilmyTheme.accent)
                        Text("More room to create.").font(.largeTitle.bold())
                        Text(feature.map { "Unlock \($0.rawValue.lowercased()) and every Pro feature." }
                            ?? "Your whole film library. Every camera control. No daily limit. No ads.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        benefit("Unlimited photos, without ads", symbol: "camera")
                        benefit("Every film stock and custom recipe", symbol: "camera.filters")
                        benefit("Manual controls and advanced shooting tools", symbol: "slider.horizontal.3")
                        benefit("Photo imports, editing, and print finishes", symbol: "photo.on.rectangle")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
                    purchaseSection
                    if let message = membership.purchaseMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("membership-purchase-message")
                    }
                    Button("Restore Purchases") { Task { await membership.restore() } }
                        .disabled(membership.isWorking)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("membership-restore")
                    legalSection
                    Text("Prefer to stay free? Keep 10 photos each day and three starter looks. Your saved photos remain yours.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Filmy Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { MembershipPresentation.dismissPaywall() }
                        .accessibilityIdentifier("membership-close")
                }
            }
        }
        .tint(FilmyTheme.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("membership-paywall")
        .task { await membership.loadProduct(); await membership.refresh() }
        .onChange(of: membership.isPremium) { _, premium in
            if premium { MembershipPresentation.dismissPaywall() }
        }
    }

    private func benefit(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if membership.isPremium {
            Text("Pro is active").font(.title2.bold())
            Button("Manage Subscription") { Task { await MembershipPresentation.manageSubscription() } }
        } else if let product = membership.product {
            VStack(alignment: .leading, spacing: 12) {
                if membership.eligibleForOneMonthTrial {
                    Text("1 month free").font(.title.bold())
                    Text("Then \(product.displayPrice) per month. Auto-renews unless canceled.")
                        .font(.body.weight(.medium))
                } else {
                    Text("\(product.displayPrice) per month").font(.title.bold())
                    Text("Billed monthly. Auto-renews unless canceled.").font(.body)
                }
                Button {
                    Task { await membership.purchase() }
                } label: {
                    HStack {
                        Spacer()
                        if membership.isWorking { ProgressView() }
                        Text(membership.eligibleForOneMonthTrial ? "Start 1-Month Free Trial" : "Subscribe Monthly")
                            .font(.headline)
                        Spacer()
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!membership.canPurchase)
                .accessibilityIdentifier("membership-purchase")
                if !MonetizationConfiguration.legalLinksConfigured {
                    Text("Subscription terms are not available yet. Purchases are temporarily disabled.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if membership.isLoadingProduct { ProgressView("Loading App Store price") }
                else {
                    Text("The App Store offer is currently unavailable.").font(.headline)
                    Button("Retry") { Task { await membership.loadProduct() } }
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payment is charged to your Apple Account after confirmation. Eligible new subscribers receive the trial shown above. "
                + "After the trial, the subscription renews at the displayed monthly price unless canceled. "
                + "Cancel at least 24 hours before the current period ends in Apple Account settings. "
                + "Signing out or deleting your Filmy account does not cancel a subscription.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                if let terms = MonetizationConfiguration.termsURL { Link("Terms of Use", destination: terms) }
                if let privacy = MonetizationConfiguration.privacyURL { Link("Privacy Policy", destination: privacy) }
            }
            .font(.footnote).frame(minHeight: 44)
        }
    }
}

/// Even an already-open premium sheet responds to entitlement revocation.
struct PremiumFeatureGate<Content: View>: View {
    let feature: PremiumFeature
    @ViewBuilder var content: () -> Content
    @ObservedObject private var membership = MembershipStore.shared

    var body: some View {
        if membership.hasFullAccess { content() }
        else {
            VStack(spacing: 20) {
                Text(feature.rawValue).font(.title2.bold())
                Text("Included with Filmy Pro. Trial and paid subscribers get every feature without ads.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("View Filmy Pro") { MembershipPresentation.showPaywall(feature: feature) }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
            .padding(28)
        }
    }
}

struct MembershipStatusBar: View {
    @ObservedObject private var membership = MembershipStore.shared

    var body: some View {
        if !membership.hasFullAccess {
            HStack(spacing: 12) {
                Text(membership.entitlementsResolved ? "\(membership.remainingPhotos) of 10 photos left today" : "Checking App Store access")
                    .font(.caption.weight(.medium)).accessibilityIdentifier("membership-photo-allowance")
                Spacer(minLength: 4)
                Button("Go Pro") { MembershipPresentation.showPaywall() }
                    .font(.caption.bold()).frame(minHeight: 44).accessibilityIdentifier("membership-upgrade")
            }
            .padding(.horizontal, 20)
            .background(FilmyTheme.background)
        }
    }
}

struct AccountSettingsSection: View {
    @ObservedObject private var membership = MembershipStore.shared
    @ObservedObject private var authentication = AuthenticationStore.shared
    @ObservedObject private var advertising = AdvertisingStore.shared
    @State private var isConfirmingDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account & Filmy Pro").font(.title3.bold())
            Text(membership.isTrial ? "Your free trial is active" : membership.isPremium ? "Filmy Pro is active" : "Free camera")
                .font(.headline)
            if case .premium(let expiry, _) = membership.access {
                Text("Access through \(expiry.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("10 photos per day, three starter looks, and ads outside the camera. Pro unlocks every feature and removes ads.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Explore Filmy Pro") { MembershipPresentation.showPaywall() }.buttonStyle(.borderedProminent)
            }
            HStack(spacing: 16) {
                Button("Restore Purchases") { Task { await membership.restore() } }
                    .disabled(membership.isWorking)
                Button("Manage Subscription") { Task { await MembershipPresentation.manageSubscription() } }
            }
            .font(.footnote).frame(minHeight: 44)
            if let message = membership.purchaseMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Divider()
            accountControls
            if let message = authentication.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            if advertising.requiresPrivacyOptions {
                Button("Ad Privacy Choices") { Task { await advertising.showPrivacyOptions() } }.frame(minHeight: 44)
            }
            if let message = advertising.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(20)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .confirmationDialog("Delete your Filmy account?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await authentication.deleteAccount() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will verify your sign-in again. Your account will be permanently deleted. Saved photos remain. "
                + "An App Store subscription must be canceled separately using Manage Subscription.")
        }
        .accessibilityIdentifier("membership-account-settings")
        .task { await advertising.refreshPrivacyOptions() }
    }

    @ViewBuilder
    private var accountControls: some View {
        if let identity = authentication.identity {
            Text(identity.name ?? identity.email ?? "Signed in").font(.headline)
            if let email = identity.email, identity.name != nil { Text(email).font(.footnote).foregroundStyle(.secondary) }
            HStack(spacing: 24) {
                Button("Sign Out", action: authentication.signOut)
                Button("Delete Account", role: .destructive) { isConfirmingDeletion = true }
            }
            .frame(minHeight: 44).disabled(authentication.isWorking)
        } else {
            Text("Sign in, or keep shooting as a guest.").font(.headline)
            Text("Sign-in is optional. Purchases and restores use your Apple Account, not your Filmy sign-in. Photos stay on this device.")
                .font(.footnote).foregroundStyle(.secondary)
            if authentication.isConfigured {
                SignInWithAppleButton(.signIn, onRequest: authentication.prepareApple) { result in
                    Task { await authentication.completeApple(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(authentication.isWorking)
                GoogleSignInButton { Task { await authentication.signInWithGoogle() } }
                .frame(height: 48).disabled(authentication.isWorking)
                .accessibilityIdentifier("membership-google-sign-in")
            } else {
                Text("Account sign-in is not available in this build. Guest access and App Store purchases do not require it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        if authentication.isWorking { ProgressView("Verifying account") }
    }
}

struct MonetizationRootModifier: ViewModifier {
    let camera: CameraService
    let viewModel: CameraViewModel
    @ObservedObject private var membership = MembershipStore.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                synchronizeAccess()
                await membership.start()
                await AuthenticationStore.shared.checkAppleCredential()
                synchronizeAccess()
            }
            .onOpenURL { _ = AuthenticationStore.shared.handle($0) }
            .onChange(of: membership.access) { _, _ in synchronizeAccess() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await membership.refresh()
                        await AuthenticationStore.shared.checkAppleCredential()
                        synchronizeAccess()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                Task { await membership.refresh(); synchronizeAccess() }
            }
            .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                Task { await AuthenticationStore.shared.checkAppleCredential() }
            }
            .alert("Filmy Pro", isPresented: Binding(
                get: { membership.notice != nil }, set: { if !$0 { membership.notice = nil } }
            )) {
                Button("OK", role: .cancel) { membership.notice = nil }
            } message: { Text(membership.notice ?? "") }
    }

    private func synchronizeAccess() {
        camera.setPremiumControlsEnabled(membership.hasFullAccess)
        viewModel.objectWillChange.send()
        AdvertisingStore.shared.accessChanged()
    }
}
